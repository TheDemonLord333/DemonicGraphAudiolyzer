import Foundation

/// Generates the mono PCM signal of a `SoundPlan`, sequentially and in chunks of any size.
///
/// The *same* renderer is used for the preview (whole pass rendered ahead of playback) and for
/// the export (rendered chunk by chunk while encoding). Output depends only on the plan, never on
/// chunk sizes, system volume or the playback state.
///
/// Signal chain "Graph vertonen":
///   x(t) → y = f(x) → u → frequency → glide (one-pole on log2 f) → phase += f / sampleRate
///   → oscillator (sine / band-limited triangle / band-limited rich) → mute ramp → fades → level
/// Signal chain "Formel als Klangwelle":
///   p(t) = frac(baseFrequency · t) → band-limited wavetable(p) → fades → level
final class PCMRenderer {
    /// Linear ramp used to mute/unmute at definition gaps.
    static let muteRampMilliseconds = 5.0

    let plan: SoundPlan
    let totalFrames: Int
    private(set) var position: Int = 0

    // Oscillator state
    private var phase: Double = 0               // cycles, 0 ≤ phase < 1 (radians / 2π)
    private var logFrequency: Double = 0        // log2(Hz), smoothed
    private var gain: Double = 0                // mute gain 0 … 1
    private var hasFrequency = false

    // Pre-computed constants
    private let sampleRate: Double
    private let level: Double
    private let fadeFrames: Int
    private let glideCoefficient: Double
    private let gainStep: Double
    private let maximumFrequency: Double

    init(plan: SoundPlan) {
        self.plan = plan
        self.totalFrames = plan.frameCount
        self.sampleRate = plan.sampleRate
        let settings = plan.settings
        self.level = settings.linearLevel
        let requestedFade = Int((settings.fadeMilliseconds / 1000 * plan.sampleRate).rounded())
        self.fadeFrames = max(1, min(requestedFade, plan.frameCount / 2))
        if settings.glideMilliseconds > 0 {
            let tau = settings.glideMilliseconds / 1000 * plan.sampleRate
            self.glideCoefficient = 1 - exp(-1 / tau)
        } else {
            self.glideCoefficient = 1
        }
        self.gainStep = 1 / max(1, Self.muteRampMilliseconds / 1000 * plan.sampleRate)
        self.maximumFrequency = 0.45 * plan.sampleRate
    }

    var isFinished: Bool { position >= totalFrames }

    /// Renders up to `capacity` frames into `output`. Returns the number of frames written (0 at the end).
    @discardableResult
    func render(into output: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        let count = min(capacity, totalFrames - position)
        guard count > 0 else { return 0 }
        switch plan.settings.mode {
        case .graph:
            renderGraph(into: output, count: count)
        case .waveform:
            renderWaveform(into: output, count: count)
        case .synthesizer, .pendulum:
            output.update(repeating: 0, count: count)
        }
        position += count
        return count
    }

    /// Convenience: renders the complete pass.
    func renderAll() -> [Float] {
        var samples = [Float](repeating: 0, count: totalFrames - position)
        samples.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = render(into: base + offset, capacity: min(65_536, buffer.count - offset))
                if written == 0 { break }
                offset += written
            }
        }
        return samples
    }

    // MARK: Envelope

    /// Raised-cosine fade-in/out at the beginning and end of the pass.
    @inline(__always)
    private func envelope(at frame: Int) -> Double {
        if frame < fadeFrames {
            return 0.5 - 0.5 * cos(Double.pi * Double(frame) / Double(fadeFrames))
        }
        let remaining = totalFrames - 1 - frame
        if remaining < fadeFrames {
            return 0.5 - 0.5 * cos(Double.pi * Double(max(remaining, 0)) / Double(fadeFrames))
        }
        return 1
    }

    // MARK: Graph vertonen

    private func renderGraph(into output: UnsafeMutablePointer<Float>, count: Int) {
        let function = plan.function
        let settings = plan.settings
        let xMin = settings.playXMin
        let xSpan = settings.playXMax - settings.playXMin
        let total = Double(totalFrames)
        let bank = plan.timbreBank
        let canSound = plan.pitchRange.hasDefinedValues

        for index in 0..<count {
            let frame = position + index
            let x = xMin + xSpan * (Double(frame) / total)
            let y = function(x)
            let defined = canSound && !y.isNaN
            if defined {
                let target = log2(plan.targetFrequency(forY: y))
                if !hasFrequency || gain <= 0 {
                    // Coming out of silence: start directly at the right pitch.
                    logFrequency = target
                    hasFrequency = true
                } else {
                    logFrequency += (target - logFrequency) * glideCoefficient
                }
                gain = min(1, gain + gainStep)
            } else {
                gain = max(0, gain - gainStep)
            }

            var sample = 0.0
            if gain > 0, hasFrequency {
                let frequency = min(exp2(logFrequency), maximumFrequency)
                let oscillator: Double
                if let bank {
                    oscillator = Double(bank.value(phase: phase, frequency: frequency))
                } else {
                    oscillator = sin(2 * Double.pi * phase)
                }
                sample = oscillator * gain
                phase += frequency / sampleRate
                if phase >= 1 { phase -= floor(phase) }
            }
            output[index] = Float(sample * level * envelope(at: frame))
        }
    }

    // MARK: Formel als Klangwelle

    private func renderWaveform(into output: UnsafeMutablePointer<Float>, count: Int) {
        guard let waveform = plan.waveform, !waveform.isSilent else {
            output.update(repeating: 0, count: count)
            return
        }
        let table = waveform.table
        let increment = plan.settings.baseFrequency / sampleRate
        for index in 0..<count {
            let frame = position + index
            // p(t) = frac(baseFrequency · t), computed from the frame index (no drift).
            let cycles = increment * Double(frame)
            let p = cycles - floor(cycles)
            let value = Double(table.value(atPhase: p))
            output[index] = Float(value * level * envelope(at: frame))
        }
    }
}
