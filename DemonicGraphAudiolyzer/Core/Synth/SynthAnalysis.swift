import Foundation

/// One curve inside a lane of the multi-lane graph.
struct LaneCurve: Sendable {
    var id: String
    var voiceID: UUID?
    var name: String
    var color: VoiceColor
    var curve: SampledCurve
    var isDisplayOnly: Bool
}

/// A horizontal lane of the synthesizer graph (shared time axis).
struct GraphLane: Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Pitch formula values in their unit.
        case pitch(PitchUnit)
        /// All pitches converted to Hz, drawn on a log2 axis.
        case frequency
        /// Gains (linear) of all voices.
        case amplitude
        /// Display-only curves without unit.
        case display(DisplayCurve.Unit)
        /// Event ticks of every voice (drums, sequencers, pendulums).
        case events
        /// Shepard riser partials of a voice.
        case riser(UUID)
    }

    var id: String
    var kind: Kind
    var title: String
    var unitLabel: String
    var curves: [LaneCurve]
    var yRange: ClosedRange<Double>
    /// The y axis shows log2 values with Hz labels.
    var isLogFrequency: Bool { kind == .frequency }
}

/// Settings of a riser voice for its lane.
struct RiserDisplay: Equatable, Sendable {
    var partials: Int
    var lowest: Double
    var cycleBeats: Double
    var rising: Bool
    var color: VoiceColor
}

/// Everything the synthesizer graph draws, computed off the main thread from a compilation.
struct SynthGraphData: Sendable {
    var lanes: [GraphLane]
    /// Range of the x axis (project x mapping: seconds, beats or free x).
    var xRange: ClosedRange<Double>
    var mapping: XMappingFunction
    var voiceEvents: [UUID: [NoteEvent]]
    var voiceOrder: [(id: UUID, name: String, color: VoiceColor)]
    var rateLimited: [UUID: Double]
    var riserSettings: [UUID: RiserDisplay] = [:]

    static let empty = SynthGraphData(lanes: [], xRange: 0...1,
                                      mapping: XMappingFunction(project: SynthProject(), clock: MusicalClock(tempo: TempoSettings(), sampleRate: 44_100)),
                                      voiceEvents: [:], voiceOrder: [], rateLimited: [:])
}

/// Evaluates the role formulas of a voice at arbitrary frames (graph sampling, read-outs).
/// Not thread-safe: create one per task.
final class VoiceProbe {
    let compiled: CompiledVoice
    let schedule: VoiceSchedule
    let clock: MusicalClock
    let mapping: XMappingFunction
    let normalizedRange: PitchConversion.NormalizedRange?
    private let buffer: EvaluationBuffer

    init(compiled: CompiledVoice, compilation: SynthCompilation) {
        self.compiled = compiled
        self.schedule = compilation.schedules[compiled.voice.id] ?? VoiceSchedule(events: [])
        self.clock = compilation.clock
        self.mapping = compilation.xMapping
        self.buffer = EvaluationBuffer(capacity: compiled.slotCount)
        if compiled.voice.pitch.unit == .normalized {
            normalizedRange = SynthPlan.normalizedRange(compiled, schedule: schedule, compilation: compilation)
        } else {
            normalizedRange = nil
        }
    }

    func event(atFrame frame: Int) -> NoteEvent? {
        schedule.activeEventIndex(atFrame: frame).map { schedule.events[$0] }
    }

    private func prepare(_ frame: Int) {
        VoiceInputs.set(buffer, frame: frame, event: event(atFrame: frame), clock: clock, xMapping: mapping)
    }

    /// Raw value of the pitch formula (in its unit).
    func pitchValue(atFrame frame: Int) -> Double {
        guard let program = compiled.pitch?.program else { return .nan }
        prepare(frame)
        return buffer.evaluate(program)
    }

    func frequency(atFrame frame: Int) -> Double? {
        let voice = compiled.voice
        if voice.source.kind == .directSignal { return nil }
        if voice.source.kind == .riser { return nil }
        let value = compiled.pitch == nil ? 0 : pitchValue(atFrame: frame)
        return PitchConversion.frequency(value: value, unit: voice.pitch.unit, baseFrequency: voice.pitch.baseFrequency,
                                         quantization: voice.pitch.quantization, normalized: normalizedRange,
                                         maximum: 0.45 * clock.sampleRate)
    }

