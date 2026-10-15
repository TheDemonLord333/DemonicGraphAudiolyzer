import Foundation

/// Generates the stereo mix of a `SynthPlan`, sequentially and in chunks of any size.
///
/// The *same* renderer is used for the preview and for the export. The output depends only on
/// the plan – never on chunk sizes, display frames or the playback state.
///
/// Mixing: every voice is rendered as its own signal, multiplied with its volume and
/// constant-power pan gains and *added as audio* (frequencies are never added).
/// The sum is scaled by the project level and a headroom factor 1/√N (N audible voices);
/// a soft limiter above −1 dBFS guarantees that the output never exceeds 0 dBFS.
final class SynthRenderer {
    static let blockFrames = 2_048
    /// Budget for the per-voice signals kept for the audio snippet display (16-bit samples).
    static let stemSampleBudget = 12_000_000

    let plan: SynthPlan
    let totalFrames: Int
    private(set) var position = 0
    /// Frames at which the safety limiter changed the signal.
    private(set) var limitedFrames = 0
    /// Per-voice signals (voice id → 16-bit samples) if requested and within budget.
    private(set) var stems: [UUID: [Int16]] = [:]

    private let voices: [VoiceRenderer]
    private var voiceBuffer: [Double]
    private var mixLeft: [Double]
    private var mixRight: [Double]
    private let captureStems: Bool

    init(plan: SynthPlan, captureStems: Bool = false) {
        self.plan = plan
        self.totalFrames = plan.frameCount
        self.voices = plan.voices.map { VoiceRenderer(plan: $0, synth: plan) }
        self.voiceBuffer = [Double](repeating: 0, count: Self.blockFrames)
        self.mixLeft = [Double](repeating: 0, count: Self.blockFrames)
        self.mixRight = [Double](repeating: 0, count: Self.blockFrames)
        self.captureStems = captureStems && plan.voices.count * plan.frameCount <= Self.stemSampleBudget
        if self.captureStems {
            for voice in plan.voices {
                stems[voice.voice.id] = []
                stems[voice.voice.id]?.reserveCapacity(plan.frameCount)
            }
        }
    }

    var isFinished: Bool { position >= totalFrames }

    /// Renders up to `capacity` stereo frames. Returns the number of frames written (0 at the end).
    @discardableResult
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        var written = 0
        while written < capacity, position < totalFrames {
            let count = min(Self.blockFrames, capacity - written, totalFrames - position)
            renderBlock(count: count, left: left + written, right: right + written)
            written += count
            position += count
        }
        return written
    }

    private func renderBlock(count: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        for index in 0..<count {
            mixLeft[index] = 0
            mixRight[index] = 0
        }
        for voice in voices {
            voiceBuffer.withUnsafeMutableBufferPointer { buffer in
                let pointer = buffer.baseAddress!
                pointer.update(repeating: 0, count: count)
                voice.render(into: pointer, from: position, count: count)
            }
            let gainLeft = voice.plan.gainLeft
            let gainRight = voice.plan.gainRight
            for index in 0..<count {
                let sample = voiceBuffer[index]
                mixLeft[index] += sample * gainLeft
                mixRight[index] += sample * gainRight
            }
            if captureStems {
                let id = voice.plan.voice.id
                let volume = max(voice.plan.gainLeft, voice.plan.gainRight)
                for index in 0..<count {
                    let value = min(max(voiceBuffer[index] * volume, -1), 1)
                    stems[id]?.append(Int16((value * 32_767).rounded()))
                }
            }
        }
        let gain = plan.masterGain
        for index in 0..<count {
            let (l, limitedL) = Self.limit(mixLeft[index] * gain)
            let (r, limitedR) = Self.limit(mixRight[index] * gain)
            if limitedL || limitedR { limitedFrames += 1 }
            left[index] = Float(l)
            right[index] = Float(r)
        }
    }

    /// Soft limiter: linear up to −1 dBFS, then a tanh knee that approaches ±1.
    @inline(__always)
    static func limit(_ value: Double) -> (Double, Bool) {
        let threshold = SynthPlan.limiterThreshold
        let magnitude = abs(value)
        guard magnitude > threshold else { return (value.isFinite ? value : 0, false) }
        guard value.isFinite else { return (0, true) }
        let headroom = 1 - threshold
        let limited = threshold + headroom * tanh((magnitude - threshold) / headroom)
        return (value < 0 ? -limited : limited, true)
    }

    /// Convenience: the complete pass.
    func renderAll() -> (left: [Float], right: [Float]) {
        let remaining = totalFrames - position
        var left = [Float](repeating: 0, count: remaining)
        var right = [Float](repeating: 0, count: remaining)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var offset = 0
                while offset < remaining {
                    let written = render(left: l.baseAddress! + offset, right: r.baseAddress! + offset,
                                         capacity: min(65_536, remaining - offset))
                    if written == 0 { break }
                    offset += written
                }
            }
        }
        return (left, right)
    }
}

