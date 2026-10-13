import Foundation

/// Keys for UI preferences stored with `@AppStorage` / `UserDefaults`.
enum PreferenceKey {
    static let lightGraph = "graph.lightMode"
    static let showGrid = "graph.showGrid"
    static let showPreview = "graph.showPreview"
    static let showCursorLine = "graph.showCursorLine"
    static let defaultAutoFitY = "graph.autoFitY"

    static let defaultDuration = "defaults.duration"
    static let defaultVolume = "defaults.volume"
    static let defaultLoop = "defaults.loop"
    static let defaultLevel = "defaults.levelDecibels"

    static let exportFormat = "export.format"
    static let exportSampleRate = "export.sampleRate"
    static let exportWAVBitDepth = "export.wavBitDepth"
    static let exportAACBitrate = "export.aacBitrate"
    static let exportMP3Bitrate = "export.mp3Bitrate"
    static let exportMP3Quality = "export.mp3Quality"

    static let selectedTab = "ui.selectedTab"
    static let lastState = "session.lastState.v1"

    static let all: [String] = [
        lightGraph, showGrid, showPreview, showCursorLine, defaultAutoFitY,
        defaultDuration, defaultVolume, defaultLoop, defaultLevel,
        exportFormat, exportSampleRate, exportWAVBitDepth, exportAACBitrate, exportMP3Bitrate, exportMP3Quality,
        selectedTab, lastState
    ]

    /// Deterministic start for UI tests: forget all stored preferences.
    static func resetAll(in defaults: UserDefaults = .standard) {
        for key in all {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Typed access to the default values chosen in the settings.
struct PlaybackDefaults: Equatable, Sendable {
    var duration: Double = 10
    var volume: Double = 0.6
    var isLooping: Bool = false
    var levelDecibels: Double = -3

    static func load(from defaults: UserDefaults = .standard) -> PlaybackDefaults {
        var result = PlaybackDefaults()
        if defaults.object(forKey: PreferenceKey.defaultDuration) != nil {
            result.duration = defaults.double(forKey: PreferenceKey.defaultDuration).clamped(to: SoundSettings.durationRange, fallback: 10)
        }
        if defaults.object(forKey: PreferenceKey.defaultVolume) != nil {
            result.volume = defaults.double(forKey: PreferenceKey.defaultVolume).clamped(to: 0...1, fallback: 0.6)
        }
        result.isLooping = defaults.bool(forKey: PreferenceKey.defaultLoop)
        if defaults.object(forKey: PreferenceKey.defaultLevel) != nil {
            result.levelDecibels = defaults.double(forKey: PreferenceKey.defaultLevel).clamped(to: SoundSettings.levelRange, fallback: -3)
        }
        return result
    }
}

extension ExportOptions {
    /// Export options pre-filled with the defaults from the settings screen.
    static func defaults(from defaults: UserDefaults = .standard) -> ExportOptions {
        var options = ExportOptions()
        if let raw = defaults.string(forKey: PreferenceKey.exportFormat), let format = ExportFormat(rawValue: raw) {
            options.format = format
        }
        let rate = defaults.double(forKey: PreferenceKey.exportSampleRate)
        if ExportOptions.sampleRates.contains(rate) {
            options.sampleRate = rate
        }
        if let depth = WAVBitDepth(rawValue: defaults.integer(forKey: PreferenceKey.exportWAVBitDepth)) {
            options.wavBitDepth = depth
        }
        let aac = defaults.integer(forKey: PreferenceKey.exportAACBitrate)
        if ExportOptions.aacBitrates.contains(aac) {
            options.aacBitrate = aac
        }
        let mp3 = defaults.integer(forKey: PreferenceKey.exportMP3Bitrate)
        if ExportOptions.mp3Bitrates.contains(mp3) {
            options.mp3Bitrate = mp3
        }
        if defaults.object(forKey: PreferenceKey.exportMP3Quality) != nil,
           let quality = MP3EncodingQuality(rawValue: defaults.integer(forKey: PreferenceKey.exportMP3Quality)) {
            options.mp3Quality = quality
        }
        return options
    }
}

/// The complete working state that is restored after a restart.
struct SessionState: Codable, Equatable, Sendable {
    var preset: SoundPreset
    var viewport: GraphViewport
    var autoFitY: Bool
    var volume: Double
    var isLooping: Bool
    var slowMotionWaveform: Bool

    private enum CodingKeys: String, CodingKey {
        case preset, viewport, autoFitY, volume, isLooping, slowMotionWaveform
    }

    init(preset: SoundPreset, viewport: GraphViewport, autoFitY: Bool, volume: Double, isLooping: Bool, slowMotionWaveform: Bool) {
        self.preset = preset
        self.viewport = viewport
        self.autoFitY = autoFitY
        self.volume = volume
        self.isLooping = isLooping
        self.slowMotionWaveform = slowMotionWaveform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decode(SoundPreset.self, forKey: .preset)
        viewport = (try? container.decode(GraphViewport.self, forKey: .viewport)) ?? .standard
        autoFitY = (try? container.decode(Bool.self, forKey: .autoFitY)) ?? true
        volume = (try? container.decode(Double.self, forKey: .volume)) ?? 0.6
        isLooping = (try? container.decode(Bool.self, forKey: .isLooping)) ?? false
        slowMotionWaveform = (try? container.decode(Bool.self, forKey: .slowMotionWaveform)) ?? false
    }
}

/// Saves and restores the last session state as JSON in `UserDefaults`.
final class SessionStateStore {
    private let defaults: UserDefaults
    private let isEnabled: Bool

    init(defaults: UserDefaults = .standard, isEnabled: Bool = true) {
        self.defaults = defaults
        self.isEnabled = isEnabled
    }

    func load() -> SessionState? {
        guard isEnabled, let data = defaults.data(forKey: PreferenceKey.lastState) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    func save(_ state: SessionState) {
        guard isEnabled, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: PreferenceKey.lastState)
    }
}