    /// Linear gain of the amplitude formula (dB converted).
    func gain(atFrame frame: Int) -> Double {
        guard let program = compiled.amplitude?.program else { return .nan }
        prepare(frame)
        let value = buffer.evaluate(program)
        guard value.isFinite else { return .nan }
        return PitchConversion.gain(value: value, scale: compiled.voice.amplitude.scale)
    }

    /// Index of the active case of the first case distinction in a role formula.
    func activeCase(role: SynthField, atFrame frame: Int) -> Int? {
        let program: CompiledProgram?
        switch role {
        case .pitch: program = compiled.pitch?.program
        case .amplitude: program = compiled.amplitude?.program
        case .signal: program = compiled.signal?.program
        default: program = nil
        }
        guard let program else { return nil }
        prepare(frame)
        var inputs = [Double](repeating: 0, count: CompiledProgram.inputCount)
        for index in 0..<CompiledProgram.inputCount { inputs[index] = buffer.pointer[index] }
        // Fixed values (bpm, …) are folded in the program; the interpreter needs them as inputs.
        inputs[FormulaVariable.bpm.slot] = clock.tempo.bpm
        inputs[FormulaVariable.beatsPerBar.slot] = Double(clock.tempo.beatsPerBar)
        inputs[FormulaVariable.baseFrequency.slot] = compiled.voice.pitch.baseFrequency
        inputs[FormulaVariable.nyquist.slot] = clock.sampleRate / 2
        return program.node.activeCase(inputs: inputs)
    }
}

/// Current values of a voice for the read-out under the graph.
struct VoiceReadout: Identifiable, Sendable {
    var id: UUID
    var name: String
    var color: VoiceColor
    var frequency: Double?
    var pitchValue: Double?
    var gain: Double?
    var eventIndex: Int?
    var note: Double?
}

