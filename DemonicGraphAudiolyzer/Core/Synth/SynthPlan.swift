import Foundation

/// Immutable snapshot of a synthesizer project for preview and export (same type for both).
struct SynthRenderConfiguration: Equatable, Sendable {
    var project: SynthProject
    var sampleRate: Double

    init(project: SynthProject, sampleRate: Double = 44_100) {
        self.project = project
        self.sampleRate = sampleRate
    }

    var frameCount: Int { MusicalClock(tempo: project.tempo, sampleRate: sampleRate).totalFrames }

    func withSampleRate(_ rate: Double) -> SynthRenderConfiguration {
        var copy = self
        copy.sampleRate = rate
        return copy
    }
}

enum SynthPlanError: Error, Equatable, Sendable {
    case invalid(String)

    var message: String {
        switch self {
        case .invalid(let text): return text
        }
    }
}

/// How a voice produces its raw signal.
enum VoiceSignalMode: Equatable, Sendable {
    /// Band-limited table oscillator (also formula waves that do not depend on time).
    case table
    case sine
    /// Formula evaluated per (oversampled) sample, low-pass filtered and decimated.
    case formula(oversampling: Int)
    case drum(DrumKind)
    case riser
}

/// Everything a voice needs for rendering, prepared off the main thread.
struct VoicePlan: Sendable {
    let compiled: CompiledVoice
    let schedule: VoiceSchedule
    let mode: VoiceSignalMode
    let bank: BandLimitedWavetableBank?
    /// Left/right gain including the voice volume (constant-power pan, centre compensated).
    let gainLeft: Double
    let gainRight: Double
    let normalizedRange: PitchConversion.NormalizedRange?
    /// Formula signals: mean and scale of the automatic normalisation.
    let signalOffset: Double
    let signalScale: Double
    let noiseSeed: UInt64
    let maximumFrequency: Double

    var voice: SynthVoice { compiled.voice }
}

/// Prepared render plan of a synthesizer project.
struct SynthPlan: Sendable {
    let configuration: SynthRenderConfiguration
    let compilation: SynthCompilation
    let voices: [VoicePlan]
    /// Linear master gain (project level and headroom 1/√N for N audible voices).
    let masterGain: Double

    var sampleRate: Double { configuration.sampleRate }
    var frameCount: Int { compilation.clock.totalFrames }
    var clock: MusicalClock { compilation.clock }

    /// Soft limiter threshold (−1 dBFS); the output approaches but never exceeds 0 dBFS.
    static let limiterThreshold = 0.891_250_938_133_745_5

    init(configuration: SynthRenderConfiguration, compilation: SynthCompilation? = nil) throws {
        self.configuration = configuration
        let compilation = compilation ?? SynthCompilation(project: configuration.project, sampleRate: configuration.sampleRate)
        self.compilation = compilation
        if let issue = compilation.blockingIssue {
            throw SynthPlanError.invalid(issue)
        }
        let project = compilation.project
        let audible = Set(project.audibleVoices.map(\.id))
        var plans: [VoicePlan] = []
        for compiled in compilation.voices where audible.contains(compiled.voice.id) && compiled.isValid {
            plans.append(Self.makeVoicePlan(compiled, compilation: compilation))
        }
        self.voices = plans
        let level = pow(10, project.masterLevelDecibels.clamped(to: SynthProject.masterLevelRange, fallback: -3) / 20)
        self.masterGain = level / Double(max(1, plans.count)).squareRoot()
    }

