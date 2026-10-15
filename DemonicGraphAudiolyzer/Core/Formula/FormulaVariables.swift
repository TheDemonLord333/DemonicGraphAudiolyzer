import Foundation

/// Built-in variables of the formula language. Which ones are available depends on the
/// `FormulaContext` (classic graph modes or formula synthesizer).
enum FormulaVariable: String, CaseIterable, Sendable {
    // Classic modes
    case x, a, b, c
    // Musical time (formula synthesizer)
    case t, beat, bar, beatInBar, localTime, localBeat
    // Trigger and note information
    case n, note, velocity
    // Project and render constants
    case bpm, beatsPerBar, baseFrequency, nyquist

    /// Index of the variable in an evaluation environment (order of `allCases`).
    @inline(__always)
    var slot: Int {
        switch self {
        case .x: return 0
        case .a: return 1
        case .b: return 2
        case .c: return 3
        case .t: return 4
        case .beat: return 5
        case .bar: return 6
        case .beatInBar: return 7
        case .localTime: return 8
        case .localBeat: return 9
        case .n: return 10
        case .note: return 11
        case .velocity: return 12
        case .bpm: return 13
        case .beatsPerBar: return 14
        case .baseFrequency: return 15
        case .nyquist: return 16
        }
    }

    /// a, b, c of the classic modes (sliders).
    var isLegacyParameter: Bool { self == .a || self == .b || self == .c }

    /// Classic names are case-insensitive (old formulas such as `SIN(X)`); new names are exact.
    var isCaseInsensitive: Bool { self == .x || isLegacyParameter }

    var title: String {
        switch self {
        case .x: return "x"
        case .a, .b, .c: return "Parameter \(rawValue)"
        case .t: return "Zeit t"
        case .beat: return "Beatposition"
        case .bar: return "Taktindex"
        case .beatInBar: return "Position im Takt"
        case .localTime: return "Zeit seit dem Trigger"
        case .localBeat: return "Beats seit dem Trigger"
        case .n: return "Triggerzähler"
        case .note: return "Note des Ereignisses"
        case .velocity: return "Anschlagstärke"
        case .bpm: return "Tempo"
        case .beatsPerBar: return "Beats pro Takt"
        case .baseFrequency: return "Grundfrequenz"
        case .nyquist: return "Nyquist-Grenze"
        }
    }

    var unit: String {
        switch self {
        case .x, .a, .b, .c, .n, .note: return ""
        case .t, .localTime: return "s"
        case .beat, .localBeat, .beatInBar: return "Beats"
        case .bar: return "Takte"
        case .velocity: return "0 … 1"
        case .bpm: return "Schläge/min"
        case .beatsPerBar: return "Beats"
        case .baseFrequency, .nyquist: return "Hz"
        }
    }

    var summary: String {
        switch self {
        case .x:
            return "Die Variable der Funktion. In „Graph vertonen“ läuft x in der eingestellten Dauer von xMin nach xMax. Im Formel-Synthesizer wird pro Projekt gewählt, ob x Sekunden (x = t), Beats (x = beat) oder den bisherigen freien x-Durchlauf bedeutet. In einer periodischen Wellenform läuft x je Periode einmal durch den Abschnitt."
        case .a, .b, .c:
            return "Freie Parameter der klassischen Modi mit Schiebereglern (Standard a = 1, b = 1, c = 0)."
        case .t:
            return "Globale Zeit in Sekunden seit dem Start des Durchlaufs."
        case .beat:
            return "Globale Beatposition: beat = t · BPM / 60 (bei konstantem Tempo)."
        case .bar:
            return "Nullbasierter Taktindex: bar = floor(beat / beatsPerBar). Der erste Takt ist 0."
        case .beatInBar:
            return "Position innerhalb des Takts in Beats: beatInBar = mod(beat, beatsPerBar), also 0 bis unter beatsPerBar."
        case .localTime:
            return "Sekunden seit dem letzten Trigger der Stimme. Ohne Trigger (Dauerton) gleich t. Grundlage für Hüllkurven wie exp(-6*localTime)."
        case .localBeat:
            return "Beats seit dem letzten Trigger der Stimme: localBeat = localTime · BPM / 60."
        case .n:
            return "Nullbasierter Zähler der Trigger einer Stimme: beim ersten Ereignis 0, dann 1, 2, … Ideal für Notenlisten: notes[mod(n, len(notes))]."
        case .note:
            return "Notenwert (Halbtöne) des aktuellen Ereignisses aus einem Sequencer oder Pendel; sonst 0."
        case .velocity:
            return "Anschlagstärke des aktuellen Ereignisses (0 … 1): 1 für x im Rhythmusmuster, 0,5 für einen leisen Schlag o. Die Stimme wird automatisch damit multipliziert."
        case .bpm:
            return "Tempo des Projekts in Schlägen pro Minute."
        case .beatsPerBar:
            return "Beats pro Takt des Projekts."
        case .baseFrequency:
            return "Grundfrequenz der Stimme in Hz (Bezug für Halbton- und Oktavangaben)."
        case .nyquist:
            return "Halbe Abtastrate in Hz (22 050 Hz bei 44,1 kHz). Frequenzen darüber würden Aliasing erzeugen."
        }
    }

    static let classic: [FormulaVariable] = [.x, .a, .b, .c]
    static let synth: [FormulaVariable] = [.x, .t, .beat, .bar, .beatInBar, .localTime, .localBeat,
                                           .n, .note, .velocity, .bpm, .beatsPerBar, .baseFrequency, .nyquist]
}

/// Values of the optional formula parameters a, b and c.
struct FormulaParameters: Codable, Equatable, Hashable, Sendable {
    var a: Double = 1
    var b: Double = 1
    var c: Double = 0

    subscript(variable: FormulaVariable) -> Double {
        get {
            switch variable {
            case .a: return a
            case .b: return b
            case .c: return c
            default: return .nan
            }
        }
        set {
            switch variable {
            case .a: a = newValue
            case .b: b = newValue
            case .c: c = newValue
            default: break
            }
        }
    }
}

/// Which names a formula may use.
struct FormulaContext: Equatable, Sendable {
    var variables: Set<FormulaVariable>
    /// Name of the context for error hints.
    var title: String

    /// "Graph vertonen" and "Formel als Klangwelle": x and the parameters a, b, c.
    static let classic = FormulaContext(variables: Set(FormulaVariable.classic), title: "klassischer Modus")
    /// Formula synthesizer: musical time, trigger information and x (mapped per project).
    static let synth = FormulaContext(variables: Set(FormulaVariable.synth), title: "Formel-Synthesizer")
    /// Constant expressions only (numeric input fields).
    static let constant = FormulaContext(variables: [], title: "Zahleneingabe")
}

enum FormulaConstant: String, CaseIterable, Sendable {
    case pi, e

    var value: Double {
        switch self {
        case .pi: return Double.pi
        case .e: return M_E
        }
    }
}
