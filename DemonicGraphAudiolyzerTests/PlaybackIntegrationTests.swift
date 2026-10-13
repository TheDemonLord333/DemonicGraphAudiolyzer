#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

/// Transport against the real AVAudioEngine (simulator or device). If the environment has no
/// audio output at all, the engine reports an error state and the test ends early.
@Suite("Wiedergabe mit AVAudioEngine", .serialized)
@MainActor
struct PlaybackIntegrationTests {
    private func makeModel(formula: String = "sin(x)", duration: Double = 2) -> AudiolyzerModel {
        let defaults = UserDefaults(suiteName: "PlaybackTests-\(UUID().uuidString)")!
        let model = AudiolyzerModel(sessionStore: SessionStateStore(defaults: defaults, isEnabled: false),
                                    defaults: PlaybackDefaults())
        model.formulaText = formula
        model.settings.duration = duration
        model.isLooping = false
        model.volume = 0.05
        return model
    }

    /// Waits until `condition` is true or the timeout expires.
    private func wait(_ timeout: TimeInterval, until condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func startPlaying(_ model: AudiolyzerModel) async throws -> Bool {
        model.play()
        _ = try await wait(10) { model.phase == .playing || { if case .failed = model.phase { return true } else { return false } }() }
        if case .failed(let message) = model.phase {
            print("Audioausgabe nicht verfügbar, Test beendet: \(message)")
            return false
        }
        return model.phase == .playing
    }

    @Test("Abspielen, Pausieren, Fortsetzen, Stoppen – Position kommt aus der Audiouhr")
    func playPauseResumeStop() async throws {
        let model = makeModel(duration: 4)
        guard try await startPlaying(model) else { return }

        try await Task.sleep(nanoseconds: 700_000_000)
        let running = try #require(model.playbackSnapshot())
        #expect(running.time > 0.2)
        #expect(running.time < 2.0)
        #expect(running.readout.x > -10)

        model.pause()
        #expect(model.phase == .paused)
        let pausedAt = try #require(model.playbackSnapshot()).time
        try await Task.sleep(nanoseconds: 400_000_000)
        let stillPaused = try #require(model.playbackSnapshot()).time
        #expect(abs(stillPaused - pausedAt) < 0.001, "Pausiert darf die Zeit nicht weiterlaufen")

        model.resume()
        #expect(model.phase == .playing)
        try await Task.sleep(nanoseconds: 500_000_000)
        let resumed = try #require(model.playbackSnapshot()).time
        #expect(resumed > pausedAt + 0.2)

        model.stop()
        #expect(model.phase == .ready)
        #expect(model.playbackSnapshot() == nil, "Nach Stopp wird die vollständige Kurve gezeigt")
    }

    @Test("Ohne Wiederholung endet der Durchlauf, mit Wiederholung läuft er weiter")
    func finishAndLoop() async throws {
        let model = makeModel(duration: 1)
        guard try await startPlaying(model) else { return }
        let finished = try await wait(4) { model.phase == .ready }
        #expect(finished, "Durchlauf muss nach 1 s enden")

        model.isLooping = true
        guard try await startPlaying(model) else { return }
        try await Task.sleep(nanoseconds: 1_600_000_000)
        #expect(model.phase == .playing, "Mit Wiederholung läuft die Wiedergabe weiter")
        let wrapped = try #require(model.playbackSnapshot())
        #expect(wrapped.time < 0.9, "Position springt nach dem Ende an den Anfang")
        model.stop()
        #expect(model.phase == .ready)
    }

    @Test("Formeländerung stoppt den laufenden Durchlauf")
    func formulaChangeStops() async throws {
        let model = makeModel(duration: 3)
        guard try await startPlaying(model) else { return }
        model.formulaText = "cos(x)"
        #expect(model.phase == .ready)
        model.formulaText = "cos(x"
        #expect(model.phase == .invalidFormula)
        model.play()
        #expect(model.phase == .invalidFormula, "Ungültige Formel kann nicht abgespielt werden")
    }
}
#endif