    private static func makeVoicePlan(_ compiled: CompiledVoice, compilation: SynthCompilation) -> VoicePlan {
        let voice = compiled.voice
        let sampleRate = compilation.sampleRate
        let schedule = compilation.schedules[voice.id] ?? VoiceSchedule(events: [])
        let volume = pow(10, voice.volumeDecibels.clamped(to: SynthVoice.volumeRange, fallback: -6) / 20)
        let pan = voice.pan.clamped(to: -1...1, fallback: 0)
        let angle = (pan + 1) * Double.pi / 4
        let left = min(1, 2.0.squareRoot() * cos(angle)) * volume
        let right = min(1, 2.0.squareRoot() * sin(angle)) * volume
        let seed = compilation.project.noiseSeed ^ NoiseGenerator.stableHash(voice.id.uuidString)

        var mode: VoiceSignalMode
        var bank: BandLimitedWavetableBank?
        var offset = 0.0
        var scale = 1.0
        switch voice.source.kind {
        case .oscillator:
            if voice.source.waveform == .sine {
                mode = .sine
            } else {
                mode = .table
                bank = OscillatorBankCache.shared.bank(for: voice.source.waveform, sampleRate: sampleRate)
            }
        case .periodicFormula:
            if let signal = compiled.signal, signal.program.inputs.isSubset(of: [.x]) {
                mode = .table
                bank = staticFormulaBank(signal.program, voice: voice, sampleRate: sampleRate)
            } else {
                mode = .formula(oversampling: normalizedOversampling(voice.source.oversampling))
                (offset, scale) = normalization(compiled, schedule: schedule, compilation: compilation)
            }
        case .directSignal:
            mode = .formula(oversampling: normalizedOversampling(voice.source.oversampling))
            (offset, scale) = normalization(compiled, schedule: schedule, compilation: compilation)
        case .drum:
            mode = .drum(voice.source.drum)
            if voice.source.drum == .cowbell {
                bank = OscillatorBankCache.shared.bank(for: .square, sampleRate: sampleRate)
            }
        case .riser:
            mode = .riser
        }

        var normalizedRange: PitchConversion.NormalizedRange?
        if voice.pitch.unit == .normalized {
            normalizedRange = Self.normalizedRange(compiled, schedule: schedule, compilation: compilation)
        }
        return VoicePlan(compiled: compiled, schedule: schedule, mode: mode, bank: bank,
                         gainLeft: left, gainRight: right, normalizedRange: normalizedRange,
                         signalOffset: offset, signalScale: scale, noiseSeed: seed,
                         maximumFrequency: 0.45 * sampleRate)
    }

    static func normalizedOversampling(_ value: Int) -> Int {
        VoiceSource.oversamplingOptions.contains(value) ? value : 4
    }

    /// Wavetable bank of a time-independent formula wave: one period over the section,
    /// DC removed, outliers limited softly, then band-limited per octave band.
    static func staticFormulaBank(_ program: CompiledProgram, voice: SynthVoice, sampleRate: Double) -> BandLimitedWavetableBank {
        let size = SoundPlan.tableSize
        let buffer = EvaluationBuffer(capacity: program.slotCount)
        let start = voice.source.sectionStart
        let width = voice.source.sectionEnd - voice.source.sectionStart
        var period = [Double](repeating: 0, count: size)
        for index in 0..<size {
            buffer[.x] = start + width * Double(index) / Double(size)
            let value = buffer.evaluate(program)
            period[index] = value.isFinite ? value : 0
        }
        let mean = period.reduce(0, +) / Double(size)
        var centered = period.map { $0 - mean }
        let magnitudes = centered.map { abs($0) }.sorted()
        let peak = magnitudes.last ?? 0
        let robust = RobustRange.quantile(magnitudes, 0.995)
        if robust > 0, peak > 4 * robust {
            let limit = 2 * robust
            centered = centered.map { limit * tanh($0 / limit) }
        }
        return BandLimitedWavetableBank.fromPeriod(centered, sampleRate: sampleRate)
    }