/// Linear interpolation between control points every 16 frames, anchored at the trigger frame.
/// Values are always computed from the frame itself (never from chunk boundaries), so the
/// result does not depend on how the pass is split into blocks.
struct ControlLine {
    static let interval = 16
    private var anchor = 0
    private var segmentStart = Int.min
    private var a = 0.0
    private var b = 0.0

    mutating func reset(anchor: Int) {
        self.anchor = anchor
        segmentStart = Int.min
    }

    @inline(__always)
    mutating func value(at frame: Int, _ evaluate: (Int) -> Double) -> Double {
        let offset = frame - anchor
        let start = anchor + (offset >= 0 ? offset / Self.interval : (offset - Self.interval + 1) / Self.interval) * Self.interval
        if start != segmentStart {
            a = start == segmentStart + Self.interval ? b : evaluate(start)
            b = evaluate(start + Self.interval)
            segmentStart = start
        }
        if a.isNaN { return .nan }
        if b.isNaN { return a }
        return a + (b - a) * Double(frame - start) / Double(Self.interval)
    }
}

/// One sounding note of a voice.
private struct NoteInstance {
    var event: NoteEvent
    var endFrame: Int?
    var releaseRemaining = -1
    var finished = false
    var phases: [Double]
    var logFrequency = 0.0
    var hasFrequency = false
    var muteGain = 0.0
    var smoothedGain = 0.0
    var pitchLine = ControlLine()
    var amplitudeLine = ControlLine()
    var filterA = BiquadState()
    var filterB = BiquadState()

    init(event: NoteEvent, phaseCount: Int) {
        self.event = event
        self.endFrame = event.lengthFrames.map { event.frame + $0 }
        // Spread unison phases deterministically (golden ratio) to avoid a comb peak at the start.
        self.phases = (0..<max(1, phaseCount)).map { MathSemantics.frac(Double($0) * 0.618_033_988_749_894_8) }
        if phaseCount <= 1 { phases = [0] }
        pitchLine.reset(anchor: event.frame)
        amplitudeLine.reset(anchor: event.frame)
    }

    mutating func retrigger(_ newEvent: NoteEvent, resetPhase: Bool) {
        event = newEvent
        endFrame = newEvent.lengthFrames.map { newEvent.frame + $0 }
        releaseRemaining = -1
        pitchLine.reset(anchor: newEvent.frame)
        amplitudeLine.reset(anchor: newEvent.frame)
        if resetPhase {
            for index in phases.indices { phases[index] = 0 }
            filterA.reset()
            filterB.reset()
        }
    }
}

