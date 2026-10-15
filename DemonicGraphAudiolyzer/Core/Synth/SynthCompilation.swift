import Foundation

/// Where a formula of the synthesizer lives (to show errors in the right editor).
enum SynthField: Hashable, Sendable {
    case projectParameters
    case projectDefinitions
    case voiceParameters
    case voiceDefinitions
    case pitch
    case amplitude
    case signal
    case rate
    case display(UUID)

    var title: String {
        switch self {
        case .projectParameters: return "Projekt-Parameter"
        case .projectDefinitions: return "Projekt-Definitionen"
        case .voiceParameters: return "Parameter"
        case .voiceDefinitions: return "Definitionen"
        case .pitch: return "Tonhöhe"
        case .amplitude: return "Amplitude"
        case .signal: return "Audiosignal"
        case .rate: return "Wiederholrate"
        case .display: return "Anzeigekurve"
        }
    }
}

struct SynthIssue: Equatable, Sendable {
    var voiceID: UUID?
    var field: SynthField
    var error: FormulaError

    var message: String {
        error.localizedSummary
    }
}

/// A compiled role formula with its syntax (for the readable notation and active branches).
struct CompiledRole: Sendable {
    let program: CompiledProgram
    let syntax: SyntaxProgram
}

struct CompiledVoice: Sendable {
    let voice: SynthVoice
    let pitch: CompiledRole?
    let amplitude: CompiledRole?
    let signal: CompiledRole?
    let rate: CompiledRole?
    let autoParameters: [String]
    let warnings: [FormulaWarning]
    /// Largest environment needed by the programs.
    let slotCount: Int

    var isValid: Bool {
        (pitch != nil || !voice.source.kind.usesPitch || voice.source.kind == .riser) && amplitude != nil
            && (signal != nil || !voice.source.kind.usesSignalFormula)
            && (rate != nil || voice.trigger.kind != .rate)
    }
}

struct CompiledDisplayCurve: Sendable {
    let curve: DisplayCurve
    let program: CompiledProgram
}

/// Parses, binds and compiles all formulas of a project and plans the events of all voices.
/// Used by the renderer (preview and export) and by the graphs.
struct SynthCompilation: Sendable {
    let project: SynthProject
    let sampleRate: Double
    let clock: MusicalClock
    let xMapping: XMappingFunction
    let voices: [CompiledVoice]
    let schedules: [UUID: VoiceSchedule]
    let displayCurves: [CompiledDisplayCurve]
    let issues: [SynthIssue]

    /// Variables that are constant during a pass.
    static let fixedVariables: Set<FormulaVariable> = [.bpm, .beatsPerBar, .baseFrequency, .nyquist]

