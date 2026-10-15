import Foundation

/// The role an example formula takes when it is opened in the editor.
enum ExampleRole: Equatable, Sendable {
    /// "Graph vertonen": y = f(x).
    case graph
    /// "Formel als Klangwelle": one period over [start, end].
    case waveform(start: Double, end: Double)
    /// Synthesizer: pitch formula with unit.
    case pitch(PitchUnit)
    /// Synthesizer: amplitude envelope.
    case amplitude(AmplitudeScale)
    /// Synthesizer: direct audio signal.
    case signal
}

/// What "Im Editor öffnen" loads: an example with all required parameters, its formula role
/// and the matching mode – or a complete built-in preset.
struct EditorPayload: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case formula(text: String, role: ExampleRole)
        case preset(UUID)
    }

    var title: String
    var content: Content
    /// Classic parameters a, b, c.
    var classicParameters = FormulaParameters()
    /// Named parameters of the synthesizer voice.
    var parameters: [SynthParameter] = []
    /// Additional definitions of the voice (lists, helper functions).
    var definitions = ""
    var tempo = TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2)
    /// Synthesizer voice trigger (default: one event per beat).
    var trigger: VoiceTrigger = {
        var trigger = VoiceTrigger()
        trigger.kind = .pattern
        trigger.pattern = "x"
        trigger.stepBeats = 1
        return trigger
    }()

    static func classic(_ title: String, _ text: String, waveform: Bool = false, parameters: FormulaParameters = FormulaParameters()) -> EditorPayload {
        EditorPayload(title: title, content: .formula(text: text, role: waveform ? .waveform(start: 0, end: 2 * Double.pi) : .graph),
                      classicParameters: parameters)
    }

    static func synth(_ title: String, _ text: String, role: ExampleRole, parameters: [SynthParameter] = [],
                      definitions: String = "") -> EditorPayload {
        EditorPayload(title: title, content: .formula(text: text, role: role), parameters: parameters, definitions: definitions)
    }

    static func preset(_ preset: SoundPreset) -> EditorPayload {
        EditorPayload(title: preset.name, content: .preset(preset.id))
    }

    /// The complete configuration that is loaded (a pure function – tested on all platforms).
    func makePreset() -> SoundPreset? {
        switch content {
        case .preset(let id):
            return BuiltInPresets.preset(withID: id)
        case .formula(let text, let role):
            switch role {
            case .graph:
                var settings = SoundSettings()
                settings.mode = .graph
                return SoundPreset(name: title, summary: "Aus den Anleitungen geöffnet.", formula: text,
                                   parameters: classicParameters, settings: settings)
            case .waveform(let start, let end):
                var settings = SoundSettings()
                settings.mode = .waveform
                settings.sectionStart = start
                settings.sectionEnd = end
                settings.baseFrequency = 220
                settings.duration = 4
                return SoundPreset(name: title, summary: "Aus den Anleitungen geöffnet.", formula: text,
                                   parameters: classicParameters, settings: settings)
            case .pitch, .amplitude, .signal:
                var voice = SynthVoice(name: title, color: .green)
                voice.id = UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1C-000000000001")!
                voice.trigger = trigger
                voice.parameters = parameters
                voice.definitions = definitions
                voice.useAdvancedEditor = text.contains("\n") || !definitions.isEmpty
                voice.source.waveform = .triangle
                voice.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 220)
                voice.amplitude = AmplitudeControl(formula: "exp(-3*localTime)")
                switch role {
                case .pitch(let unit):
                    voice.pitch.formula = text
                    voice.pitch.unit = unit
                case .amplitude(let scale):
                    voice.amplitude = AmplitudeControl(formula: text, scale: scale)
                case .signal:
                    voice.source.kind = .directSignal
                    voice.source.signalFormula = text
                    voice.amplitude = AmplitudeControl(formula: "0.8")
                default:
                    break
                }
                let project = SynthProject(tempo: tempo, xMapping: .seconds, voices: [voice])
                var settings = SoundSettings()
                settings.mode = .synthesizer
                return SoundPreset(name: title, summary: "Aus den Anleitungen geöffnet.", formula: text,
                                   settings: settings, project: project)
            }
        }
    }
}
