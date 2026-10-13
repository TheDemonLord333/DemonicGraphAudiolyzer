import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Transport: Zustände und Zeitlinie")
struct TransportTests {
    @Test("Abspielen → Pausieren → Fortsetzen → Stoppen")
    func playPauseResumeStop() {
        var machine = TransportStateMachine()
        #expect(machine.phase == .ready)
        let accepted1 = machine.handle(.play)
        #expect(accepted1)
        #expect(machine.phase == .preparing)
        let accepted2 = machine.handle(.prepared)
        #expect(accepted2)
        #expect(machine.phase == .playing)
        let accepted3 = machine.handle(.pause)
        #expect(accepted3)
        #expect(machine.phase == .paused)
        let accepted4 = machine.handle(.resume)
        #expect(accepted4)
        #expect(machine.phase == .playing)
        let accepted5 = machine.handle(.stop)
        #expect(accepted5)
        #expect(machine.phase == .ready)
    }

    @Test("Ungültige Übergänge werden abgelehnt")
    func invalidTransitions() {
        var machine = TransportStateMachine()
        let accepted6 = machine.handle(.pause)
        #expect(!accepted6)
        let accepted7 = machine.handle(.resume)
        #expect(!accepted7)
        let accepted8 = machine.handle(.prepared)
        #expect(!accepted8)
        #expect(machine.phase == .ready)
        machine.handle(.formulaBecameInvalid)
        #expect(machine.phase == .invalidFormula)
        let accepted9 = machine.handle(.play)
        #expect(!accepted9)
        let accepted10 = machine.handle(.exportStarted)
        #expect(!accepted10)
        machine.handle(.formulaBecameValid)
        #expect(machine.phase == .ready)
    }

    @Test("Formel- oder Klangänderung beendet den Durchlauf")
    func configurationChangeStops() {
        var machine = TransportStateMachine()
        machine.handle(.play)
        machine.handle(.prepared)
        let accepted11 = machine.handle(.configurationChanged)
        #expect(accepted11)
        #expect(machine.phase == .ready)
        machine.handle(.play)
        machine.handle(.prepared)
        machine.handle(.formulaBecameInvalid)
        #expect(machine.phase == .invalidFormula)
    }

    @Test("Ende des Durchlaufs, Export und Fehler")
    func finishExportAndFailure() {
        var machine = TransportStateMachine()
        machine.handle(.play)
        machine.handle(.prepared)
        let accepted12 = machine.handle(.finished)
        #expect(accepted12)
        #expect(machine.phase == .ready)
        let accepted13 = machine.handle(.exportStarted)
        #expect(accepted13)
        #expect(machine.phase == .exporting)
        #expect(machine.phase.title == "Export läuft")
        let accepted14 = machine.handle(.exportEnded)
        #expect(accepted14)
        #expect(machine.phase == .ready)
        let accepted15 = machine.handle(.fail("Kein Audiogerät"))
        #expect(accepted15)
        #expect(machine.phase == .failed("Kein Audiogerät"))
        let accepted16 = machine.handle(.play)
        #expect(accepted16)
        #expect(machine.phase == .preparing)
    }

    @Test("Deutsche Zustandsnamen")
    func titles() {
        #expect(TransportPhase.ready.title == "Bereit")
        #expect(TransportPhase.invalidFormula.title == "Formel ungültig")
        #expect(TransportPhase.preparing.title == "Audio wird vorbereitet")
        #expect(TransportPhase.playing.title == "Wiedergabe")
        #expect(TransportPhase.paused.title == "Pausiert")
        #expect(TransportPhase.failed("x").title == "Fehler")
    }

    @Test("Zeitlinie: Position aus der Audiouhr, Fortsetzen ab Offset")
    func timelineResume() {
        var timeline = PlaybackTimeline(totalFrames: 1_000, sampleRate: 100, startFrame: 0, isLooping: false)
        #expect(timeline.position(playedFrames: 250).frame == 250)
        #expect(timeline.position(playedFrames: -5).frame == 0)
        // Paused at 400, resumed: the clock restarts at 0, the position continues at 400.
        timeline.startFrame = 400
        #expect(timeline.position(playedFrames: 0).frame == 400)
        #expect(timeline.position(playedFrames: 100).frame == 500)
        let end = timeline.position(playedFrames: 700)
        #expect(end.isFinished)
        #expect(end.frame == 1_000)
        #expect(timeline.duration == 10)
    }

    @Test("Zeitlinie: Wiederholung springt sauber an den Anfang")
    func timelineLoop() {
        let timeline = PlaybackTimeline(totalFrames: 1_000, sampleRate: 100, startFrame: 300, isLooping: true)
        let first = timeline.position(playedFrames: 650)
        #expect(first.frame == 950 && first.completedLoops == 0)
        let wrapped = timeline.position(playedFrames: 900)
        #expect(wrapped.frame == 200)
        #expect(wrapped.completedLoops == 1)
        #expect(!wrapped.isFinished)
        let later = timeline.position(playedFrames: 2_750)
        #expect(later.frame == 50)
        #expect(later.completedLoops == 3)
    }
}