    init(project: SynthProject, sampleRate: Double) {
        var project = project
        project.tempo = project.tempo.clamped()
        self.project = project
        self.sampleRate = sampleRate
        let clock = MusicalClock(tempo: project.tempo, sampleRate: sampleRate)
        self.clock = clock
        self.xMapping = XMappingFunction(project: project, clock: clock)

        var issues: [SynthIssue] = []
        var compiledVoices: [CompiledVoice] = []
        var schedules: [UUID: VoiceSchedule] = [:]

        // Project-wide sources.
        let projectSources = Self.prepareSources(
            [(text: project.parameters.map(\.definitionLine).joined(separator: "\n"), field: SynthField.projectParameters),
             (text: project.definitions, field: .projectDefinitions)],
            voiceID: nil, external: [:], issues: &issues)

        for voice in project.voices.prefix(SynthProject.maximumVoices) {
            let voiceSources = Self.prepareSources(
                [(text: voice.parameters.map(\.definitionLine).joined(separator: "\n"), field: .voiceParameters),
                 (text: voice.definitions, field: .voiceDefinitions)],
                voiceID: voice.id, external: projectSources.shapes, issues: &issues)
            let prelude = projectSources.programs + voiceSources.programs
            var shapes = projectSources.shapes
            shapes.merge(voiceSources.shapes) { first, _ in first }
            let preludeFailed = projectSources.failed || voiceSources.failed
            let fixed: [FormulaVariable: Double] = [
                .bpm: project.tempo.bpm, .beatsPerBar: Double(project.tempo.beatsPerBar),
                .baseFrequency: voice.pitch.baseFrequency, .nyquist: sampleRate / 2
            ]
            var autoParameters: [String] = []
            var warnings: [FormulaWarning] = []

            func role(_ text: String, field: SynthField, needed: Bool) -> CompiledRole? {
                guard needed, !preludeFailed else { return nil }
                var environment = FormulaEnvironment(context: .synth)
                environment.externalDefinitions = shapes
                environment.allowAutoParameters = !voice.useAdvancedEditor
                environment.sourceName = nil
                do {
                    let syntax = try FormulaParser.parseProgram(text, environment: environment)
                    let bound = try FormulaBinder.bind(main: FormulaSourceProgram(program: syntax, sourceName: nil), prelude: prelude,
                                                       environment: environment, fixedVariables: Self.fixedVariables)
                    for name in bound.autoParameters where !autoParameters.contains(name) { autoParameters.append(name) }
                    warnings += syntax.warnings
                    return CompiledRole(program: CompiledProgram(bound.root, fixed: fixed), syntax: syntax)
                } catch let error as FormulaError {
                    issues.append(SynthIssue(voiceID: voice.id, field: field, error: error))
                    return nil
                } catch {
                    return nil
                }
            }

            let kind = voice.source.kind
            let pitch = role(voice.pitch.formula, field: .pitch, needed: kind.usesPitch && kind != .riser)
            let amplitude = role(voice.amplitude.formula, field: .amplitude, needed: true)
            let signal = role(voice.source.signalFormula, field: .signal, needed: kind.usesSignalFormula)
            let rate = role(voice.trigger.rateFormula, field: .rate, needed: voice.trigger.kind == .rate)
            let slots = [pitch, amplitude, signal, rate].compactMap { $0?.program.slotCount }.max() ?? CompiledProgram.localBase + 1
            let compiled = CompiledVoice(voice: voice, pitch: pitch, amplitude: amplitude, signal: signal, rate: rate,
                                         autoParameters: autoParameters, warnings: warnings, slotCount: slots)
            compiledVoices.append(compiled)

            // Events (the rate trigger integrates its compiled rate formula).
            var rateFunction: ((Int) -> Double)?
            if let rate {
                let buffer = EvaluationBuffer(capacity: rate.program.slotCount)
                let mapping = XMappingFunction(project: project, clock: clock)
                rateFunction = { frame in
                    VoiceInputs.set(buffer, frame: frame, event: nil, clock: clock, xMapping: mapping)
                    return buffer.evaluate(rate.program)
                }
            }
            schedules[voice.id] = EventScheduler.schedule(voice, clock: clock, rate: rateFunction)
        }

        // Display-only curves.
        var curves: [CompiledDisplayCurve] = []
        for curve in project.displayCurves {
            var prelude = projectSources.programs
            var shapes = projectSources.shapes
            var baseFrequency = 110.0
            if let voiceID = curve.voiceID, let voice = project.voices.first(where: { $0.id == voiceID }) {
                var throwaway: [SynthIssue] = []
                let sources = Self.prepareSources(
                    [(text: voice.parameters.map(\.definitionLine).joined(separator: "\n"), field: .voiceParameters),
                     (text: voice.definitions, field: .voiceDefinitions)],
                    voiceID: voice.id, external: shapes, issues: &throwaway)
                prelude += sources.programs
                shapes.merge(sources.shapes) { first, _ in first }
                baseFrequency = voice.pitch.baseFrequency
            }
            var environment = FormulaEnvironment(context: .synth)
            environment.externalDefinitions = shapes
            do {
                let syntax = try FormulaParser.parseProgram(curve.formula, environment: environment)
                let bound = try FormulaBinder.bind(main: FormulaSourceProgram(program: syntax, sourceName: nil), prelude: prelude,
                                                   environment: environment, fixedVariables: Self.fixedVariables)
                let fixed: [FormulaVariable: Double] = [.bpm: project.tempo.bpm, .beatsPerBar: Double(project.tempo.beatsPerBar),
                                                        .baseFrequency: baseFrequency, .nyquist: sampleRate / 2]
                curves.append(CompiledDisplayCurve(curve: curve, program: CompiledProgram(bound.root, fixed: fixed)))
            } catch let error as FormulaError {
                issues.append(SynthIssue(voiceID: nil, field: .display(curve.id), error: error))
            } catch {}
        }

        self.voices = compiledVoices
        self.schedules = schedules
        self.displayCurves = curves
        self.issues = issues
    }

