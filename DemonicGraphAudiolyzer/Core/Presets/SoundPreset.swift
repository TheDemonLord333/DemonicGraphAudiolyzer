import Foundation

/// A complete instrument configuration (formula + parameters + sound settings).
/// Used for the built-in examples, for saved presets and for restoring the last state.
struct SoundPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var formula: String
    var parameters: FormulaParameters
    var settings: SoundSettings
    /// Project of the formula synthesizer / pendulum mode (nil for the classic modes).
    var project: SynthProject?
    /// Group in the preset list (built-in presets).
    var category: PresetCategory?

    init(id: UUID = UUID(), name: String, summary: String = "", formula: String,
         parameters: FormulaParameters = FormulaParameters(), settings: SoundSettings = SoundSettings(),
         project: SynthProject? = nil, category: PresetCategory? = nil) {
        self.id = id
        self.category = category
        self.name = name
        self.summary = summary
        self.formula = formula
        self.parameters = parameters
        self.settings = settings
        self.project = project
    }

    var isSynth: Bool { !settings.mode.isClassic }
}

enum PresetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case formulas
    case sequencers
    case generators
    case combinations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Klassische Beispiele"
        case .formulas: return "Formel-Presets"
        case .sequencers: return "Mathematische Sequencer"
        case .generators: return "Pendel, Riser und Beschleunigung"
        case .combinations: return "Kombinationen"
        }
    }

    var icon: String {
        switch self {
        case .classic: return "sparkles"
        case .formulas: return "function"
        case .sequencers: return "square.grid.3x3"
        case .generators: return "metronome"
        case .combinations: return "square.stack.3d.down.forward"
        }
    }
}

/// Examples shipped with the app. They live in code and are never inserted into the
/// database, so they are not re-created on every launch and cannot be duplicated.
enum BuiltInPresets {
    /// The original examples of "Graph vertonen" and "Formel als Klangwelle".
    static let classic: [SoundPreset] = [
        gentleWave, doubleWave, steps, dampedWave, waveCrest, experiment, parameterWave
    ].map { preset in
        var copy = preset
        copy.category = .classic
        return copy
    }

    /// All built-in presets: classic examples, formula presets, sequencers, generators, combinations.
    static let all: [SoundPreset] = classic + SynthPresets.all

    static func preset(withID id: UUID) -> SoundPreset? {
        all.first { $0.id == id }
    }

    // Stable identifiers so selection state survives restarts.
    static let gentleWave = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A1")!,
        name: "Sanfte Welle",
        summary: "Die klassische Sinuskurve: ruhiges Auf und Ab der Tonhöhe.",
        formula: "sin(x)",
        settings: makeSettings { $0.timbre = .sine })

    static let doubleWave = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A2")!,
        name: "Doppelwelle",
        summary: "Grundwelle plus halb so hohe doppelte Frequenz – ein wiegendes Motiv.",
        formula: "sin(x) + 0.5sin(2x)",
        settings: makeSettings { $0.timbre = .triangle })

    static let steps = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A3")!,
        name: "Stufen",
        summary: "Abrundungsfunktion: Jede Stufe ist ein eigener Ton – eine Tonleiter aus dem Graphen.",
        formula: "floor(x)",
        settings: makeSettings {
            $0.playXMin = -6
            $0.playXMax = 6
            $0.timbre = .rich
            $0.glideMilliseconds = 4
            $0.duration = 12
        })

    static let dampedWave = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A4")!,
        name: "Gedämpfte Welle",
        summary: "Schnelle Schwingung, die zur Mitte anschwillt und zu den Rändern abklingt.",
        formula: "sin(4*x)exp(-0.2abs(x))",
        settings: makeSettings {
            $0.timbre = .triangle
            $0.duration = 12
        })

    static let waveCrest = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A5")!,
        name: "Wellenkamm",
        summary: "Betrag der Sinuswelle: nur positive Bögen mit spitzen Tälern.",
        formula: "abs(sin(3*x))",
        settings: makeSettings {
            $0.playXMin = -5
            $0.playXMax = 5
            $0.timbre = .rich
            $0.frequencyLow = 146.83
            $0.frequencyHigh = 587.33
        })

    static let experiment = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A6")!,
        name: "Experiment",
        summary: "Als Klangwelle gespielt: Das Produkt zweier Schwingungen ergibt einen obertonreichen Klang.",
        formula: "sin(x)cos(3x)",
        settings: makeSettings {
            $0.mode = .waveform
            $0.sectionStart = 0
            $0.sectionEnd = 2 * Double.pi
            $0.baseFrequency = 110
            $0.duration = 6
        })

    static let parameterWave = SoundPreset(
        id: UUID(uuidString: "6D3C8E8A-1F7B-4C1E-9E1A-0000000000A7")!,
        name: "Parameterwelle",
        summary: "Arkussinus mit Parametern: b staucht die Kurve, c verschiebt sie. Für |b·x| > 1 entsteht eine Definitionslücke.",
        formula: "asin(bx)+c",
        parameters: FormulaParameters(a: 1, b: 0.1, c: 0),
        settings: makeSettings { $0.timbre = .sine })

    private static func makeSettings(_ configure: (inout SoundSettings) -> Void) -> SoundSettings {
        var settings = SoundSettings()
        configure(&settings)
        return settings
    }
}
