import Foundation

/// The modes of "Graph & Klang". Saved projects keep their mode: "graph" and "waveform"
/// are the two original modes and keep their meaning.
enum SoundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// "Graph vertonen": the height of the curve controls the pitch.
    case graph
    /// "Formel als Klangwelle": the function itself is the waveform.
    case waveform
    /// "Formel-Synthesizer": several voices with explicit formula roles and musical time.
    case synthesizer
    /// "Pendel": six pendulums trigger notes at their midline crossings.
    case pendulum

    var id: String { rawValue }

    /// The two original modes rendered by `PCMRenderer`.
    static let classic: [SoundMode] = [.graph, .waveform]

    var isClassic: Bool { self == .graph || self == .waveform }

    var title: String {
        switch self {
        case .graph: return "Graph vertonen"
        case .waveform: return "Formel als Klangwelle"
        case .synthesizer: return "Formel-Synthesizer"
        case .pendulum: return "Pendel"
        }
    }

    var shortTitle: String {
        switch self {
        case .graph: return "Graph"
        case .waveform: return "Klangwelle"
        case .synthesizer: return "Synthesizer"
        case .pendulum: return "Pendel"
        }
    }

    var icon: String {
        switch self {
        case .graph: return "chart.xyaxis.line"
        case .waveform: return "waveform"
        case .synthesizer: return "slider.vertical.3"
        case .pendulum: return "metronome"
        }
    }

    var explanation: String {
        switch self {
        case .graph:
            return "Ein Punkt wandert von links nach rechts über die Kurve. Je höher die Kurve, desto höher der Ton. Definitionslücken werden sanft stummgeschaltet."
        case .waveform:
            return "Hier wird die Kurve selbst zur Klangwelle. Die Grundfrequenz bestimmt, wie oft der gewählte Abschnitt pro Sekunde wiederholt wird."
        case .synthesizer:
            return "Mehrere Stimmen mit gemeinsamer musikalischer Zeit. Jede Formel hat eine ausdrückliche Rolle: Tonhöhe, Amplitude oder Audiosignal."
        case .pendulum:
            return "Sechs Pendel schwingen mit 6 bis 11 Schwingungen in 16 Beats und lösen beim Mitteldurchgang ihre Note aus."
        }
    }
}

/// Oscillator timbre for the "Graph vertonen" mode.
enum Timbre: String, Codable, CaseIterable, Identifiable, Sendable {
    case sine
    case triangle
    case rich

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sine: return "Sinus"
        case .triangle: return "Dreieck"
        case .rich: return "Obertonreich"
        }
    }

    var explanation: String {
        switch self {
        case .sine: return "Reiner Ton ohne Obertöne."
        case .triangle: return "Weicher Ton mit ungeraden Obertönen."
        case .rich: return "Kräftiger Synthesizerklang, bandbegrenzt aus vielen Obertönen aufgebaut."
        }
    }
}

enum PitchRangeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatisch"
        case .manual: return "Manuell"
        }
    }
}

/// All sound related settings. Value type; every playback and export takes a snapshot.
struct SoundSettings: Codable, Equatable, Hashable, Sendable {
    var mode: SoundMode = .graph
    /// Duration of one pass in seconds (1 … 120).
    var duration: Double = 10

    // MARK: Graph vertonen
    var playXMin: Double = -10
    var playXMax: Double = 10
    var pitchRangeMode: PitchRangeMode = .automatic
    var manualYLow: Double = -1
    var manualYHigh: Double = 1
    var frequencyLow: Double = 110
    var frequencyHigh: Double = 880
    var timbre: Timbre = .sine
    /// Time constant of the pitch glide in milliseconds (0 = none).
    var glideMilliseconds: Double = 8

    // MARK: Formel als Klangwelle
    var sectionStart: Double = 0
    var sectionEnd: Double = 2 * Double.pi
    var baseFrequency: Double = 220

    // MARK: Output
    /// Fade-in and fade-out length in milliseconds.
    var fadeMilliseconds: Double = 20
    /// Peak level of the generated signal in dBFS (also the export level).
    var levelDecibels: Double = -3

    static let durationRange: ClosedRange<Double> = 1...120
    static let frequencyRange: ClosedRange<Double> = 20...8000
    static let baseFrequencyRange: ClosedRange<Double> = 20...2000
    static let glideRange: ClosedRange<Double> = 0...200
    static let fadeRange: ClosedRange<Double> = 2...500
    static let levelRange: ClosedRange<Double> = -24...0
    static let coordinateLimit: Double = 1e6

    init() {}