enum SynthAnalysis {
    /// Builds all lanes for the visible voices.
    static func graph(_ compilation: SynthCompilation, baseSamples: Int = 600) -> SynthGraphData {
        let project = compilation.project
        let mapping = compilation.xMapping
        let xRange = mapping.range
        var lanes: [GraphLane] = []
        var pitchCurves: [PitchUnit: [LaneCurve]] = [:]
        var frequencyCurves: [LaneCurve] = []
        var amplitudeCurves: [LaneCurve] = []
        var events: [UUID: [NoteEvent]] = [:]
        var order: [(id: UUID, name: String, color: VoiceColor)] = []
        var limited: [UUID: Double] = [:]
        var risers: [UUID: RiserDisplay] = [:]
        let options = GraphSampler.Options(baseSamples: baseSamples, maximumDepth: 8, maximumExtraPoints: 6_000)

        for compiled in compilation.voices where compiled.voice.isVisible {
            let voice = compiled.voice
            let probe = VoiceProbe(compiled: compiled, compilation: compilation)
            events[voice.id] = probe.schedule.events
            order.append((voice.id, voice.name, voice.color))
            if probe.schedule.rateLimited, let beat = probe.schedule.limitedFromBeat {
                limited[voice.id] = beat
            }
            func frame(_ x: Double) -> Int {
                Int(min(max(mapping.frame(atX: x), 0), Double(compilation.clock.totalFrames - 1)).rounded(.down))
            }
            if voice.source.kind == .riser {
                risers[voice.id] = RiserDisplay(partials: min(max(voice.source.riserPartials, 2), 10), lowest: voice.source.riserLowestFrequency,
                                                cycleBeats: voice.source.riserCycleBeats, rising: voice.source.riserRising, color: voice.color)
                lanes.append(GraphLane(id: "riser-\(voice.id)", kind: .riser(voice.id), title: "\(voice.name): Teiltöne",
                                       unitLabel: "Hz", curves: [], yRange: 0...Double(max(2, voice.source.riserPartials))))
            } else if compiled.pitch != nil, voice.source.kind != .directSignal {
                switch project.laneLayout {
                case .byUnit:
                    let curve = GraphSampler.sample({ probe.pitchValue(atFrame: frame($0)) }, over: xRange, options: options)
                    pitchCurves[voice.pitch.unit, default: []].append(
                        LaneCurve(id: "pitch-\(voice.id)", voiceID: voice.id, name: voice.name, color: voice.color, curve: curve, isDisplayOnly: false))
                case .sharedFrequency:
                    let curve = GraphSampler.sample({ probe.frequency(atFrame: frame($0)).map(log2) ?? .nan }, over: xRange, options: options)
                    frequencyCurves.append(LaneCurve(id: "frequency-\(voice.id)", voiceID: voice.id, name: voice.name, color: voice.color,
                                                     curve: curve, isDisplayOnly: false))
                }
            }
            if compiled.amplitude != nil {
                let curve = GraphSampler.sample({ probe.gain(atFrame: frame($0)) }, over: xRange, options: options)
                amplitudeCurves.append(LaneCurve(id: "gain-\(voice.id)", voiceID: voice.id, name: voice.name, color: voice.color,
                                                 curve: curve, isDisplayOnly: false))
            }
        }

        // Display-only curves.
        var displayLanes: [DisplayCurve.Unit: [LaneCurve]] = [:]
        for display in compilation.displayCurves where display.curve.unit != .signal {
            let program = display.program
            let buffer = EvaluationBuffer(capacity: program.slotCount)
            let voiceProbe = display.curve.voiceID.flatMap { id in compilation.voice(id) }.map { VoiceProbe(compiled: $0, compilation: compilation) }
            let curve = GraphSampler.sample({ x in
                let frame = Int(min(max(mapping.frame(atX: x), 0), Double(compilation.clock.totalFrames - 1)))
                VoiceInputs.set(buffer, frame: frame, event: voiceProbe?.event(atFrame: frame), clock: compilation.clock, xMapping: mapping)
                return buffer.evaluate(program)
            }, over: xRange, options: options)
            let lane = LaneCurve(id: "display-\(display.curve.id)", voiceID: nil, name: display.curve.name, color: display.curve.color,
                                 curve: curve, isDisplayOnly: true)
            switch display.curve.unit {
            case .gain: amplitudeCurves.append(lane)
            case .hertz where project.laneLayout == .byUnit: pitchCurves[.hertz, default: []].append(lane)
            case .semitones where project.laneLayout == .byUnit: pitchCurves[.semitones, default: []].append(lane)
            case .octaves where project.laneLayout == .byUnit: pitchCurves[.octaves, default: []].append(lane)
            default: displayLanes[display.curve.unit, default: []].append(lane)
            }
        }

        for unit in PitchUnit.allCases {
            guard let curves = pitchCurves[unit], !curves.isEmpty else { continue }
            lanes.insert(GraphLane(id: "pitch-\(unit.rawValue)", kind: .pitch(unit), title: "Tonhöhe (\(unit.title))",
                                   unitLabel: unit.axisLabel, curves: curves, yRange: yRange(curves)), at: 0)
        }
        if !frequencyCurves.isEmpty {
            lanes.insert(GraphLane(id: "frequency", kind: .frequency, title: "Tonhöhe (Hz, logarithmisch)", unitLabel: "Hz",
                                   curves: frequencyCurves, yRange: yRange(frequencyCurves)), at: 0)
        }
        if !amplitudeCurves.isEmpty {
            let range = yRange(amplitudeCurves)
            lanes.append(GraphLane(id: "amplitude", kind: .amplitude, title: "Amplitude (linear)", unitLabel: "×",
                                   curves: amplitudeCurves, yRange: min(0, range.lowerBound)...max(1, range.upperBound)))
        }
        for (unit, curves) in displayLanes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lanes.append(GraphLane(id: "display-\(unit.rawValue)", kind: .display(unit), title: "Anzeige (\(unit.title))",
                                   unitLabel: unit.title, curves: curves, yRange: yRange(curves)))
        }
        if events.values.contains(where: { $0.count > 1 }) {
            lanes.append(GraphLane(id: "events", kind: .events, title: "Ereignisse", unitLabel: "", curves: [],
                                   yRange: 0...Double(max(1, order.count))))
        }
        return SynthGraphData(lanes: lanes, xRange: xRange, mapping: mapping, voiceEvents: events, voiceOrder: order,
                              rateLimited: limited, riserSettings: risers)
    }

    private static func yRange(_ curves: [LaneCurve]) -> ClosedRange<Double> {
        var low = Double.infinity
        var high = -Double.infinity
        for curve in curves {
            if let range = curve.curve.robustYRange ?? curve.curve.finiteYRange {
                low = min(low, range.lowerBound)
                high = max(high, range.upperBound)
            }
        }
        guard low.isFinite, high.isFinite else { return -1...1 }
        if high - low < 1e-9 {
            return (low - 1)...(high + 1)
        }
        let margin = (high - low) * 0.08
        return (low - margin)...(high + margin)
    }

    /// Current values of all visible voices at a frame.
    static func readout(_ compilation: SynthCompilation, probes: [VoiceProbe], frame: Int) -> [VoiceReadout] {
        probes.map { probe in
            let voice = probe.compiled.voice
            let event = probe.event(atFrame: frame)
            let pitch = probe.compiled.pitch == nil ? nil : probe.pitchValue(atFrame: frame)
            return VoiceReadout(id: voice.id, name: voice.name, color: voice.color,
                                frequency: probe.frequency(atFrame: frame),
                                pitchValue: pitch.flatMap { $0.isFinite ? $0 : nil },
                                gain: { let g = probe.gain(atFrame: frame); return g.isFinite ? g : nil }(),
                                eventIndex: event?.index, note: event?.note)
        }
    }

    /// Current value of a parameter (constant or switched per beat / bar).
    static func value(of parameter: SynthParameter, position: MusicalPosition) -> Double {
        switch parameter.mode {
        case .constant: return parameter.value
        case .perBar, .perBeat:
            let values = parameter.values.isEmpty ? [parameter.value] : parameter.values
            let counter = parameter.mode == .perBar ? position.bar : floor(position.beat)
            let index = Int(MathSemantics.modulo(counter, Double(values.count)))
            return values[min(max(index, 0), values.count - 1)]
        }
    }
}