/// Renders one voice into a mono buffer (adds to it).
private final class VoiceRenderer {
    let plan: VoicePlan
    private let clock: MusicalClock
    private let xMapping: XMappingFunction
    private let voice: SynthVoice
    private let buffer: EvaluationBuffer
    private let sampleRate: Double
    private let events: [NoteEvent]
    private var nextEvent = 0
    private var instances: [NoteInstance] = []
    private let polyphony: Int
    private var noise: NoiseGenerator
    private let releaseFrames: Int
    private let muteStep: Double
    private let gainSmoothing: Double
    private let glideCoefficient: Double
    private let unisonRatios: [Double]
    private let unisonGain: Double
    // Drum constants
    private let drumFilterA: BiquadCoefficients
    private let drumFilterB: BiquadCoefficients
    private let drumDecay: Double
    // Formula signal path
    private var formula: FormulaSignalPath?

    init(plan: VoicePlan, synth: SynthPlan) {
        self.plan = plan
        self.clock = synth.clock
        self.xMapping = synth.compilation.xMapping
        self.voice = plan.voice
        self.buffer = EvaluationBuffer(capacity: plan.compiled.slotCount)
        self.sampleRate = synth.sampleRate
        self.events = plan.schedule.events
        self.noise = NoiseGenerator(seed: plan.noiseSeed)
        self.releaseFrames = max(1, Int(0.005 * synth.sampleRate))
        self.muteStep = 1 / max(1, PCMRenderer.muteRampMilliseconds / 1000 * synth.sampleRate)
        self.gainSmoothing = 1 - exp(-1 / (0.0007 * synth.sampleRate))
        let glide = voice.pitch.glideMilliseconds.clamped(to: PitchControl.glideRange, fallback: 0)
        self.glideCoefficient = glide > 0 ? 1 - exp(-1 / (glide / 1000 * synth.sampleRate)) : 1
        let unison = voice.source.kind == .oscillator || voice.source.kind == .periodicFormula
            ? min(max(voice.source.unison, VoiceSource.unisonRange.lowerBound), VoiceSource.unisonRange.upperBound) : 1
        if unison > 1 {
            let spread = voice.source.detuneCents.clamped(to: 0...100, fallback: 0)
            self.unisonRatios = (0..<unison).map { index in
                let position = Double(index) / Double(unison - 1) * 2 - 1
                return exp2(position * spread / 1200)
            }
        } else {
            self.unisonRatios = [1]
        }
        self.unisonGain = 1 / Double(unisonRatios.count).squareRoot()
        let isFormula: Bool
        if case .formula = plan.mode { isFormula = true } else { isFormula = false }
        self.polyphony = isFormula ? 1 : min(max(voice.polyphony, 1), SynthVoice.polyphonyRange.upperBound)
        let tone = voice.source.tone.clamped(to: 0...1, fallback: 0.5)
        switch voice.source.drum {
        case .snare:
            drumFilterA = .bandpass(frequency: 1_800 + 1_400 * tone, q: 0.8, sampleRate: synth.sampleRate)
            drumFilterB = .highpass(frequency: 700, q: 0.7, sampleRate: synth.sampleRate)
        case .hihat:
            drumFilterA = .highpass(frequency: 6_500 + 3_500 * tone, q: 0.8, sampleRate: synth.sampleRate)
            drumFilterB = .bandpass(frequency: 10_000, q: 0.6, sampleRate: synth.sampleRate)
        case .cowbell:
            drumFilterA = .bandpass(frequency: 2_200, q: 2.5, sampleRate: synth.sampleRate)
            drumFilterB = .highpass(frequency: 300, q: 0.7, sampleRate: synth.sampleRate)
        case .kick:
            drumFilterA = .identity
            drumFilterB = .identity
        }
        // Decay = time to −60 dB.
        self.drumDecay = max(0.005, voice.source.decayMilliseconds.clamped(to: 5...4_000, fallback: 300) / 1000) / 6.9
        if case .formula(let oversampling) = plan.mode {
            formula = FormulaSignalPath(plan: plan, synth: synth, oversampling: oversampling)
        }
    }

    // MARK: Evaluation helpers

