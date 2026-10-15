import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value or falls back to a default (older saved projects stay readable).
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// Tempo and length of a synthesizer project.
struct TempoSettings: Codable, Equatable, Hashable, Sendable {
    var bpm: Double = 120
    var beatsPerBar: Int = 4
    var bars: Int = 4

    static let bpmRange: ClosedRange<Double> = 30...300
    static let beatsPerBarRange: ClosedRange<Int> = 1...12
    static let barsRange: ClosedRange<Int> = 1...64
    /// Longest pass that is rendered (resource limit).
    static let maximumDuration: Double = 120

    init(bpm: Double = 120, beatsPerBar: Int = 4, bars: Int = 4) {
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.bars = bars
    }

    var totalBeats: Double { Double(bars * beatsPerBar) }
    var secondsPerBeat: Double { 60 / bpm }
    var duration: Double { totalBeats * secondsPerBeat }

    func clamped() -> TempoSettings {
        var copy = self
        copy.bpm = bpm.clamped(to: Self.bpmRange, fallback: 120)
        copy.beatsPerBar = min(max(beatsPerBar, Self.beatsPerBarRange.lowerBound), Self.beatsPerBarRange.upperBound)
        copy.bars = min(max(bars, Self.barsRange.lowerBound), Self.barsRange.upperBound)
        return copy
    }

    var validationIssue: String? {
        if duration > Self.maximumDuration + 1e-9 {
            return "Der Durchlauf ist zu lang (\(NumberText.seconds(duration))). Höchstens \(Int(Self.maximumDuration)) s – weniger Takte oder schnelleres Tempo wählen."
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TempoSettings()
        bpm = container.value(.bpm, defaults.bpm)
        beatsPerBar = container.value(.beatsPerBar, defaults.beatsPerBar)
        bars = container.value(.bars, defaults.bars)
    }
}

/// Meaning of x in a synthesizer project (chosen per project).
enum XMapping: String, Codable, CaseIterable, Identifiable, Sendable {
    /// x = t (seconds)
    case seconds
    /// x = beat
    case beats
    /// The previous free x run: x goes from xMin to xMax during the pass.
    case freeRange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seconds: return "Sekunden (x = t)"
        case .beats: return "Beats (x = beat)"
        case .freeRange: return "Freier x-Durchlauf"
        }
    }

    var shortTitle: String {
        switch self {
        case .seconds: return "Sekunden"
        case .beats: return "Beats"
        case .freeRange: return "Frei"
        }
    }
}

// MARK: - Pitch

enum PitchUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case hertz
    case semitones
    case octaves
    /// The former graph-to-pitch mapping: [yLow, yHigh] → [fLow, fHigh].
    case normalized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hertz: return "Hz"
        case .semitones: return "Halbtöne"
        case .octaves: return "Oktaven"
        case .normalized: return "Graph → Ton"
        }
    }

    /// Visible meaning of the formula output.
    var meaning: String {
        switch self {
        case .hertz: return "Frequenz in Hz"
        case .semitones: return "Halbtonabstand zur Grundfrequenz: f = Grundfrequenz · 2^(s/12)"
        case .octaves: return "Oktavabstand zur Grundfrequenz: f = Grundfrequenz · 2^o"
        case .normalized: return "Graphwert, abgebildet von [yLow, yHigh] auf [fLow, fHigh] (bisheriger Modus „Graph vertonen“)"
        }
    }

    var axisLabel: String {
        switch self {
        case .hertz: return "Hz"
        case .semitones: return "Halbtöne"
        case .octaves: return "Oktaven"
        case .normalized: return "y"
        }
    }
}

/// Musical scale quantization (different from numeric rounding with floor/round).
enum ScaleQuantization: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case chromatic
    case major
    case naturalMinor
    case pentatonic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Aus"
        case .chromatic: return "Chromatisch"
        case .major: return "Dur"
        case .naturalMinor: return "Natürlich Moll"
        case .pentatonic: return "Pentatonik"
        }
    }

    /// Semitone steps within an octave above the root.
    var steps: [Double] {
        switch self {
        case .none, .chromatic: return (0..<12).map(Double.init)
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .pentatonic: return [0, 2, 4, 7, 9]
        }
    }
}

