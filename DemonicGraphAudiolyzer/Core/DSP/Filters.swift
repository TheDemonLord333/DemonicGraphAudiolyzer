import Foundation

/// Second-order IIR filter (RBJ audio EQ cookbook), transposed direct form II.
struct BiquadCoefficients: Equatable, Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    private static func normalized(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) -> BiquadCoefficients {
        BiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    private static func omega(_ frequency: Double, _ sampleRate: Double) -> (cos: Double, sin: Double) {
        let w = 2 * Double.pi * min(max(frequency, 1), 0.49 * sampleRate) / sampleRate
        return (cos(w), sin(w))
    }

    static func lowpass(frequency: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        let w = omega(frequency, sampleRate)
        let alpha = w.sin / (2 * q)
        return normalized((1 - w.cos) / 2, 1 - w.cos, (1 - w.cos) / 2, 1 + alpha, -2 * w.cos, 1 - alpha)
    }

    static func highpass(frequency: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        let w = omega(frequency, sampleRate)
        let alpha = w.sin / (2 * q)
        return normalized((1 + w.cos) / 2, -(1 + w.cos), (1 + w.cos) / 2, 1 + alpha, -2 * w.cos, 1 - alpha)
    }

    /// Band-pass with 0 dB peak gain.
    static func bandpass(frequency: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        let w = omega(frequency, sampleRate)
        let alpha = w.sin / (2 * q)
        return normalized(alpha, 0, -alpha, 1 + alpha, -2 * w.cos, 1 - alpha)
    }
}

struct BiquadState: Sendable {
    private var z1 = 0.0
    private var z2 = 0.0

    @inline(__always)
    mutating func process(_ x: Double, _ c: BiquadCoefficients) -> Double {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

/// One-pole DC blocker: y[n] = x[n] − x[n−1] + R·y[n−1] (corner ≈ 10 Hz).
struct DCBlocker: Sendable {
    private let r: Double
    private var previousInput = 0.0
    private var previousOutput = 0.0

    init(sampleRate: Double, cornerFrequency: Double = 10) {
        r = exp(-2 * Double.pi * cornerFrequency / sampleRate)
    }

    @inline(__always)
    mutating func process(_ x: Double) -> Double {
        let y = x - previousInput + r * previousOutput
        previousInput = x
        previousOutput = y
        return y
    }
}

/// Deterministic white noise (xorshift64*), seeded – preview and export produce identical noise.
struct NoiseGenerator: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    /// Uniform in [−1, 1).
    @inline(__always)
    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return Double(value >> 11) / Double(1 << 52) - 1
    }

    /// Stable 64-bit hash of a string (FNV-1a) – Swift's `hashValue` is randomised per launch.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// Linear-phase low-pass FIR for oversampled formula signals (Kaiser-windowed sinc).
/// Pass band up to 0.4·fs_out, stop band from 0.5·fs_out (≈ 80 dB), so everything that would
/// fold back into the audible band is removed before decimation.
struct DecimationFilter: Sendable {
    let factor: Int
    let taps: [Double]
    /// (taps.count − 1) / 2 – the delay in oversampled samples.
    var halfLength: Int { (taps.count - 1) / 2 }

    init(factor: Int) {
        self.factor = max(1, factor)
        guard self.factor > 1 else {
            taps = [1]
            return
        }
        let halfLength = 24 * self.factor
        let count = 2 * halfLength + 1
        let cutoff = 0.45 / Double(self.factor)   // cycles per oversampled sample
        let beta = 8.0
        let denominator = Self.besselI0(beta)
        var coefficients = [Double](repeating: 0, count: count)
        var sum = 0.0
        for index in 0..<count {
            let n = Double(index - halfLength)
            let sinc = n == 0 ? 2 * cutoff : sin(2 * Double.pi * cutoff * n) / (Double.pi * n)
            let ratio = n / Double(halfLength)
            let window = Self.besselI0(beta * (max(0, 1 - ratio * ratio)).squareRoot()) / denominator
            coefficients[index] = sinc * window
            sum += coefficients[index]
        }
        taps = coefficients.map { $0 / sum }
    }

    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let quarter = x * x / 4
        for k in 1..<50 {
            term *= quarter / Double(k * k)
            sum += term
            if term < 1e-12 * sum { break }
        }
        return sum
    }
}