    @inline(__always)
    private func pitchValue(frame: Int, event: NoteEvent) -> Double {
        guard let program = plan.compiled.pitch?.program else { return log2(voice.pitch.baseFrequency) }
        VoiceInputs.set(buffer, frame: frame, event: event, clock: clock, xMapping: xMapping)
        let value = buffer.evaluate(program)
        guard let frequency = PitchConversion.frequency(value: value, unit: voice.pitch.unit, baseFrequency: voice.pitch.baseFrequency,
                                                        quantization: voice.pitch.quantization, normalized: plan.normalizedRange,
                                                        maximum: plan.maximumFrequency) else { return .nan }
        return log2(frequency)
    }

    @inline(__always)
    private func gainValue(frame: Int, event: NoteEvent) -> Double {
        guard let program = plan.compiled.amplitude?.program else { return 1 }
        VoiceInputs.set(buffer, frame: frame, event: event, clock: clock, xMapping: xMapping)
        return PitchConversion.gain(value: buffer.evaluate(program), scale: voice.amplitude.scale)
    }

    // MARK: Rendering

    func render(into output: UnsafeMutablePointer<Double>, from start: Int, count: Int) {
        if let formula {
            formula.render(into: output, from: start, count: count)
            return
        }
        var frame = start
        let end = start + count
        while frame < end {
            while nextEvent < events.count, events[nextEvent].frame <= frame {
                trigger(events[nextEvent])
                nextEvent += 1
            }
            // The next event lies after `frame`, so every segment makes progress.
            let segmentEnd = nextEvent < events.count ? min(end, events[nextEvent].frame) : end
            for index in instances.indices {
                renderInstance(&instances[index], into: output - start, from: frame, to: segmentEnd)
            }
            instances.removeAll { $0.finished }
            frame = segmentEnd
        }
    }

    private func trigger(_ event: NoteEvent) {
        let phaseCount = voice.source.kind == .riser ? min(max(voice.source.riserPartials, 2), 10) : unisonRatios.count
        let resetPhase = voice.source.resetPhaseOnTrigger || voice.source.kind == .drum
        if polyphony == 1 {
            if instances.isEmpty {
                instances.append(NoteInstance(event: event, phaseCount: phaseCount))
            } else {
                instances[0].retrigger(event, resetPhase: resetPhase)
                instances.removeSubrange(1...)
            }
            return
        }
        let sounding = instances.filter { $0.releaseRemaining < 0 }
        if sounding.count >= polyphony, let oldest = instances.firstIndex(where: { $0.releaseRemaining < 0 }) {
            instances[oldest].releaseRemaining = releaseFrames
        }
        if instances.count > polyphony + 4 {
            instances.removeFirst(instances.count - polyphony - 4)
        }
        instances.append(NoteInstance(event: event, phaseCount: phaseCount))
    }

