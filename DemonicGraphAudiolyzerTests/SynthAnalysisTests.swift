import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Mehrspur-Graph und Anzeigen")
struct SynthAnalysisTests {
    @Test("Bahnen je Einheit, gemeinsame Amplitudenbahn und Anzeigekurven")
    func lanes() throws {
        let project = try #require(SynthPresets.reese.project)
        let compilation = SynthCompilation(project: project, sampleRate: 44_100)
        let graph = SynthAnalysis.graph(compilation, baseSamples: 200)
        let pitch = try #require(graph.lanes.first { $0.kind == .pitch(.hertz) })
        #expect(pitch.curves.count == 2, "beide Oszillatoren in derselben Hz-Bahn")
        let amplitude = try #require(graph.lanes.first { $0.kind == .amplitude })
        #expect(amplitude.curves.contains { $0.isDisplayOnly && $0.name == "Schwebungshüllkurve" })
        #expect(graph.xRange.lowerBound == 0)
        #expect(abs(graph.xRange.upperBound - project.tempo.duration) < 1e-9, "x = Sekunden")

        var shared = project
        shared.laneLayout = .sharedFrequency
        let sharedGraph = SynthAnalysis.graph(SynthCompilation(project: shared, sampleRate: 44_100), baseSamples: 200)
        let frequency = try #require(sharedGraph.lanes.first { $0.kind == .frequency })
        #expect(frequency.curves.count == 2)
        #expect(frequency.isLogFrequency)

        // Hidden voices are not drawn.
        var hidden = project
        hidden.voices[1].isVisible = false
        let hiddenGraph = SynthAnalysis.graph(SynthCompilation(project: hidden, sampleRate: 44_100), baseSamples: 200)
        #expect(hiddenGraph.lanes.first { $0.kind == .pitch(.hertz) }?.curves.count == 1)
    }

    @Test("Ereignisbahn, Riser-Bahn und begrenzte Raten werden gemeldet")
    func specialLanes() throws {
        let drums = SynthAnalysis.graph(SynthCompilation(project: try #require(SynthPresets.drumPattern.project), sampleRate: 44_100), baseSamples: 100)
        #expect(drums.lanes.contains { $0.kind == .events })
        #expect(drums.voiceOrder.count == 3)
        let riserProject = try #require(SynthPresets.endlessRiser.project)
        let riser = SynthAnalysis.graph(SynthCompilation(project: riserProject, sampleRate: 44_100), baseSamples: 100)
        #expect(riser.lanes.contains { $0.kind == .riser(riserProject.voices[0].id) })
        let accelerating = SynthAnalysis.graph(SynthCompilation(project: try #require(SynthPresets.accelerating.project), sampleRate: 44_100), baseSamples: 100)
        #expect(!accelerating.rateLimited.isEmpty, "Beschleunigung wird sichtbar begrenzt")
    }

    @Test("Aktiver Formelabschnitt und aktuelle Parameter")
    func activeSectionAndParameters() throws {
        let project = try #require(SynthPresets.shapeshifter.project)
        let compilation = SynthCompilation(project: project, sampleRate: 44_100)
        let probe = VoiceProbe(compiled: try #require(compilation.voices.first), compilation: compilation)
        let clock = compilation.clock
        #expect(probe.activeCase(role: .signal, atFrame: clock.frame(atBeat: 1)) == 0, "Takt 0: Sägezahn")
        #expect(probe.activeCase(role: .signal, atFrame: clock.frame(atBeat: 5)) == 1, "Takt 1: Dreieck")
        #expect(probe.activeCase(role: .signal, atFrame: clock.frame(atBeat: 9)) == 2, "Takt 2: Sonst-Fall Pluck")

        let kick = try #require(SynthPresets.kickRoll.project)
        let period = try #require(kick.voices[0].parameters.first { $0.name == "period" })
        #expect(SynthAnalysis.value(of: period, position: clock.position(atFrame: 0)) == 1)
        #expect(SynthAnalysis.value(of: period, position: MusicalPosition(time: 0, beat: 5, bar: 1, beatInBar: 1)) == 0.5)

        let readout = SynthAnalysis.readout(compilation, probes: [probe], frame: clock.frame(atBeat: 1.25))
        #expect(readout.first?.eventIndex == 1)
        #expect(readout.first?.frequency.map { abs($0 - 110 * pow(2, 3.0 / 12)) < 1e-9 } == true, "zweiter Ton der Liste: 3 Halbtöne")
    }

    @Test("Zahlenlisten aus Eingabefeldern")
    func numberLists() {
        #expect(NumberListParser.parse("0; 3; 7; 10") == [0, 3, 7, 10])
        #expect(NumberListParser.parse("0, 3, 7") == [0, 3, 7])
        #expect(NumberListParser.parse("[0, -2, 4]") == [0, -2, 4])
        #expect(NumberListParser.parse("0,5; 1,5") == [0.5, 1.5])
        #expect(NumberListParser.parse("0,5 1,5") == [0.5, 1.5])
        #expect(NumberListParser.parse("1,2,3") == [1, 2, 3])
        #expect(NumberListParser.parse("0,25") == [0.25])
        #expect(NumberListParser.parse("2pi")?.first.map { abs($0 - 2 * Double.pi) < 1e-12 } == true)
        #expect(NumberListParser.parse("") == nil)
        #expect(NumberListParser.parse("1; x") == nil)
    }
}
