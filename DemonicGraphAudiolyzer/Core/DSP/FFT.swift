import Foundation

/// Minimal iterative radix-2 complex FFT (used offline for wavetable construction only,
/// never inside the real-time audio path).
struct FFT {
    let size: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReversed: [Int]

    init(size: Int) {
        precondition(size >= 2 && (size & (size - 1)) == 0, "FFT size must be a power of two")
        self.size = size
        var cosTable = [Double](repeating: 0, count: size / 2)
        var sinTable = [Double](repeating: 0, count: size / 2)
        for index in 0..<(size / 2) {
            let angle = -2.0 * Double.pi * Double(index) / Double(size)
            cosTable[index] = cos(angle)
            sinTable[index] = sin(angle)
        }
        self.cosTable = cosTable
        self.sinTable = sinTable
        var bits = 0
        while (1 << bits) < size { bits += 1 }
        self.bitReversed = (0..<size).map { value in
            var reversed = 0
            var input = value
            for _ in 0..<bits {
                reversed = (reversed << 1) | (input & 1)
                input >>= 1
            }
            return reversed
        }
    }

    /// In-place forward transform (e^{-i…}). Set `inverse` for the unscaled inverse transform.
    func transform(real: inout [Double], imaginary: inout [Double], inverse: Bool = false) {
        precondition(real.count == size && imaginary.count == size)
        for index in 0..<size {
            let target = bitReversed[index]
            if target > index {
                real.swapAt(index, target)
                imaginary.swapAt(index, target)
            }
        }
        let sign: Double = inverse ? -1 : 1
        var length = 2
        while length <= size {
            let half = length / 2
            let tableStep = size / length
            var start = 0
            while start < size {
                for k in 0..<half {
                    let wr = cosTable[k * tableStep]
                    let wi = sign * sinTable[k * tableStep]
                    let evenIndex = start + k
                    let oddIndex = evenIndex + half
                    let oddReal = real[oddIndex] * wr - imaginary[oddIndex] * wi
                    let oddImaginary = real[oddIndex] * wi + imaginary[oddIndex] * wr
                    real[oddIndex] = real[evenIndex] - oddReal
                    imaginary[oddIndex] = imaginary[evenIndex] - oddImaginary
                    real[evenIndex] += oddReal
                    imaginary[evenIndex] += oddImaginary
                }
                start += length
            }
            length *= 2
        }
    }

    /// Harmonic coefficients of a real periodic signal of length `size`.
    /// Returns (cosine, sine) amplitudes for harmonics 0…size/2 such that
    /// signal[n] = Σ cos[k]·cos(2πkn/N) + sin[k]·sin(2πkn/N).
    func harmonics(of signal: [Double]) -> (cosine: [Double], sine: [Double]) {
        var real = signal
        var imaginary = [Double](repeating: 0, count: size)
        transform(real: &real, imaginary: &imaginary)
        let halfCount = size / 2
        var cosine = [Double](repeating: 0, count: halfCount + 1)
        var sine = [Double](repeating: 0, count: halfCount + 1)
        let scale = 2.0 / Double(size)
        for k in 0...halfCount {
            let factor = (k == 0 || k == halfCount) ? scale * 0.5 : scale
            cosine[k] = real[k] * factor
            sine[k] = -imaginary[k] * factor
        }
        return (cosine, sine)
    }

    /// Synthesises one period of length `size` from harmonic coefficients (inverse of `harmonics`).
    func synthesize(cosine: [Double], sine: [Double]) -> [Double] {
        var real = [Double](repeating: 0, count: size)
        var imaginary = [Double](repeating: 0, count: size)
        let halfCount = size / 2
        for k in 0...min(halfCount, cosine.count - 1) {
            let c = cosine[k]
            let s = k < sine.count ? sine[k] : 0
            if k == 0 || k == halfCount {
                real[k] = c
            } else {
                // X[k] = (c - i s) / 2 · N / N ... use conjugate symmetric spectrum.
                real[k] = c * 0.5
                imaginary[k] = -s * 0.5
                real[size - k] = c * 0.5
                imaginary[size - k] = s * 0.5
            }
        }
        transform(real: &real, imaginary: &imaginary, inverse: true)
        return real
    }
}