    private func renderInstance(_ instance: inout NoteInstance, into output: UnsafeMutablePointer<Double>, from: Int, to: Int) {
        let kind = voice.source.kind
        let velocity = instance.event.velocity
        for frame in from..<to {
            // Gate and release (polyphonic notes).
            if let end = instance.endFrame, frame >= end, instance.releaseRemaining < 0 {
                instance.releaseRemaining = releaseFrames
            }
            var release = 1.0
            if instance.releaseRemaining >= 0 {
                if instance.releaseRemaining == 0 {
                    instance.finished = true
                    return
                }
                release = Double(instance.releaseRemaining) / Double(releaseFrames)
                instance.releaseRemaining -= 1
            }
            let event = instance.event

            // Pitch (role A) – log2 frequency, glide, mute ramp at undefined values.
            var frequency = voice.pitch.baseFrequency
            if kind != .riser {
                let target = instance.pitchLine.value(at: frame) { self.pitchValue(frame: $0, event: event) }
                if target.isNaN {
                    instance.muteGain = max(0, instance.muteGain - muteStep)
                } else {
                    if !instance.hasFrequency || instance.muteGain <= 0 || glideCoefficient >= 1 {
                        instance.logFrequency = target
                        instance.hasFrequency = true
                    } else {
                        instance.logFrequency += (target - instance.logFrequency) * glideCoefficient
                    }
                    instance.muteGain = min(1, instance.muteGain + muteStep)
                }
                frequency = exp2(instance.logFrequency)
            } else {
                instance.muteGain = 1
            }

            // Amplitude (role B), smoothed against clicks.
            let gainTarget = instance.amplitudeLine.value(at: frame) { self.gainValue(frame: $0, event: event) }
            instance.smoothedGain += ((gainTarget.isNaN ? 0 : gainTarget) - instance.smoothedGain) * gainSmoothing
            let envelope = instance.smoothedGain * instance.muteGain * release * velocity
            guard instance.hasFrequency || kind == .riser else { continue }

            let localTime = Double(frame - event.frame) / sampleRate
            var sample = 0.0
            switch plan.mode {
            case .sine:
                for index in instance.phases.indices {
                    sample += sin(2 * Double.pi * instance.phases[index])
                    advance(&instance.phases[index], frequency * unisonRatios[index])
                }
                sample *= unisonGain
            case .table:
                guard let bank = plan.bank else { break }
                for index in instance.phases.indices {
                    let f = frequency * unisonRatios[index]
                    sample += Double(bank.value(phase: instance.phases[index], frequency: f))
                    advance(&instance.phases[index], f)
                }
                sample *= unisonGain
            case .drum(let drum):
                sample = drumSample(drum, &instance, frequency: frequency, localTime: localTime)
            case .riser:
                sample = riserSample(&instance, frame: frame)
            case .formula:
                break
            }
            output[frame] += sample * envelope
        }
    }

    @inline(__always)
    private func advance(_ phase: inout Double, _ frequency: Double) {
        phase += min(frequency, plan.maximumFrequency) / sampleRate
        if phase >= 1 { phase -= floor(phase) }
    }

    private func drumSample(_ drum: DrumKind, _ instance: inout NoteInstance, frequency: Double, localTime: Double) -> Double {
        let tone = voice.source.tone.clamped(to: 0...1, fallback: 0.5)
        switch drum {
        case .kick:
            // Pitch drops from 4× to the base frequency within ~30 ms.
            let sweep = 1 + 3 * exp(-localTime / 0.03)
            let f = frequency * sweep
            let body = sin(2 * Double.pi * instance.phases[0])
            advance(&instance.phases[0], f)
            let click = noise.next() * exp(-localTime / 0.0015) * 0.4 * tone
            return (body + click) * exp(-localTime / drumDecay)
        case .snare:
            let toneEnvelope = exp(-localTime / 0.045)
            let body = (sin(2 * Double.pi * instance.phases[0]) + 0.6 * sin(2 * Double.pi * MathSemantics.frac(instance.phases[0] * 1.6))) * 0.6
            advance(&instance.phases[0], frequency)
            var rattle = instance.filterA.process(noise.next(), drumFilterA)
            rattle = instance.filterB.process(rattle, drumFilterB) * 2.2
            return (body * toneEnvelope * (1 - tone) + rattle * tone) * exp(-localTime / drumDecay)
        case .hihat:
            var hiss = instance.filterA.process(noise.next(), drumFilterA)
            hiss = hiss * 0.7 + instance.filterB.process(hiss, drumFilterB) * 0.6
            return hiss * 1.8 * exp(-localTime / drumDecay)
        case .cowbell:
            guard let bank = plan.bank else { return 0 }
            let f1 = frequency
            let f2 = frequency * 1.4815
            if instance.phases.count < 2 { instance.phases.append(0.25) }
            let raw = Double(bank.value(phase: instance.phases[0], frequency: f1)) + Double(bank.value(phase: instance.phases[1], frequency: f2))
            advance(&instance.phases[0], f1)
            advance(&instance.phases[1], f2)
            let filtered = instance.filterB.process(instance.filterA.process(raw, drumFilterA), drumFilterB)
            let envelope = 0.65 * exp(-localTime / 0.012) + 0.35 * exp(-localTime / drumDecay)
            return filtered * 1.6 * envelope
        }
    }

