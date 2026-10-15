import Foundation

/// A trigger of a voice at an exact frame.
struct NoteEvent: Equatable, Sendable {
    var frame: Int
    /// Zero-based counter `n` (steps of a sequencer, otherwise events of the voice).
    var index: Int
    /// Note value in semitones (`note` in formulas).
    var note: Double = 0
    var velocity: Double = 1
    /// Gate length for polyphonic voices (nil = until the next event).
    var lengthFrames: Int?
    /// Raw generator value (Fibonacci residue, Pascal row, pitch class …) for displays.
    var value: Double?
}

/// Result of planning the events of one voice.
struct VoiceSchedule: Equatable, Sendable {
    var events: [NoteEvent]
    /// The rate of an accelerating repetition was limited (visible note in the UI).
    var rateLimited = false
    /// Beat from which the rate was limited.
    var limitedFromBeat: Double?
    /// Event list was cut at the maximum number of events.
    var truncated = false

    /// The event that is active at `frame` (last event at or before it), as an index into `events`.
    func activeEventIndex(atFrame frame: Int) -> Int? {
        var low = 0
        var high = events.count - 1
        var result: Int?
        while low <= high {
            let middle = (low + high) / 2
            if events[middle].frame <= frame {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }
}

/// Plans all events of a voice ahead of rendering, sample-accurately from the musical clock.
/// Preview, export, graph and visualisations use the same plan.
enum EventScheduler {
    /// Limit of events per voice and pass (resource limit).
    static let maximumEvents = 20_000

    /// - Parameter rate: events per beat at a frame (only for the `.rate` trigger).
    static func schedule(_ voice: SynthVoice, clock: MusicalClock, rate: ((Int) -> Double)? = nil) -> VoiceSchedule {
        let trigger = voice.trigger
        let gate: Int? = voice.polyphony > 1 ? max(1, Int((max(trigger.noteLengthBeats, 1.0 / 64) * clock.framesPerBeat).rounded())) : nil
        switch trigger.kind {
        case .continuous:
            return VoiceSchedule(events: [NoteEvent(frame: 0, index: 0, lengthFrames: nil)])
        case .pattern:
            return pattern(trigger, clock: clock, gate: gate)
        case .rate:
            return accelerating(trigger, clock: clock, rate: rate ?? { _ in 1 }, gate: gate)
        case .pendulum:
            let math = PendulumMath(trigger: trigger)
            let beats = math.triggerBeats(before: clock.totalBeats)
            var events: [NoteEvent] = []
            for (index, beat) in beats.prefix(maximumEvents).enumerated() {
                events.append(NoteEvent(frame: clock.frame(atBeat: beat), index: index, lengthFrames: gate))
            }
            return VoiceSchedule(events: events, truncated: beats.count > maximumEvents)
        case .sequencer:
            return sequencer(trigger, clock: clock, gate: gate)
        }
    }

    private static func pattern(_ trigger: VoiceTrigger, clock: MusicalClock, gate: Int?) -> VoiceSchedule {
        let rhythm = RhythmPattern(trigger.pattern)
        let step = trigger.stepBeats.clamped(to: VoiceTrigger.stepRange, fallback: 1)
        var events: [NoteEvent] = []
        var stepIndex = 0
        var truncated = false
        while true {
            let beat = trigger.offsetBeats + Double(stepIndex) * step
            if beat >= clock.totalBeats - 1e-9 { break }
            if beat >= 0, let velocity = rhythm.steps[stepIndex % rhythm.steps.count] {
                if events.count >= maximumEvents {
                    truncated = true
                    break
                }
                events.append(NoteEvent(frame: clock.frame(atBeat: beat), index: events.count, velocity: velocity, lengthFrames: gate))
            }
            stepIndex += 1
        }
        return VoiceSchedule(events: events, truncated: truncated)
    }

    /// Accelerating repetition: phase(beat) = ∫ rate d(beat); an event at every integer crossing.
    /// The rate is evaluated at the middle of 16-frame blocks (midpoint rule) and the crossing
    /// frame inside a block is computed exactly – never phase = t / period(t).
    private static func accelerating(_ trigger: VoiceTrigger, clock: MusicalClock, rate: (Int) -> Double, gate: Int?) -> VoiceSchedule {
        let block = 16
        let limitPerSecond = trigger.maximumEventsPerSecond.clamped(to: 0.5...VoiceTrigger.maximumRate, fallback: 24)
        let limitPerBeat = limitPerSecond / clock.beatsPerSecond
        var events = [NoteEvent(frame: 0, index: 0, lengthFrames: gate)]
        var phase = 0.0
        var limited = false
        var limitedFrom: Double?
        var frame = 0
        while frame < clock.totalFrames {
            let count = min(block, clock.totalFrames - frame)
            var perBeat = rate(frame + count / 2)
            if !perBeat.isFinite || perBeat < 0 { perBeat = 0 }
            if perBeat > limitPerBeat {
                perBeat = limitPerBeat
                if !limited {
                    limited = true
                    limitedFrom = clock.beat(atFrame: Double(frame))
                }
            }
            let increment = perBeat / clock.framesPerBeat
            if increment > 0 {
                var nextInteger = floor(phase) + 1
                let end = phase + increment * Double(count)
                while nextInteger <= end + 1e-12 {
                    let offset = Int(((nextInteger - phase) / increment - 1e-9).rounded(.up))
                    let eventFrame = frame + max(0, offset)
                    if eventFrame < clock.totalFrames {
                        if events.count >= maximumEvents {
                            return VoiceSchedule(events: events, rateLimited: limited, limitedFromBeat: limitedFrom, truncated: true)
                        }
                        events.append(NoteEvent(frame: eventFrame, index: events.count, lengthFrames: gate))
                    }
                    nextInteger += 1
                }
                phase = end
            }
            frame += count
        }
        return VoiceSchedule(events: events, rateLimited: limited, limitedFromBeat: limitedFrom)
    }

    private static func sequencer(_ trigger: VoiceTrigger, clock: MusicalClock, gate: Int?) -> VoiceSchedule {
        let settings = trigger.sequencer
        let rhythm = RhythmPattern(settings.rhythm)
        let step = settings.stepBeats.clamped(to: VoiceTrigger.stepRange, fallback: 0.5)
        let notes = settings.notes.isEmpty ? [0] : settings.notes
        let modulus = min(max(settings.modulus, SequencerSettings.modulusRange.lowerBound), SequencerSettings.modulusRange.upperBound)
        let rows = min(max(settings.rows, SequencerSettings.rowsRange.lowerBound), SequencerSettings.rowsRange.upperBound)
        let voices = min(max(settings.maximumVoices, SequencerSettings.voicesRange.lowerBound), SequencerSettings.voicesRange.upperBound)
        var fibonacci = FibonacciModulo(modulus: modulus)
        var events: [NoteEvent] = []
        var stepIndex = 0
        var active = 0
        var truncated = false
        while true {
            let beat = Double(stepIndex) * step
            if beat >= clock.totalBeats - 1e-9 { break }
            defer { stepIndex += 1 }
            // The rhythm cycles independently of the note sequence.
            guard let velocity = rhythm.steps[stepIndex % rhythm.steps.count] else { continue }
            let frame = clock.frame(atBeat: beat)
            var produced: [(note: Double, value: Double)] = []
            switch settings.kind {
            case .fibonacci:
                let residue = fibonacci.next() ?? 0
                produced = [(notes[residue % notes.count], Double(residue))]
            case .pascal:
                let row = active % rows
                produced = PascalParity.limitedPositions(row: row, limit: voices).map { position in
                    (notes[position % notes.count] + 12 * Double(position / notes.count), Double(row))
                }
            case .circleOfFifths:
                let pitchClass = FifthsSequence.pitchClass(step: active)
                produced = [(Double(pitchClass), Double(pitchClass))]
            case .diatonicFifths:
                let degree = FifthsSequence.diatonicDegree(step: active)
                produced = [(FifthsSequence.majorScale[degree], Double(degree))]
            case .tritone:
                let isTritone = active % 2 == 1
                produced = [(isTritone ? 6 : 0, isTritone ? 1 : 0)]
            }
            for item in produced {
                if events.count >= maximumEvents {
                    truncated = true
                    break
                }
                events.append(NoteEvent(frame: frame, index: active, note: item.note, velocity: velocity, lengthFrames: gate, value: item.value))
            }
            if truncated { break }
            active += 1
        }
        return VoiceSchedule(events: events, truncated: truncated)
    }
}
