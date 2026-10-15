import Foundation

/// Conversion of pitch formula values into frequencies (role A) and gains (role B).
enum PitchConversion {
    /// Lowest and highest frequency that is played (above: limited, never above 0.45·sampleRate).
    static let minimumFrequency = 8.0

    struct NormalizedRange: Equatable, Sendable {
        var yLow: Double
        var yHigh: Double
        var frequencyLow: Double
        var frequencyHigh: Double
    }

    /// Frequency in Hz for a formula value; nil = silent (undefined or not positive).
    static func frequency(value: Double, unit: PitchUnit, baseFrequency: Double,
                          quantization: ScaleQuantization, normalized: NormalizedRange?, maximum: Double) -> Double? {
        guard value.isFinite else { return nil }
        var frequency: Double
        switch unit {
        case .hertz:
            guard value > 0 else { return nil }
            frequency = value
        case .semitones:
            frequency = baseFrequency * exp2(value / 12)
        case .octaves:
            frequency = baseFrequency * exp2(value)
        case .normalized:
            guard let range = normalized else { return nil }
            let span = range.yHigh - range.yLow
            let u = span > 0 ? min(max((value - range.yLow) / span, 0), 1) : 0.5
            frequency = range.frequencyLow * pow(range.frequencyHigh / range.frequencyLow, u)
        }
        if quantization != .none {
            let semitones = 12 * log2(frequency / baseFrequency)
            frequency = baseFrequency * exp2(quantize(semitones: semitones, scale: quantization) / 12)
        }
        guard frequency.isFinite, frequency > 0 else { return nil }
        return min(max(frequency, minimumFrequency), maximum)
    }

    /// Snaps a semitone value to the nearest step of the scale in any octave (relative to the
    /// base frequency as root). Chromatic = nearest semitone. This is musical quantization –
    /// different from numeric rounding of the formula with floor/round.
    static func quantize(semitones: Double, scale: ScaleQuantization) -> Double {
        guard semitones.isFinite else { return semitones }
        if scale == .none { return semitones }
        if scale == .chromatic { return semitones.rounded() }
        let octave = floor(semitones / 12)
        let within = semitones - 12 * octave
        var best = 0.0
        var bestDistance = Double.infinity
        for step in scale.steps + [12] {
            let distance = abs(within - step)
            if distance < bestDistance - 1e-12 {
                bestDistance = distance
                best = step
            }
        }
        return 12 * octave + best
    }

    /// Gain of the amplitude role: linear values are clamped to 0 … 4 (negative = 0), dB values
    /// are converted with 10^(A/20); undefined or ≤ −120 dB is silent.
    @inline(__always)
    static func gain(value: Double, scale: AmplitudeScale) -> Double {
        guard value.isFinite else { return 0 }
        switch scale {
        case .linear:
            return min(max(value, 0), 4)
        case .decibels:
            if value <= -120 { return 0 }
            return min(pow(10, value / 20), 4)
        }
    }
}