    private func riserSample(_ instance: inout NoteInstance, frame: Int) -> Double {
        let partials = instance.phases.count
        let riser = ShepardRiser(partials: partials, lowestFrequency: voice.source.riserLowestFrequency,
                                 cycleSeconds: voice.source.riserCycleBeats * clock.tempo.secondsPerBeat,
                                 rising: voice.source.riserRising)
        let time = Double(frame) / sampleRate
        var sample = 0.0
        for index in 0..<partials {
            let frequency = riser.frequency(partial: index, time: time)
            let level = riser.level(partial: index, time: time)
            if frequency < plan.maximumFrequency {
                sample += level * sin(2 * Double.pi * instance.phases[index])
            }
            instance.phases[index] += frequency / sampleRate
            if instance.phases[index] >= 1 { instance.phases[index] -= floor(instance.phases[index]) }
        }
        return sample / riser.levelSum
    }
}

/// Formula signals (role C): evaluated at `oversampling` × the sample rate, low-pass filtered
/// and decimated (anti-aliasing), normalised and DC-free. The producer runs ahead by the
/// filter delay so that the output is sample-aligned with all other voices.
private final class FormulaSignalPath {
    private let plan: VoicePlan
    private let clock: MusicalClock
    private let xMapping: XMappingFunction
    private let voice: SynthVoice
    private let buffer: EvaluationBuffer
    private let sampleRate: Double
    private let oversampling: Int
    private let filter: DecimationFilter
    private let lookahead: Int
    private let events: [NoteEvent]
    private let periodic: Bool
    private let sectionStart: Double
    private let sectionWidth: Double
    // Producer
    private var producerFrame = 0
    private var producerEvent = -1
    private var phase = 0.0
    private var logFrequency = 0.0
    private var hasFrequency = false
    private var pitchLine = ControlLine()
    private let glideCoefficient: Double
    private var ring: [Double]
    private let ringSize: Int
    private var written = 0   // oversampled samples written
    // Consumer
    private var consumerEvent = -1
    private var amplitudeLine = ControlLine()
    private var smoothedGain = 0.0
    private let gainSmoothing: Double
    private var dcBlocker: DCBlocker
    private var primed = false

    init(plan: VoicePlan, synth: SynthPlan, oversampling: Int) {
        self.plan = plan
        self.clock = synth.clock
        self.xMapping = synth.compilation.xMapping
        self.voice = plan.voice
        self.buffer = EvaluationBuffer(capacity: plan.compiled.slotCount)
        self.sampleRate = synth.sampleRate
        self.oversampling = oversampling
        self.filter = DecimationFilter(factor: oversampling)
        self.lookahead = (filter.halfLength + oversampling - 1) / oversampling
        self.events = plan.schedule.events
        self.periodic = voice.source.kind == .periodicFormula
        self.sectionStart = voice.source.sectionStart
        self.sectionWidth = voice.source.sectionEnd - voice.source.sectionStart
        let glide = voice.pitch.glideMilliseconds.clamped(to: PitchControl.glideRange, fallback: 0)
        self.glideCoefficient = glide > 0 ? 1 - exp(-1 / (glide / 1000 * synth.sampleRate)) : 1
        self.ringSize = filter.taps.count + 2 * oversampling
        self.ring = [Double](repeating: 0, count: 2 * ringSize)
        self.gainSmoothing = 1 - exp(-1 / (0.0007 * synth.sampleRate))
        self.dcBlocker = DCBlocker(sampleRate: synth.sampleRate)
    }

    private func event(_ index: Int) -> NoteEvent? {
        index >= 0 && index < events.count ? events[index] : nil
    }

