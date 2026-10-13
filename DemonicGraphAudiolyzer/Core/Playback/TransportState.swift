import Foundation

/// The clearly defined states of the instrument.
enum TransportPhase: Equatable, Sendable {
    case ready
    case invalidFormula
    case preparing
    case playing
    case paused
    case exporting
    case failed(String)

    var title: String {
        switch self {
        case .ready: return "Bereit"
        case .invalidFormula: return "Formel ungültig"
        case .preparing: return "Audio wird vorbereitet"
        case .playing: return "Wiedergabe"
        case .paused: return "Pausiert"
        case .exporting: return "Export läuft"
        case .failed: return "Fehler"
        }
    }

    var isActive: Bool {
        self == .playing || self == .paused || self == .preparing
    }
}

enum TransportEvent: Equatable, Sendable {
    case formulaBecameInvalid
    case formulaBecameValid
    case play
    case prepared
    case pause
    case resume
    case stop
    case finished
    case configurationChanged
    case exportStarted
    case exportEnded
    case fail(String)
    case dismissError
}

/// Pure state machine for the transport. Invalid transitions are rejected (return false),
/// which keeps the UI and the audio engine consistent.
struct TransportStateMachine: Equatable, Sendable {
    private(set) var phase: TransportPhase = .ready
    /// Remembers whether the formula is valid while exporting/failing.
    private(set) var formulaIsValid = true

    init(phase: TransportPhase = .ready) {
        self.phase = phase
        self.formulaIsValid = phase != .invalidFormula
    }

    private var idlePhase: TransportPhase {
        formulaIsValid ? .ready : .invalidFormula
    }

    @discardableResult
    mutating func handle(_ event: TransportEvent) -> Bool {
        switch (phase, event) {
        case (_, .formulaBecameInvalid):
            formulaIsValid = false
            if phase == .exporting { return true }
            phase = .invalidFormula
            return true
        case (_, .formulaBecameValid):
            formulaIsValid = true
            if phase == .invalidFormula { phase = .ready }
            return true

        case (.ready, .play), (.failed, .play):
            guard formulaIsValid else { return false }
            phase = .preparing
            return true
        case (.preparing, .prepared):
            phase = .playing
            return true
        case (.playing, .pause):
            phase = .paused
            return true
        case (.paused, .resume):
            phase = .playing
            return true
        case (.paused, .play):
            phase = .playing
            return true

        case (.preparing, .stop), (.playing, .stop), (.paused, .stop):
            phase = idlePhase
            return true
        case (.playing, .finished):
            phase = idlePhase
            return true
        case (.preparing, .configurationChanged), (.playing, .configurationChanged), (.paused, .configurationChanged):
            phase = idlePhase
            return true

        case (.ready, .exportStarted), (.paused, .exportStarted), (.playing, .exportStarted), (.failed, .exportStarted):
            guard formulaIsValid else { return false }
            phase = .exporting
            return true
        case (.exporting, .exportEnded):
            phase = idlePhase
            return true

        case (.exporting, .fail(let message)), (.preparing, .fail(let message)),
             (.playing, .fail(let message)), (.paused, .fail(let message)), (.ready, .fail(let message)):
            phase = .failed(message)
            return true
        case (.failed, .dismissError), (.failed, .stop):
            phase = idlePhase
            return true

        default:
            return false
        }
    }
}

/// Converts frames reported by the audio clock into the position inside the rendered pass.
/// Handles resuming from an offset and looping.
struct PlaybackTimeline: Equatable, Sendable {
    let totalFrames: Int
    let sampleRate: Double
    /// Frame inside the pass where the current schedule started (after pause/resume).
    var startFrame: Int
    var isLooping: Bool

    struct Position: Equatable, Sendable {
        var frame: Int
        var completedLoops: Int
        var isFinished: Bool

        func time(sampleRate: Double) -> Double { Double(frame) / sampleRate }
    }

    /// - Parameter playedFrames: frames played since the schedule started (audio clock).
    func position(playedFrames: Double) -> Position {
        let played = max(0, playedFrames)
        let absolute = Double(startFrame) + played
        let total = Double(totalFrames)
        if absolute < total {
            return Position(frame: Int(absolute), completedLoops: 0, isFinished: false)
        }
        guard isLooping, totalFrames > 0 else {
            return Position(frame: totalFrames, completedLoops: 0, isFinished: true)
        }
        let beyond = absolute - total
        let loops = Int(beyond / total) + 1
        let frame = Int(beyond.truncatingRemainder(dividingBy: total))
        return Position(frame: frame, completedLoops: loops, isFinished: false)
    }

    var duration: Double { Double(totalFrames) / sampleRate }
}