extension FormulaNode {
    /// Index of the active case of the first case distinction (if/piecewise) at the top of the
    /// tree (through bindings and arithmetic, not inside sums): 0 = first case, the last index
    /// is the "sonst" case. nil if there is none or its condition is undefined.
    func activeCase(inputs: [Double]) -> Int? {
        var locals = [Double](repeating: 0, count: localCount)
        return findActiveCase(inputs: inputs, locals: &locals)
    }

    private func findActiveCase(inputs: [Double], locals: inout [Double]) -> Int? {
        func value(_ node: FormulaNode) -> Double {
            // Evaluate a sub-tree with the current locals (bindings above are already set).
            var wrapped = node
            for (slot, value) in locals.enumerated().reversed() {
                wrapped = .binding(local: slot, value: .number(value), body: wrapped)
            }
            return wrapped.evaluate(inputs: inputs)
        }
        switch self {
        case .binding(let slot, let bound, let body):
            locals[slot] = value(bound)
            return body.findActiveCase(inputs: inputs, locals: &locals)
        case .conditional(let condition, _, _):
            let c = value(condition)
            if c.isNaN { return nil }
            return c != 0 ? 0 : 1
        case .piecewise(let parts):
            var position = 0
            while position + 1 < parts.count {
                let c = value(parts[position])
                if c.isNaN { return nil }
                if c != 0 { return position / 2 }
                position += 2
            }
            return parts.count / 2
        case .negate(let operand), .not(let operand):
            return operand.findActiveCase(inputs: inputs, locals: &locals)
        case .binary(_, let lhs, let rhs):
            return lhs.findActiveCase(inputs: inputs, locals: &locals) ?? rhs.findActiveCase(inputs: inputs, locals: &locals)
        case .call(_, let arguments):
            for argument in arguments {
                if let found = argument.findActiveCase(inputs: inputs, locals: &locals) { return found }
            }
            return nil
        default:
            return nil
        }
    }
}