    /// Values clamped to the supported ranges. Does not reorder inverted ranges.
    func clamped() -> SoundSettings {
        var copy = self
        copy.duration = duration.clamped(to: Self.durationRange, fallback: 10)
        copy.frequencyLow = frequencyLow.clamped(to: Self.frequencyRange, fallback: 110)
        copy.frequencyHigh = frequencyHigh.clamped(to: Self.frequencyRange, fallback: 880)
        copy.baseFrequency = baseFrequency.clamped(to: Self.baseFrequencyRange, fallback: 220)
        copy.glideMilliseconds = glideMilliseconds.clamped(to: Self.glideRange, fallback: 8)
        copy.fadeMilliseconds = fadeMilliseconds.clamped(to: Self.fadeRange, fallback: 20)
        copy.levelDecibels = levelDecibels.clamped(to: Self.levelRange, fallback: -3)
        let limits = -Self.coordinateLimit...Self.coordinateLimit
        copy.playXMin = playXMin.clamped(to: limits, fallback: -10)
        copy.playXMax = playXMax.clamped(to: limits, fallback: 10)
        copy.manualYLow = manualYLow.clamped(to: limits, fallback: -1)
        copy.manualYHigh = manualYHigh.clamped(to: limits, fallback: 1)
        copy.sectionStart = sectionStart.clamped(to: limits, fallback: 0)
        copy.sectionEnd = sectionEnd.clamped(to: limits, fallback: 2 * Double.pi)
        return copy
    }

    /// A user-facing problem that prevents rendering, or nil.
    var validationIssue: String? {
        switch mode {
        case .graph:
            if !(playXMax > playXMin) {
                return "Der x-Bereich ist ungültig: xMin muss kleiner als xMax sein."
            }
            if !(frequencyHigh > frequencyLow) {
                return "Die höchste Frequenz muss über der tiefsten liegen."
            }
            if pitchRangeMode == .manual, !(manualYHigh > manualYLow) {
                return "Der Klangbereich ist ungültig: yLow muss kleiner als yHigh sein."
            }
        case .waveform:
            if !(sectionEnd > sectionStart) {
                return "Der Funktionsabschnitt ist ungültig: Der Anfang muss kleiner als das Ende sein."
            }
        case .synthesizer, .pendulum:
            break
        }
        return nil
    }

    /// Linear peak amplitude for `levelDecibels`.
    var linearLevel: Double {
        pow(10, levelDecibels / 20)
    }

    // MARK: Codable with defaults (older saved states stay readable)

    private enum CodingKeys: String, CodingKey {
        case mode, duration, playXMin, playXMax, pitchRangeMode, manualYLow, manualYHigh
        case frequencyLow, frequencyHigh, timbre, glideMilliseconds
        case sectionStart, sectionEnd, baseFrequency, fadeMilliseconds, levelDecibels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SoundSettings()
        mode = (try? container.decodeIfPresent(SoundMode.self, forKey: .mode)) ?? defaults.mode
        duration = (try? container.decodeIfPresent(Double.self, forKey: .duration)) ?? defaults.duration
        playXMin = (try? container.decodeIfPresent(Double.self, forKey: .playXMin)) ?? defaults.playXMin
        playXMax = (try? container.decodeIfPresent(Double.self, forKey: .playXMax)) ?? defaults.playXMax
        pitchRangeMode = (try? container.decodeIfPresent(PitchRangeMode.self, forKey: .pitchRangeMode)) ?? defaults.pitchRangeMode
        manualYLow = (try? container.decodeIfPresent(Double.self, forKey: .manualYLow)) ?? defaults.manualYLow
        manualYHigh = (try? container.decodeIfPresent(Double.self, forKey: .manualYHigh)) ?? defaults.manualYHigh
        frequencyLow = (try? container.decodeIfPresent(Double.self, forKey: .frequencyLow)) ?? defaults.frequencyLow
        frequencyHigh = (try? container.decodeIfPresent(Double.self, forKey: .frequencyHigh)) ?? defaults.frequencyHigh
        timbre = (try? container.decodeIfPresent(Timbre.self, forKey: .timbre)) ?? defaults.timbre
        glideMilliseconds = (try? container.decodeIfPresent(Double.self, forKey: .glideMilliseconds)) ?? defaults.glideMilliseconds
        sectionStart = (try? container.decodeIfPresent(Double.self, forKey: .sectionStart)) ?? defaults.sectionStart
        sectionEnd = (try? container.decodeIfPresent(Double.self, forKey: .sectionEnd)) ?? defaults.sectionEnd
        baseFrequency = (try? container.decodeIfPresent(Double.self, forKey: .baseFrequency)) ?? defaults.baseFrequency
        fadeMilliseconds = (try? container.decodeIfPresent(Double.self, forKey: .fadeMilliseconds)) ?? defaults.fadeMilliseconds
        levelDecibels = (try? container.decodeIfPresent(Double.self, forKey: .levelDecibels)) ?? defaults.levelDecibels
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard isFinite else { return fallback }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
