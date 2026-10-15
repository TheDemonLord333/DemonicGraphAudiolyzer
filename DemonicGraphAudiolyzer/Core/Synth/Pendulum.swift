import Foundation

/// Analytic pendulum: position(beat) = cos(2π · N · beat / P).
///
/// Midline crossings (position 0) happen at beat = (P/4 + m·P/2) / N, m = 0, 1, 2, … – even m
/// while swinging from + to − ("eine Richtung"), odd m on the way back. After P beats all
/// pendulums with integer N are back in phase. Triggers are computed from this formula, never
/// from sampled display frames, so skipped frames cannot lose or double a trigger.
struct PendulumMath: Equatable, Sendable {
    var cycles: Int
    var periodBeats: Double
    var bothDirections: Bool

    init(cycles: Int, periodBeats: Double = 16, bothDirections: Bool = true) {
        self.cycles = max(1, cycles)
        self.periodBeats = max(0.25, periodBeats)
        self.bothDirections = bothDirections
    }

    init(trigger: VoiceTrigger) {
        self.init(cycles: trigger.pendulumCycles, periodBeats: trigger.pendulumPeriodBeats, bothDirections: trigger.pendulumBothDirections)
    }

    func position(atBeat beat: Double) -> Double {
        cos(2 * Double.pi * Double(cycles) * beat / periodBeats)
    }

    private var spacing: Double { (bothDirections ? periodBeats / 2 : periodBeats) / Double(cycles) }
    private var firstCrossing: Double { periodBeats / 4 / Double(cycles) }

    /// Beat of the m-th trigger (m = 0, 1, …).
    func triggerBeat(_ index: Int) -> Double {
        firstCrossing + Double(index) * spacing
    }

    /// All trigger beats in [0, endBeat).
    func triggerBeats(before endBeat: Double) -> [Double] {
        var result: [Double] = []
        var index = 0
        while true {
            let beat = triggerBeat(index)
            if beat >= endBeat - 1e-12 { break }
            result.append(beat)
            index += 1
        }
        return result
    }

    /// Index of the last trigger at or before `beat` (nil before the first one).
    func lastTriggerIndex(atOrBefore beat: Double) -> Int? {
        guard beat + 1e-12 >= firstCrossing else { return nil }
        return Int(floor((beat - firstCrossing) / spacing + 1e-9))
    }

    /// Triggers in the half-open interval (previous, current] – what a display frame has to flash.
    /// Works for any frame spacing; consecutive intervals never share or skip a trigger.
    func triggers(after previous: Double, upTo current: Double) -> [Int] {
        guard current > previous else { return [] }
        let first = (lastTriggerIndex(atOrBefore: previous) ?? -1) + 1
        guard let last = lastTriggerIndex(atOrBefore: current), last >= first else { return [] }
        return Array(first...last)
    }
}

/// Shepard/Risset riser: P partials one octave apart whose log-frequency rises continuously and
/// wraps around; a raised-cosine level window over the octave range fades every partial in at the
/// bottom and out at the top. The ear follows the rising partials while the sum stays similar –
/// a psychoacoustic illusion of endless rising, not a physically unbounded frequency.
struct ShepardRiser: Equatable, Sendable {
    var partials: Int
    var lowestFrequency: Double
    /// Seconds for one octave of rise.
    var cycleSeconds: Double
    var rising: Bool

    init(partials: Int, lowestFrequency: Double, cycleSeconds: Double, rising: Bool) {
        self.partials = max(2, partials)
        self.lowestFrequency = max(1, lowestFrequency)
        self.cycleSeconds = max(0.05, cycleSeconds)
        self.rising = rising
    }

    /// Position of partial `index` in the octave stack (0 … 1) at `time`.
    func position(partial index: Int, time: Double) -> Double {
        let drift = time / (cycleSeconds * Double(partials)) * (rising ? 1 : -1)
        return MathSemantics.frac(Double(index) / Double(partials) + drift)
    }

    func frequency(partial index: Int, time: Double) -> Double {
        lowestFrequency * exp2(Double(partials) * position(partial: index, time: time))
    }

    /// Level window 0 … 1 (raised cosine over the position).
    func level(partial index: Int, time: Double) -> Double {
        0.5 - 0.5 * cos(2 * Double.pi * position(partial: index, time: time))
    }

    /// Sum of all levels: constant P/2 for P ≥ 2 – used for normalisation.
    var levelSum: Double { Double(partials) / 2 }
}
