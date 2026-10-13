import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Wiederherstellung des letzten Zustands")
struct SessionStateTests {
    private func makeDefaults() -> UserDefaults {
        let name = "SessionStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Zustand übersteht einen Neustart (JSON in UserDefaults)")
    func roundTrip() throws {
        let defaults = makeDefaults()
        var preset = BuiltInPresets.parameterWave
        preset.settings.duration = 42
        preset.settings.mode = .waveform
        preset.settings.baseFrequency = 330
        let state = SessionState(preset: preset,
                                 viewport: GraphViewport(xMin: -3, xMax: 4, yMin: -2, yMax: 2),
                                 autoFitY: false, volume: 0.35, isLooping: true, slowMotionWaveform: true)
        SessionStateStore(defaults: defaults).save(state)

        // A new store instance simulates the next app launch.
        let restored = try #require(SessionStateStore(defaults: defaults).load())
        #expect(restored == state)
        #expect(restored.preset.parameters.b == 0.1)
    }

    @Test("Deaktivierter Speicher (UI-Tests) liest und schreibt nichts")
    func disabledStore() {
        let defaults = makeDefaults()
        let store = SessionStateStore(defaults: defaults, isEnabled: false)
        store.save(SessionState(preset: BuiltInPresets.gentleWave, viewport: .standard, autoFitY: true,
                                volume: 0.6, isLooping: false, slowMotionWaveform: false))
        #expect(store.load() == nil)
        #expect(defaults.data(forKey: PreferenceKey.lastState) == nil)
    }

    @Test("Ältere gespeicherte Einstellungen ohne neue Felder bleiben lesbar")
    func forwardCompatibleSettings() throws {
        let json = #"{"mode":"waveform","duration":5}"#
        let settings = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        #expect(settings.mode == .waveform)
        #expect(settings.duration == 5)
        #expect(settings.frequencyLow == 110)
        #expect(settings.frequencyHigh == 880)
    }

    @Test("Standardwerte für Wiedergabe und Export")
    func defaultsFromPreferences() {
        let defaults = makeDefaults()
        #expect(PlaybackDefaults.load(from: defaults) == PlaybackDefaults())
        defaults.set(25.0, forKey: PreferenceKey.defaultDuration)
        defaults.set(0.3, forKey: PreferenceKey.defaultVolume)
        defaults.set(ExportFormat.wav.rawValue, forKey: PreferenceKey.exportFormat)
        defaults.set(24, forKey: PreferenceKey.exportWAVBitDepth)
        let playback = PlaybackDefaults.load(from: defaults)
        #expect(playback.duration == 25)
        #expect(playback.volume == 0.3)
        let export = ExportOptions.defaults(from: defaults)
        #expect(export.format == .wav)
        #expect(export.wavBitDepth == .twentyFour)
        #expect(export.mp3Bitrate == 192)
        #expect(export.aacBitrate == 192)
        #expect(export.sampleRate == 44_100)
    }
}
