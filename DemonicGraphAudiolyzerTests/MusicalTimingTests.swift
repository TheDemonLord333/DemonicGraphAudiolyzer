import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Musikalische Zeit, Trigger und Generatoren")
struct MusicalTimingTests {
    @Test("beat, bar und beatInBar folgen BPM und Taktart")
    func clockPositions() {
        let clock = MusicalClock(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 4), sampleRate: 48_000)
        #expect(clock.framesPerBeat == 24_000)
        #expect(clock.totalFrames == 384_000)
        let position = clock.position(atFrame: 24_000 * 5.5)
        #expect(position.beat == 5.5)
        #expect(position.bar == 1)
        #expect(position.beatInBar == 1.5)
        #expect(abs(position.time - 2.75) < 1e-12)
        let waltz = MusicalClock(tempo: TempoSettings(bpm: 90, beatsPerBar: 3, bars: 2), sampleRate: 44_100)
        #expect(waltz.position(atFrame: waltz.framesPerBeat * 4).bar == 1)
        #expect(abs(waltz.position(atFrame: waltz.framesPerBeat * 4).beatInBar - 1) < 1e-9)
    }

    @Test("Trigger liegen samplegenau auf dem Beatraster – bei jedem Tempo")
    func sampleAccuratePatternTriggers() {
        for bpm in [60.0, 97.0, 120.0, 174.0] {
            for sampleRate in [44_100.0, 48_000.0] {
                let clock = MusicalClock(tempo: TempoSettings(bpm: bpm, beatsPerBar: 4, bars: 2), sampleRate: sampleRate)
                var voice = SynthVoice()
                voice.trigger.kind = .pattern
                voice.trigger.pattern = "x.x."
                voice.trigger.stepBeats = 0.25
                let events = EventScheduler.schedule(voice, clock: clock).events
                #expect(events.count == 16, "zwei Takte, jede zweite Sechzehntel")
                for (index, event) in events.enumerated() {
                    let exact = Double(index) * 0.5 * 60 / bpm * sampleRate
                    // First sample at or after the exact time.
                    #expect(Double(event.frame) >= exact - 1e-6 && Double(event.frame) < exact + 1, "bpm \(bpm), sr \(sampleRate), event \(index)")
                    #expect(event.index == index)
                }
            }
        }
    }

    @Test("Loop: Der Durchlauf hat eine exakte Länge, Trigger wiederholen sich an denselben Frames")
    func loopConsistency() {
        let clock = MusicalClock(tempo: TempoSettings(bpm: 133, beatsPerBar: 4, bars: 2), sampleRate: 44_100)
        var voice = SynthVoice()
        voice.trigger.kind = .pattern
        voice.trigger.pattern = "x"
        voice.trigger.stepBeats = 1
        let events = EventScheduler.schedule(voice, clock: clock).events
        #expect(events.count == 8)
        #expect(events.allSatisfy { $0.frame < clock.totalFrames })
        // The pass length is the rounded duration: looping restarts the identical frame grid.
        #expect(clock.totalFrames == Int((8 * 60 / 133.0 * 44_100).rounded()))
        // A second pass rendered from frame 0 schedules the same frames.
        #expect(EventScheduler.schedule(voice, clock: clock).events == events)
    }

    @Test("Beschleunigte Wiederholung: integrierte Phase statt t/period(t)")
    func acceleratingRepetition() {
        let clock = MusicalClock(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 3), sampleRate: 44_100)
        var voice = SynthVoice()
        voice.trigger.kind = .rate
        voice.trigger.maximumEventsPerSecond = 64
        // rate(beat) = 2^(beat/4) events per beat → phase = 4/ln2 · (2^(beat/4) − 1)
        let schedule = EventScheduler.schedule(voice, clock: clock) { frame in
            pow(2, clock.beat(atFrame: Double(frame)) / 4)
        }
        let events = schedule.events
        #expect(!schedule.rateLimited)
        #expect(events.count > 10)
        for (k, event) in events.enumerated() {
            let beat = 4 * log2(1 + Double(k) * log(2) / 4)
            let expected = beat * clock.framesPerBeat
            #expect(abs(Double(event.frame) - expected) <= 2, "Ereignis \(k): \(event.frame) statt \(expected)")
        }
        // Spacing shrinks from bar to bar.
        let gaps = zip(events.dropFirst(), events).map { $0.frame - $1.frame }
        #expect(gaps.first! > gaps.last!)
    }

    @Test("Ereignisdichte wird sichtbar begrenzt")
    func rateLimit() {
        let clock = MusicalClock(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2), sampleRate: 44_100)
        var voice = SynthVoice()
        voice.trigger.kind = .rate
        voice.trigger.maximumEventsPerSecond = 8
        let schedule = EventScheduler.schedule(voice, clock: clock) { _ in 100 }
        #expect(schedule.rateLimited)
        #expect(schedule.limitedFromBeat == 0)
        // 8 events per second for 4 s (+ the start event).
        #expect(abs(schedule.events.count - 33) <= 1)
    }

    @Test("Pendel: analytische Trigger, Rückkehr nach 16 Beats, keine verlorenen oder doppelten Trigger bei ausgelassenen Bildern")
    func pendulumTriggers() {
        for cycles in 6...11 {
            let pendulum = PendulumMath(cycles: cycles, periodBeats: 16, bothDirections: true)
            #expect(abs(pendulum.position(atBeat: 0) - 1) < 1e-12)
            #expect(abs(pendulum.position(atBeat: 16) - 1) < 1e-9, "nach 16 Beats wieder in der Ausgangsphase")
            let beats = pendulum.triggerBeats(before: 16)
            #expect(beats.count == 2 * cycles, "zwei Mitteldurchgänge pro Schwingung")
            for beat in beats {
                #expect(abs(pendulum.position(atBeat: beat)) < 1e-9)
            }
            let oneWay = PendulumMath(cycles: cycles, periodBeats: 16, bothDirections: false)
            #expect(oneWay.triggerBeats(before: 16).count == cycles)

            // Irregular display frames (including long gaps): every trigger exactly once.
            var generator = SplitMix64(seed: UInt64(cycles))
            var previous = 0.0
            var seen: [Int] = []
            while previous < 16 {
                let step = generator.nextUnit() < 0.1 ? generator.nextUnit() * 2 : generator.nextUnit() * 0.05
                let current = min(16, previous + step)
                seen += pendulum.triggers(after: previous, upTo: current)
                previous = current
            }
            let expected = Array(0..<beats.count)
            // Triggers at exactly 0 cannot occur (first crossing is at 4/N beats).
            #expect(seen == expected, "N = \(cycles)")
        }
    }

    @Test("Pendel-Trigger im Audio sind samplegenau")
    func pendulumAudioFrames() {
        let clock = MusicalClock(tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 4), sampleRate: 48_000)
        var voice = SynthVoice()
        voice.trigger.kind = .pendulum
        voice.trigger.pendulumCycles = 7
        let events = EventScheduler.schedule(voice, clock: clock).events
        #expect(events.count == 14)
        let first = 4.0 / 7 * clock.framesPerBeat
        #expect(events[0].frame == Int(first.rounded(.up)))
    }

    @Test("Fibonacci modulo m ohne Überlauf, Pisano-Periode")
    func fibonacci() {
        // Exact Fibonacci numbers fit into UInt64 up to F(93).
        var a: UInt64 = 0
        var b: UInt64 = 1
        var iterator = FibonacciModulo(modulus: 7)
        for index in 0...90 {
            #expect(UInt64(iterator.next()!) == a % 7, "F(\(index))")
            #expect(FibonacciModulo.value(at: index, modulus: 7) == Int(a % 7))
            (a, b) = (b, a &+ b)
        }
        // m = 4: 0 1 1 2 3 1 | 0 1 …
        var four = FibonacciModulo(modulus: 4)
        #expect((0..<12).map { _ in four.next()! } == [0, 1, 1, 2, 3, 1, 0, 1, 1, 2, 3, 1])
        #expect(FibonacciModulo.pisanoPeriod(modulus: 4) == 6)
        #expect(FibonacciModulo.pisanoPeriod(modulus: 10) == 60)
        // Huge indices: no overflow, consistent with the period.
        let huge = 1_000_000_000_000
        #expect(FibonacciModulo.value(at: huge, modulus: 4) == FibonacciModulo.value(at: huge % 6, modulus: 4))
        var long = FibonacciModulo(modulus: 24)
        for _ in 0..<1_000_000 { _ = long.next() }
        #expect(long.next()! < 24)
    }

    @Test("Pascal modulo 2 über Bitlogik, ohne Fakultäten")
    func pascal() {
        // Exact binomial coefficients for small rows.
        for row in 0...60 {
            var coefficient: UInt64 = 1
            for k in 0...row {
                #expect(PascalParity.isOdd(row: row, position: k) == (coefficient % 2 == 1), "C(\(row), \(k))")
                if k < row {
                    // C(n, k+1) = C(n, k) · (n − k) / (k + 1) – exact with 128-bit intermediate.
                    let product = coefficient.multipliedFullWidth(by: UInt64(row - k))
                    coefficient = UInt128Helper.divide(high: product.high, low: product.low, by: UInt64(k + 1))
                }
            }
        }
        // Huge rows work (Sierpinski structure): row 2^40 has exactly two odd entries.
        #expect(PascalParity.isOdd(row: 1 << 40, position: 0))
        #expect(!PascalParity.isOdd(row: 1 << 40, position: 1))
        #expect(PascalParity.oddPositions(row: 15).count == 16)
        #expect(PascalParity.limitedPositions(row: 15, limit: 4) == [0, 5, 10, 15])
    }

    @Test("Quintenzirkel und diatonische Quintfolge sind verschiedene Verfahren")
    func fifths() {
        #expect((0..<12).map(FifthsSequence.pitchClass) == [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5])
        #expect(Set((0..<12).map(FifthsSequence.pitchClass)).count == 12, "alle zwölf Tonklassen")
        #expect((0..<7).map(FifthsSequence.diatonicDegree) == [0, 4, 1, 5, 2, 6, 3])
        #expect(FifthsSequence.diatonicSemitones(step: 3) == 9)
        #expect(FifthsSequence.pitchClass(step: -1) == 5, "negative Schritte mit mathematischem mod")
    }

    @Test("Sequencer: Rhythmus und Notenliste mit unterschiedlicher Länge, Tritonus = √2")
    func sequencerEvents() {
        let clock = MusicalClock(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 1), sampleRate: 44_100)
        var voice = SynthVoice()
        voice.trigger.kind = .sequencer
        voice.trigger.sequencer.kind = .fibonacci
        voice.trigger.sequencer.modulus = 4
        voice.trigger.sequencer.notes = [0, 3, 7]
        voice.trigger.sequencer.rhythm = "xx."
        voice.trigger.sequencer.stepBeats = 0.5
        let events = EventScheduler.schedule(voice, clock: clock).events
        // 8 steps, pattern xx. → steps 0,1,3,4,6,7 active.
        #expect(events.map { $0.frame } == [0, 1, 3, 4, 6, 7].map { Int((Double($0) * 0.5 * clock.framesPerBeat).rounded(.up)) })
        // Residues 0,1,1,2,3,1 → notes[residue mod 3].
        #expect(events.map(\.note) == [0, 3, 3, 7, 0, 3])

        voice.trigger.sequencer.kind = .tritone
        voice.trigger.sequencer.rhythm = "x"
        let tritone = EventScheduler.schedule(voice, clock: clock).events
        #expect(tritone.prefix(4).map(\.note) == [0, 6, 0, 6])
        #expect(abs(pow(2, 6.0 / 12) - 2.0.squareRoot()) < 1e-15)

        voice.trigger.sequencer.kind = .pascal
        voice.trigger.sequencer.rows = 4
        voice.trigger.sequencer.maximumVoices = 8
        voice.polyphony = 8
        let pascal = EventScheduler.schedule(voice, clock: clock).events
        // Rows 0,1,2,3: 1, 2, 2, 4 odd entries.
        #expect(pascal.filter { $0.index == 3 }.count == 4)
        #expect(pascal.filter { $0.index == 2 }.count == 2)
        #expect(pascal.allSatisfy { $0.lengthFrames != nil })
    }
}

/// Deterministic random numbers for tests.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

/// 128-by-64 bit division for exact binomial coefficients in the test.
enum UInt128Helper {
    static func divide(high: UInt64, low: UInt64, by divisor: UInt64) -> UInt64 {
        divisor.dividingFullWidth((high: high, low: low)).quotient
    }
}