    /// Parses definition sources in order; later sources see the earlier ones.
    private static func prepareSources(_ sources: [(text: String, field: SynthField)], voiceID: UUID?,
                                       external: [String: DefinitionShape], issues: inout [SynthIssue])
        -> (programs: [FormulaSourceProgram], shapes: [String: DefinitionShape], failed: Bool) {
        var programs: [FormulaSourceProgram] = []
        var shapes = external
        var failed = false
        for source in sources where !source.text.trimmed.isEmpty {
            var environment = FormulaEnvironment(context: .synth)
            environment.externalDefinitions = shapes
            environment.requiresOutput = false
            environment.sourceName = source.field.title
            do {
                let program = try FormulaParser.parseProgram(source.text, environment: environment)
                let sourceProgram = FormulaSourceProgram(program: program, sourceName: source.field.title)
                try FormulaBinder.check(sourceProgram, prelude: programs, environment: environment)
                programs.append(sourceProgram)
                for statement in program.definitions {
                    guard let name = statement.definedName else { continue }
                    if case .function(_, let parameters) = statement.kind {
                        shapes[name] = .function(arity: parameters.count)
                    } else {
                        shapes[name] = statement.isList ? .list : .value
                    }
                }
            } catch let error as FormulaError {
                issues.append(SynthIssue(voiceID: voiceID, field: source.field, error: error))
                failed = true
            } catch {
                failed = true
            }
        }
        return (programs, shapes, failed)
    }

    func voice(_ id: UUID) -> CompiledVoice? {
        voices.first { $0.voice.id == id }
    }

    func issues(for voiceID: UUID?, field: SynthField) -> [SynthIssue] {
        issues.filter { $0.voiceID == voiceID && $0.field == field }
    }

    /// First blocking problem for playback (an audible voice with an error, or the length limit).
    var blockingIssue: String? {
        if let issue = project.tempo.validationIssue { return issue }
        if project.voices.isEmpty { return "Das Projekt hat keine Stimme." }
        let audible = Set(project.audibleVoices.map(\.id))
        let blocking = issues.first { issue in
            if case .display = issue.field { return false }
            guard let id = issue.voiceID else { return true }
            return audible.contains(id)
        }
        if let issue = blocking {
            let voiceName = issue.voiceID.flatMap { id in project.voices.first { $0.id == id }?.name }
            let prefix = voiceName.map { "„\($0)“ – \(issue.field.title): " } ?? "\(issue.field.title): "
            return prefix + issue.error.localizedSummary
        }
        return nil
    }
}

/// Sets the input variables of a voice evaluation for a frame and the active event.
enum VoiceInputs {
    @inline(__always)
    static func set(_ buffer: EvaluationBuffer, frame: Int, event: NoteEvent?, clock: MusicalClock, xMapping: XMappingFunction) {
        set(buffer, frame: Double(frame), eventFrame: event.map { Double($0.frame) }, event: event, clock: clock, xMapping: xMapping)
    }

    @inline(__always)
    static func set(_ buffer: EvaluationBuffer, frame: Double, eventFrame: Double?, event: NoteEvent?, clock: MusicalClock, xMapping: XMappingFunction) {
        let pointer = buffer.pointer
        let time = frame / clock.sampleRate
        let beat = frame / clock.framesPerBeat
        let perBar = Double(clock.tempo.beatsPerBar)
        let bar = (beat / perBar).rounded(.down)
        pointer[FormulaVariable.t.slot] = time
        pointer[FormulaVariable.beat.slot] = beat
        pointer[FormulaVariable.bar.slot] = bar
        pointer[FormulaVariable.beatInBar.slot] = beat - bar * perBar
        pointer[FormulaVariable.x.slot] = xMapping.x(atFrame: frame)
        let local = frame - (eventFrame ?? 0)
        pointer[FormulaVariable.localTime.slot] = local / clock.sampleRate
        pointer[FormulaVariable.localBeat.slot] = local / clock.framesPerBeat
        pointer[FormulaVariable.n.slot] = Double(event?.index ?? 0)
        pointer[FormulaVariable.note.slot] = event?.note ?? 0
        pointer[FormulaVariable.velocity.slot] = event?.velocity ?? 1
    }
}