    /// Produces the oversampled samples of one frame.
    private func produce() {
        let frame = producerFrame
        var eventChanged = false
        while producerEvent + 1 < events.count, events[producerEvent + 1].frame <= frame {
            producerEvent += 1
            eventChanged = true
        }
        let event = self.event(producerEvent)
        if eventChanged, let event {
            pitchLine.reset(anchor: event.frame)
            if voice.source.resetPhaseOnTrigger { phase = 0 }
        }
        var increment = 0.0
        var silent = false
        if periodic {
            let target = pitchLine.value(at: frame) { evaluationFrame in
                guard let program = plan.compiled.pitch?.program else { return log2(voice.pitch.baseFrequency) }
                VoiceInputs.set(buffer, frame: evaluationFrame, event: event, clock: clock, xMapping: xMapping)
                guard let frequency = PitchConversion.frequency(value: buffer.evaluate(program), unit: voice.pitch.unit,
                                                                baseFrequency: voice.pitch.baseFrequency, quantization: voice.pitch.quantization,
                                                                normalized: plan.normalizedRange, maximum: plan.maximumFrequency) else { return .nan }
                return log2(frequency)
            }
            if target.isNaN {
                silent = true
            } else {
                if !hasFrequency || glideCoefficient >= 1 {
                    logFrequency = target
                    hasFrequency = true
                } else {
                    logFrequency += (target - logFrequency) * glideCoefficient
                }
                increment = exp2(logFrequency) / sampleRate
            }
        }
        guard let program = plan.compiled.signal?.program else { return }
        for sub in 0..<oversampling {
            var value = 0.0
            if !silent {
                let fraction = Double(sub) / Double(oversampling)
                VoiceInputs.set(buffer, frame: Double(frame) + fraction, eventFrame: event.map { Double($0.frame) },
                                event: event, clock: clock, xMapping: xMapping)
                if periodic {
                    buffer[.x] = sectionStart + sectionWidth * MathSemantics.frac(phase + increment * fraction)
                }
                value = buffer.evaluate(program)
                if !value.isFinite { value = plan.signalOffset }
            }
            let slot = written % ringSize
            ring[slot] = value
            ring[slot + ringSize] = value
            written += 1
        }
        if periodic {
            phase += increment
            if phase >= 1 { phase -= floor(phase) }
        }
        producerFrame += 1
    }

    func render(into output: UnsafeMutablePointer<Double>, from start: Int, count: Int) {
        if !primed {
            for _ in 0..<lookahead { produce() }
            primed = true
        }
        let taps = filter.taps
        let half = filter.halfLength
        for offset in 0..<count {
            let frame = start + offset
            produce()
            // FIR centred at oversampled index frame·OS (indices before 0 count as 0).
            let center = frame * oversampling
            var filtered = 0.0
            let first = center - half
            if first >= 0 && written - first <= ringSize {
                let base = first % ringSize
                ring.withUnsafeBufferPointer { values in
                    taps.withUnsafeBufferPointer { coefficients in
                        for k in 0..<coefficients.count {
                            filtered += coefficients[k] * values[base + k]
                        }
                    }
                }
            } else {
                for k in 0..<taps.count {
                    let index = first + k
                    guard index >= 0, index < written, written - index <= ringSize else { continue }
                    filtered += taps[k] * ring[index % ringSize]
                }
            }
            var sample = (filtered - plan.signalOffset) * plan.signalScale
            sample = dcBlocker.process(sample)

            // Amplitude at the output frame (consumer-side event).
            var changed = false
            while consumerEvent + 1 < events.count, events[consumerEvent + 1].frame <= frame {
                consumerEvent += 1
                changed = true
            }
            let event = self.event(consumerEvent)
            if changed, let event { amplitudeLine.reset(anchor: event.frame) }
            let target = amplitudeLine.value(at: frame) { evaluationFrame in
                guard let program = plan.compiled.amplitude?.program else { return 1 }
                VoiceInputs.set(buffer, frame: evaluationFrame, event: event, clock: clock, xMapping: xMapping)
                return PitchConversion.gain(value: buffer.evaluate(program), scale: voice.amplitude.scale)
            }
            smoothedGain += ((target.isNaN ? 0 : target) - smoothedGain) * gainSmoothing
            output[offset] += sample * smoothedGain * (event?.velocity ?? 1)
        }
    }
}