    /// Automatic normalisation of formula signals: mean and the 99.9 % quantile of the
    /// deviation, estimated from up to 65 536 deterministic sample points over the pass.
    static func normalization(_ compiled: CompiledVoice, schedule: VoiceSchedule, compilation: SynthCompilation) -> (offset: Double, scale: Double) {
        guard compiled.voice.source.normalization == .automatic, let signal = compiled.signal else { return (0, 1) }
        let clock = compilation.clock
        let buffer = EvaluationBuffer(capacity: compiled.slotCount)
        let count = min(65_536, max(256, clock.totalFrames))
        let periodic = compiled.voice.source.kind == .periodicFormula
        let start = compiled.voice.source.sectionStart
        let width = compiled.voice.source.sectionEnd - start
        var values: [Double] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            let frame = Int(Double(index) / Double(count) * Double(clock.totalFrames))
            let event = schedule.activeEventIndex(atFrame: frame).map { schedule.events[$0] }
            VoiceInputs.set(buffer, frame: frame, event: event, clock: clock, xMapping: compilation.xMapping)
            if periodic {
                // Golden-ratio sequence: evenly distributed positions inside the period.
                buffer[.x] = start + width * MathSemantics.frac(Double(index) * 0.618_033_988_749_894_8)
            }
            let value = buffer.evaluate(signal.program)
            if value.isFinite { values.append(value) }
        }
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviations = values.map { abs($0 - mean) }.sorted()
        let quantile = RobustRange.quantile(deviations, 0.999)
        guard quantile > 1e-9 else { return (mean, 0) }
        return (mean, 1 / quantile)
    }

    /// Automatic y range of the normalized pitch unit (like the former "Graph vertonen").
    static func normalizedRange(_ compiled: CompiledVoice, schedule: VoiceSchedule, compilation: SynthCompilation) -> PitchConversion.NormalizedRange {
        let pitch = compiled.voice.pitch
        let frequencyLow = pitch.frequencyLow.clamped(to: SoundSettings.frequencyRange, fallback: 110)
        let frequencyHigh = max(pitch.frequencyHigh.clamped(to: SoundSettings.frequencyRange, fallback: 880), frequencyLow * 1.0001)
        guard pitch.automaticRange, let program = compiled.pitch?.program else {
            return PitchConversion.NormalizedRange(yLow: pitch.yLow, yHigh: max(pitch.yHigh, pitch.yLow + 1e-9),
                                                   frequencyLow: frequencyLow, frequencyHigh: frequencyHigh)
        }
        let clock = compilation.clock
        let buffer = EvaluationBuffer(capacity: compiled.slotCount)
        var values: [Double] = []
        let count = 4_096
        for index in 0...count {
            let frame = Int(Double(index) / Double(count) * Double(clock.totalFrames - 1))
            let event = schedule.activeEventIndex(atFrame: frame).map { schedule.events[$0] }
            VoiceInputs.set(buffer, frame: frame, event: event, clock: clock, xMapping: compilation.xMapping)
            let value = buffer.evaluate(program)
            if value.isFinite { values.append(value) }
        }
        var low = -1.0
        var high = 1.0
        if let range = RobustRange.estimate(values) {
            if range.upperBound - range.lowerBound > 1e-12 {
                low = range.lowerBound
                high = range.upperBound
            } else {
                low = range.lowerBound - 1
                high = range.upperBound + 1
            }
        }
        return PitchConversion.NormalizedRange(yLow: low, yHigh: high, frequencyLow: frequencyLow, frequencyHigh: frequencyHigh)
    }
}

/// Band-limited oscillator tables per waveform and sample rate (built once, shared).
final class OscillatorBankCache: @unchecked Sendable {
    static let shared = OscillatorBankCache()

    private let lock = NSLock()
    private var banks: [String: BandLimitedWavetableBank] = [:]

    func bank(for waveform: OscillatorWaveform, sampleRate: Double) -> BandLimitedWavetableBank? {
        let key = "\(waveform.rawValue)-\(Int(sampleRate))"
        lock.lock()
        if let cached = banks[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bank: BandLimitedWavetableBank?
        switch waveform {
        case .sine: bank = nil
        case .triangle: bank = BandLimitedWavetableBank.triangle(sampleRate: sampleRate)
        case .sawtooth: bank = BandLimitedWavetableBank.sawtooth(sampleRate: sampleRate)
        case .square: bank = BandLimitedWavetableBank.square(sampleRate: sampleRate)
        case .rich: bank = BandLimitedWavetableBank.rich(sampleRate: sampleRate)
        }
        if let bank {
            lock.lock()
            banks[key] = bank
            lock.unlock()
        }
        return bank
    }
}