/// Role A: pitch.
struct PitchControl: Codable, Equatable, Hashable, Sendable {
    var formula: String = "0"
    var unit: PitchUnit = .semitones
    /// Reference for semitones and octaves (Hz).
    var baseFrequency: Double = 110
    var quantization: ScaleQuantization = .none
    /// One-pole glide on log2(frequency); also the exponential slide between notes.
    var glideMilliseconds: Double = 0
    // Normalized mapping (former "Graph vertonen")
    var automaticRange = true
    var yLow: Double = -1
    var yHigh: Double = 1
    var frequencyLow: Double = 110
    var frequencyHigh: Double = 880

    static let baseFrequencyRange: ClosedRange<Double> = 8...4000
    static let glideRange: ClosedRange<Double> = 0...2000

    init() {}

    init(formula: String, unit: PitchUnit, baseFrequency: Double = 110, quantization: ScaleQuantization = .none, glideMilliseconds: Double = 0) {
        self.formula = formula
        self.unit = unit
        self.baseFrequency = baseFrequency
        self.quantization = quantization
        self.glideMilliseconds = glideMilliseconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PitchControl()
        formula = c.value(.formula, d.formula)
        unit = c.value(.unit, d.unit)
        baseFrequency = c.value(.baseFrequency, d.baseFrequency)
        quantization = c.value(.quantization, d.quantization)
        glideMilliseconds = c.value(.glideMilliseconds, d.glideMilliseconds)
        automaticRange = c.value(.automaticRange, d.automaticRange)
        yLow = c.value(.yLow, d.yLow)
        yHigh = c.value(.yHigh, d.yHigh)
        frequencyLow = c.value(.frequencyLow, d.frequencyLow)
        frequencyHigh = c.value(.frequencyHigh, d.frequencyHigh)
    }
}

enum AmplitudeScale: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Non-negative linear gain (0 = silent, 1 = full level of the voice).
    case linear
    /// Level in dB relative to the full level: gain = 10^(A/20); ≤ −120 dB is silent.
    case decibels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: return "Linear"
        case .decibels: return "dB"
        }
    }

    var meaning: String {
        switch self {
        case .linear: return "Verstärkung, linear und nicht negativ (0 = stumm, 1 = voller Pegel der Stimme; negative Werte zählen als 0)"
        case .decibels: return "Pegel in dB: Verstärkung = 10^(A/20); 0 dB = 1, −6 dB ≈ 0,5, ≤ −120 dB = stumm"
        }
    }
}

/// Role B: amplitude / envelope.
struct AmplitudeControl: Codable, Equatable, Hashable, Sendable {
    var formula: String = "1"
    var scale: AmplitudeScale = .linear

    init(formula: String = "1", scale: AmplitudeScale = .linear) {
        self.formula = formula
        self.scale = scale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formula = c.value(.formula, "1")
        scale = c.value(.scale, .linear)
    }
}

// MARK: - Source (role C and synthesized instruments)

enum OscillatorWaveform: String, Codable, CaseIterable, Identifiable, Sendable {
    case sine, triangle, sawtooth, square, rich

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sine: return "Sinus"
        case .triangle: return "Dreieck"
        case .sawtooth: return "Sägezahn"
        case .square: return "Rechteck"
        case .rich: return "Obertonreich"
        }
    }
}

enum DrumKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case kick, snare, hihat, cowbell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hihat: return "Hi-Hat"
        case .cowbell: return "Cowbell"
        }
    }

    var explanation: String {
        switch self {
        case .kick: return "Sinus mit schnellem Tonhöhenabfall (vom Vierfachen auf die Grundfrequenz) und abklingender Hüllkurve."
        case .snare: return "Kurzer Ton aus zwei Sinusschwingungen plus bandgefiltertes Rauschen mit eigener Hüllkurve."
        case .hihat: return "Hochpassgefiltertes Rauschen mit sehr kurzer Hüllkurve."
        case .cowbell: return "Zwei bandbegrenzte Rechteckschwingungen im Verhältnis 1 : 1,48 durch einen Bandpass, kurze zweistufige Hüllkurve."
        }
    }
}

enum SignalNormalization: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Peak of the (DC-free) signal is estimated before playback and scaled to 1.
    case automatic
    /// Formula values are used directly (the safety limiter still protects the output).
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatisch"
        case .none: return "Aus"
        }
    }
}

struct VoiceSource: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Band-limited oscillator driven by the pitch formula.
        case oscillator
        /// Role C, periodic: the formula is one period (x runs through the section), pitch from role A.
        case periodicFormula
        /// Role C, direct: the formula yields the samples itself.
        case directSignal
        /// Synthesized percussion.
        case drum
        /// Shepard/Risset riser: octave-spaced partials with smooth level windows.
        case riser

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oscillator: return "Oszillator"
            case .periodicFormula: return "Wellenformel"
            case .directSignal: return "Direktes Signal"
            case .drum: return "Schlaginstrument"
            case .riser: return "Endless Riser"
            }
        }

        var usesPitch: Bool { self != .directSignal }
        var usesSignalFormula: Bool { self == .periodicFormula || self == .directSignal }
    }

    var kind: Kind = .oscillator
    // Oscillator
    var waveform: OscillatorWaveform = .sine
    /// Number of detuned oscillators (1 … 7).
    var unison: Int = 1
    /// Spread of the unison oscillators in cents (± around the pitch).
    var detuneCents: Double = 0
    /// Restart the oscillator phase at every trigger (drums) or keep it continuous.
    var resetPhaseOnTrigger = false
    // Formula signal
    var signalFormula: String = "sin(2*pi*x)"
    var sectionStart: Double = 0
    var sectionEnd: Double = 1
    /// 1, 2, 4 or 8.
    var oversampling: Int = 4
    var normalization: SignalNormalization = .automatic
    // Drum
    var drum: DrumKind = .kick
    var decayMilliseconds: Double = 300
    /// Tone/noise balance (snare), brightness (hi-hat), click (kick): 0 … 1.
    var tone: Double = 0.5
    // Riser
    var riserPartials: Int = 7
    var riserCycleBeats: Double = 8
    var riserLowestFrequency: Double = 30
    var riserRising = true

    static let unisonRange: ClosedRange<Int> = 1...7
    static let oversamplingOptions = [1, 2, 4, 8]
    static let riserPartialsRange: ClosedRange<Int> = 3...10

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceSource()
        kind = c.value(.kind, d.kind)
        waveform = c.value(.waveform, d.waveform)
        unison = c.value(.unison, d.unison)
        detuneCents = c.value(.detuneCents, d.detuneCents)
        resetPhaseOnTrigger = c.value(.resetPhaseOnTrigger, d.resetPhaseOnTrigger)
        signalFormula = c.value(.signalFormula, d.signalFormula)
        sectionStart = c.value(.sectionStart, d.sectionStart)
        sectionEnd = c.value(.sectionEnd, d.sectionEnd)
        oversampling = c.value(.oversampling, d.oversampling)
        normalization = c.value(.normalization, d.normalization)
        drum = c.value(.drum, d.drum)
        decayMilliseconds = c.value(.decayMilliseconds, d.decayMilliseconds)
        tone = c.value(.tone, d.tone)
        riserPartials = c.value(.riserPartials, d.riserPartials)
        riserCycleBeats = c.value(.riserCycleBeats, d.riserCycleBeats)
        riserLowestFrequency = c.value(.riserLowestFrequency, d.riserLowestFrequency)
        riserRising = c.value(.riserRising, d.riserRising)
    }
}

// MARK: - Trigger

struct SequencerSettings: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case fibonacci
        case pascal
        case circleOfFifths
        case diatonicFifths
        case tritone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fibonacci: return "Fibonacci modulo m"
            case .pascal: return "Pascal modulo 2"
            case .circleOfFifths: return "Quintenzirkel (chromatisch)"
            case .diatonicFifths: return "Diatonische Quintfolge"
            case .tritone: return "Tritonus"
            }
        }

        var formula: String {
            switch self {
            case .fibonacci: return "F(n) = (F(n−1) + F(n−2)) mod m, direkt modulo m berechnet"
            case .pascal: return "Note k erklingt in Zeile r, wenn C(r, k) ungerade ist (k & r = k)"
            case .circleOfFifths: return "Tonklasse = mod(7·n, 12) Halbtöne"
            case .diatonicFifths: return "Stufe = mod(4·n, 7) in der Durtonleiter"
            case .tritone: return "Wechsel zwischen f0 und f0·√2 (6 Halbtöne)"
            }
        }
    }

    var kind: Kind = .fibonacci
    var stepBeats: Double = 0.5
    /// Fibonacci modulus m (2 … 24).
    var modulus: Int = 4
    /// Note list in semitones (Fibonacci residues and Pascal positions index into it).
    var notes: [Double] = [0, 3, 7, 10]
    /// Rhythm pattern of active steps (independent length from the note list).
    var rhythm: String = "x"
    /// Pascal rows (1 … 32).
    var rows: Int = 16
    /// Pascal: maximum simultaneous notes (1 … 8).
    var maximumVoices: Int = 4

    static let modulusRange: ClosedRange<Int> = 2...24
    static let rowsRange: ClosedRange<Int> = 1...32
    static let voicesRange: ClosedRange<Int> = 1...8

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SequencerSettings()
        kind = c.value(.kind, d.kind)
        stepBeats = c.value(.stepBeats, d.stepBeats)
        modulus = c.value(.modulus, d.modulus)
        notes = c.value(.notes, d.notes)
        rhythm = c.value(.rhythm, d.rhythm)
        rows = c.value(.rows, d.rows)
        maximumVoices = c.value(.maximumVoices, d.maximumVoices)
    }
}

struct VoiceTrigger: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// One event at the start: localTime = t.
        case continuous
        /// Rhythm pattern ("x..x" with step length in beats).
        case pattern
        /// Accelerating repetition: phase = ∫ rate d(beat), events at integer crossings.
        case rate
        /// Pendulum midline crossings (analytic).
        case pendulum
        /// Mathematical sequencer (Fibonacci, Pascal, circle of fifths, tritone).
        case sequencer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .continuous: return "Dauerton"
            case .pattern: return "Rhythmusmuster"
            case .rate: return "Beschleunigung"
            case .pendulum: return "Pendel"
            case .sequencer: return "Sequencer"
            }
        }
    }

    var kind: Kind = .continuous
    // Pattern
    var pattern: String = "x"
    var stepBeats: Double = 1
    var offsetBeats: Double = 0
    // Rate
    var rateFormula: String = "2^(beat/beatsPerBar)"
    var maximumEventsPerSecond: Double = 24
    // Pendulum
    var pendulumCycles: Int = 6
    var pendulumPeriodBeats: Double = 16
    var pendulumBothDirections = true
    // Sequencer
    var sequencer = SequencerSettings()
    /// Note length for polyphonic voices (beats).
    var noteLengthBeats: Double = 1

    static let maximumRate: Double = 64
    static let stepRange: ClosedRange<Double> = 1.0 / 64...16

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceTrigger()
        kind = c.value(.kind, d.kind)
        pattern = c.value(.pattern, d.pattern)
        stepBeats = c.value(.stepBeats, d.stepBeats)
        offsetBeats = c.value(.offsetBeats, d.offsetBeats)
        rateFormula = c.value(.rateFormula, d.rateFormula)
        maximumEventsPerSecond = c.value(.maximumEventsPerSecond, d.maximumEventsPerSecond)
        pendulumCycles = c.value(.pendulumCycles, d.pendulumCycles)
        pendulumPeriodBeats = c.value(.pendulumPeriodBeats, d.pendulumPeriodBeats)
        pendulumBothDirections = c.value(.pendulumBothDirections, d.pendulumBothDirections)
        sequencer = c.value(.sequencer, d.sequencer)
        noteLengthBeats = c.value(.noteLengthBeats, d.noteLengthBeats)
    }
}

// MARK: - Parameters

/// A named parameter: constant (slider) or switched per beat / per bar from a list.
struct SynthParameter: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case constant
        case perBeat
        case perBar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .constant: return "Konstant"
            case .perBeat: return "Liste pro Beat"
            case .perBar: return "Liste pro Takt"
            }
        }
    }

    var id = UUID()
    var name: String
    var mode: Mode = .constant
    var value: Double = 1
    var values: [Double] = [1]
    var minimum: Double = 0
    var maximum: Double = 10

    init(name: String, value: Double, minimum: Double = 0, maximum: Double = 10) {
        self.name = name
        self.value = value
        self.values = [value]
        self.minimum = min(minimum, value)
        self.maximum = max(maximum, value)
    }

    init(name: String, mode: Mode, values: [Double], minimum: Double = 0, maximum: Double = 10) {
        self.name = name
        self.mode = mode
        self.values = values.isEmpty ? [1] : values
        self.value = self.values[0]
        self.minimum = min(minimum, self.values.min() ?? minimum)
        self.maximum = max(maximum, self.values.max() ?? maximum)
    }

    /// The definition line inserted before the formulas of the voice.
    var definitionLine: String {
        switch mode {
        case .constant:
            return "\(name) = \(FormulaNumber.literal(value))"
        case .perBeat, .perBar:
            let list = (values.isEmpty ? [value] : values).map(FormulaNumber.literal).joined(separator: ", ")
            let counter = mode == .perBar ? "bar" : "floor(beat)"
            return "\(name) = [\(list)][mod(\(counter), \((values.isEmpty ? 1 : values.count)))]"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "p")
        mode = c.value(.mode, .constant)
        value = c.value(.value, 1)
        values = c.value(.values, [value])
        minimum = c.value(.minimum, 0)
        maximum = c.value(.maximum, 10)
    }
}

/// Number literals for generated formula text (never in exponent notation).
enum FormulaNumber {
    static func literal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.10f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        if text == "-0" || text.isEmpty { return "0" }
        return text
    }
}

// MARK: - Voice

enum VoiceColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case green, blurple, magenta, cyan, amber, crimson, lime, violet

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .green: return 0x1DB954
        case .blurple: return 0x7C86FF
        case .magenta: return 0xFF4FD8
        case .cyan: return 0x34D8FF
        case .amber: return 0xFFB23F
        case .crimson: return 0xFF5470
        case .lime: return 0xB8FF3C
        case .violet: return 0xB57CFF
        }
    }

    var title: String {
        switch self {
        case .green: return "Grün"
        case .blurple: return "Blauviolett"
        case .magenta: return "Magenta"
        case .cyan: return "Cyan"
        case .amber: return "Bernstein"
        case .crimson: return "Karmesin"
        case .lime: return "Limette"
        case .violet: return "Violett"
        }
    }
}

struct SynthVoice: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String = "Stimme"
    var color: VoiceColor = .green
    var isVisible = true
    var isMuted = false
    var isSolo = false
    /// Voice level in dB (−48 … +6).
    var volumeDecibels: Double = -6
    /// −1 (left) … 1 (right), constant-power law.
    var pan: Double = 0
    var trigger = VoiceTrigger()
    var source = VoiceSource()
    var pitch = PitchControl()
    var amplitude = AmplitudeControl()
    /// Own definitions (lists, intermediate values, helper functions), multi-line.
    var definitions: String = ""
    var parameters: [SynthParameter] = []
    /// Simultaneous notes (1 = monophonic retrigger).
    var polyphony: Int = 1
    var useAdvancedEditor = false
    /// Short explanation shown in the voice card.
    var summary: String = ""

    static let volumeRange: ClosedRange<Double> = -48...6
    static let polyphonyRange: ClosedRange<Int> = 1...8

    init() {}

    init(name: String, color: VoiceColor) {
        self.name = name
        self.color = color
    }

    var linearVolume: Double { pow(10, volumeDecibels / 20) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SynthVoice()
        id = c.value(.id, UUID())
        name = c.value(.name, d.name)
        color = c.value(.color, d.color)
        isVisible = c.value(.isVisible, d.isVisible)
        isMuted = c.value(.isMuted, d.isMuted)
        isSolo = c.value(.isSolo, d.isSolo)
        volumeDecibels = c.value(.volumeDecibels, d.volumeDecibels)
        pan = c.value(.pan, d.pan)
        trigger = c.value(.trigger, d.trigger)
        source = c.value(.source, d.source)
        pitch = c.value(.pitch, d.pitch)
        amplitude = c.value(.amplitude, d.amplitude)
        definitions = c.value(.definitions, d.definitions)
        parameters = c.value(.parameters, d.parameters)
        polyphony = c.value(.polyphony, d.polyphony)
        useAdvancedEditor = c.value(.useAdvancedEditor, d.useAdvancedEditor)
        summary = c.value(.summary, d.summary)
    }
}

/// Role "Anzeige": a curve that is only drawn (explanations such as a beat envelope).
struct DisplayCurve: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Unit: String, Codable, CaseIterable, Identifiable, Sendable {
        case hertz, semitones, octaves, gain, free
        /// Audio-rate curve, drawn in the audio snippet with a millisecond axis.
        case signal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hertz: return "Hz"
            case .semitones: return "Halbtöne"
            case .octaves: return "Oktaven"
            case .gain: return "Verstärkung"
            case .free: return "Wert"
            case .signal: return "Signal (ms)"
            }
        }
    }

    var id = UUID()
    var name: String
    var formula: String
    var color: VoiceColor = .violet
    var unit: Unit = .free
    /// The curve sees the definitions and trigger events of this voice (optional).
    var voiceID: UUID?

    init(name: String, formula: String, color: VoiceColor = .violet, unit: Unit = .free, voiceID: UUID? = nil) {
        self.name = name
        self.formula = formula
        self.color = color
        self.unit = unit
        self.voiceID = voiceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Anzeige")
        formula = c.value(.formula, "0")
        color = c.value(.color, .violet)
        unit = c.value(.unit, .free)
        voiceID = c.value(.voiceID, nil as UUID?)
    }
}

enum LaneLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One lane per unit (Hz, semitones, gain …).
    case byUnit
    /// All pitches converted to Hz in one shared lane.
    case sharedFrequency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byUnit: return "Bahnen je Einheit"
        case .sharedFrequency: return "Gemeinsam in Hz"
        }
    }
}

/// A project of the formula synthesizer (also used by the pendulum mode).
struct SynthProject: Codable, Equatable, Hashable, Sendable {
    var tempo = TempoSettings()
    var xMapping: XMapping = .beats
    var freeXMin: Double = -10
    var freeXMax: Double = 10
    /// Shared definitions for all voices, multi-line.
    var definitions: String = ""
    var parameters: [SynthParameter] = []
    var voices: [SynthVoice] = []
    var displayCurves: [DisplayCurve] = []
    /// Peak level of the mix before the safety limiter (dBFS).
    var masterLevelDecibels: Double = -3
    /// Seed of all noise generators (reproducible preview and export).
    var noiseSeed: UInt64 = 0x5EED_DE40_6A11_0001
    var laneLayout: LaneLayout = .byUnit
    var showTrails = true
    var showSignalSnippet = true

    static let maximumVoices = 8
    static let masterLevelRange: ClosedRange<Double> = -24...0

    init() {}

    init(tempo: TempoSettings, xMapping: XMapping = .beats, voices: [SynthVoice], definitions: String = "",
         displayCurves: [DisplayCurve] = []) {
        self.tempo = tempo
        self.xMapping = xMapping
        self.voices = voices
        self.definitions = definitions
        self.displayCurves = displayCurves
    }

    var duration: Double { tempo.duration }

    /// Voices that are audible: not muted, and (if any voice is solo) solo.
    var audibleVoices: [SynthVoice] {
        let hasSolo = voices.contains(where: \.isSolo)
        return voices.filter { !$0.isMuted && (!hasSolo || $0.isSolo) }
    }

    var isPendulumProject: Bool {
        !voices.isEmpty && voices.allSatisfy { $0.trigger.kind == .pendulum }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SynthProject()
        tempo = c.value(.tempo, d.tempo)
        xMapping = c.value(.xMapping, d.xMapping)
        freeXMin = c.value(.freeXMin, d.freeXMin)
        freeXMax = c.value(.freeXMax, d.freeXMax)
        definitions = c.value(.definitions, d.definitions)
        parameters = c.value(.parameters, d.parameters)
        voices = c.value(.voices, d.voices)
        displayCurves = c.value(.displayCurves, d.displayCurves)
        masterLevelDecibels = c.value(.masterLevelDecibels, d.masterLevelDecibels)
        noiseSeed = c.value(.noiseSeed, d.noiseSeed)
        laneLayout = c.value(.laneLayout, d.laneLayout)
        showTrails = c.value(.showTrails, d.showTrails)
        showSignalSnippet = c.value(.showSignalSnippet, d.showSignalSnippet)
    }
}
