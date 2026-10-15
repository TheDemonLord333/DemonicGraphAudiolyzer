import AVFoundation
import Foundation
import Observation
import SwiftUI

/// What the graph shows about the running pass (nil while idle → full curve).
struct PlaybackSnapshot: Equatable {
    var mode: SoundMode
    /// Audible frame of the pass (audio clock).
    var frame: Double
    var time: Double
    var duration: Double
    var progress: Double
    /// Read-out of the classic modes (synthesizer: time only).
    var readout: PlaybackReadout
    var isPaused: Bool
}

/// Central state of the instrument (MainActor). Owns the classic formula, the synthesizer and
/// pendulum projects, the graph view, the transport state machine and the audio engine. Heavy
/// work (sampling, compiling, rendering) runs in detached tasks; outdated results are
/// discarded via generation counters.
@MainActor
@Observable
final class AudiolyzerModel {
    // MARK: Classic formula

    var formulaText: String {
        didSet {
            guard formulaText != oldValue else { return }
            formulaDidChange()
        }
    }
    private(set) var parsedFormula: ParsedFormula?
    private(set) var formulaError: FormulaError?

    var parameters: FormulaParameters {
        didSet {
            guard parameters != oldValue else { return }
            soundConfigurationDidChange(affectsGraph: true)
        }
    }

    var settings: SoundSettings {
        didSet {
            guard settings != oldValue else { return }
            soundConfigurationDidChange(affectsGraph: false)
            if settings.mode != oldValue.mode {
                modeDidChange(from: oldValue.mode)
            }
        }
    }

    /// Playback volume (0 … 1). Only affects the preview, never the exported file.
    var volume: Double {
        didSet {
            playback.volume = Float(volume)
            scheduleSessionSave()
        }
    }

    var isLooping: Bool {
        didSet {
            guard isLooping != oldValue else { return }
            playback.setLooping(isLooping)
            scheduleSessionSave()
        }
    }

    /// Shows the waveform cursor in slow motion (clearly labelled as such).
    var slowMotionWaveform: Bool {
        didSet { scheduleSessionSave() }
    }

    /// Simple (single line) or advanced (multi-line) editor of the classic formula.
    var classicAdvancedEditor: Bool = false

    // MARK: Synthesizer and pendulum

    var synthProject: SynthProject {
        didSet {
            guard synthProject != oldValue else { return }
            if settings.mode == .synthesizer { projectDidChange() }
        }
    }

    var pendulumProject: SynthProject {
        didSet {
            guard pendulumProject != oldValue else { return }
            if settings.mode == .pendulum { projectDidChange() }
        }
    }

    /// Compiled formulas, events and diagnostics of the active project (preview sample rate).
    private(set) var compilation: SynthCompilation?
    /// Lanes of the synthesizer graph.
    private(set) var synthGraph: SynthGraphData = .empty
    /// Probes for read-outs on the main thread (one per visible voice).
    @ObservationIgnored private(set) var probes: [VoiceProbe] = []
    @ObservationIgnored private var compileGeneration = 0
    @ObservationIgnored private var compileTask: Task<Void, Never>?

    /// Title and explanation of the loaded preset (shown under the graph).
    private(set) var presetTitle: String
    private(set) var presetSummary: String

    // MARK: Graph

    private(set) var viewport: GraphViewport
    private(set) var autoFitY: Bool
    private(set) var curve: SampledCurve = .empty
    /// Band-limited waveform of the waveform mode (computed in the background).
    private(set) var waveformTable: WaveformTable?
    /// Automatically determined pitch range of the graph mode (computed in the background).
    private(set) var automaticRange: PitchRange?
    @ObservationIgnored private var plotWidth: Double = 360
    @ObservationIgnored private var curveGeneration = 0
    @ObservationIgnored private var curveTask: Task<Void, Never>?
    @ObservationIgnored private var analysisGeneration = 0
    @ObservationIgnored private var analysisTask: Task<Void, Never>?

    // MARK: Transport

    private(set) var transport = TransportStateMachine()
    var phase: TransportPhase { transport.phase }
    private(set) var activePlan: ActivePlan?
    /// Per-voice signals of the rendered preview (audio snippet display).
    private(set) var activeStems: [UUID: [Int16]] = [:]
    /// The safety limiter acted in the rendered preview.
    private(set) var limiterEngaged = false
    private(set) var lastError: String?
    /// Increments on every start so views can restart animations.
    private(set) var runID = 0

    private let playback: AudioPlaybackEngine
    @ObservationIgnored private var prepareGeneration = 0
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var preparedJob: RenderJob?

    // MARK: Navigation

    /// Tab requested by an action (e.g. help button → "Anleitungen").
    var requestedTab: AppTab?
    /// Guide entry to show when the guide tab appears.
    var requestedGuideEntry: String?

    // MARK: Persistence

    private let sessionStore: SessionStateStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The last loaded or saved configuration (for "unsaved changes").
    @ObservationIgnored private var baseline: SoundPreset?

    /// Sample rate of the preview. Equal to the default export rate so that preview and
    /// export use bit-identical PCM; the engine converts to the hardware rate.
    static let previewSampleRate: Double = 44_100

    init(sessionStore: SessionStateStore = SessionStateStore(), defaults: PlaybackDefaults = .load()) {
        self.sessionStore = sessionStore
        self.playback = AudioPlaybackEngine()
        let restored = sessionStore.load()
        let preset: SoundPreset
        if let restored {
            preset = restored.preset
        } else {
            var initial = BuiltInPresets.gentleWave
            initial.settings.duration = defaults.duration
            initial.settings.levelDecibels = defaults.levelDecibels
            preset = initial
        }
        formulaText = preset.settings.mode.isClassic ? preset.formula : (restored?.classicFormula ?? BuiltInPresets.gentleWave.formula)
        parameters = preset.parameters
        settings = preset.settings.clamped()
        volume = restored?.volume ?? defaults.volume
        isLooping = restored?.isLooping ?? defaults.isLooping
        slowMotionWaveform = restored?.slowMotionWaveform ?? false
        viewport = restored?.viewport ?? GraphViewport(xMin: preset.settings.playXMin, xMax: preset.settings.playXMax, yMin: -1.5, yMax: 1.5)
        autoFitY = restored?.autoFitY ?? true
        synthProject = (preset.settings.mode == .synthesizer ? preset.project : nil) ?? restored?.synthProject ?? Self.starterProject
        pendulumProject = (preset.settings.mode == .pendulum ? preset.project : nil) ?? restored?.pendulumProject
            ?? SynthPresets.pendulums.project ?? SynthProject()
        presetTitle = preset.name
        presetSummary = preset.summary
        classicAdvancedEditor = preset.formula.contains("\n")
        if !viewport.isValid { viewport = .standard }

        playback.volume = Float(volume)
        playback.onFinished = { [weak self] in self?.playbackFinished() }
        playback.onInterrupted = { [weak self] _ in self?.playbackInterrupted() }

        reparseFormula()
        scheduleCurveUpdate()
        scheduleAnalysis()
        scheduleCompilation()
        baseline = currentPreset()
    }

    /// First project of the synthesizer: a simple plucked voice with explicit roles.
    static var starterProject: SynthProject {
        var voice = SynthVoice(name: "Stimme 1", color: .green)
        voice.source.waveform = .triangle
        voice.trigger.kind = .pattern
        voice.trigger.pattern = "x.x.x.xx"
        voice.trigger.stepBeats = 0.5
        voice.definitions = "notes = [0, 3, 7, 10]"
        voice.pitch = PitchControl(formula: "notes[mod(n, len(notes))]", unit: .semitones, baseFrequency: 220)
        voice.amplitude = AmplitudeControl(formula: "exp(-4*localTime)")
        voice.summary = "Startstimme: Notenliste über den Triggerzähler n, abklingende Hüllkurve."
        return SynthProject(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2), voices: [voice])
    }

    // MARK: - Modes

    var mode: SoundMode { settings.mode }

    var isSynthMode: Bool { !settings.mode.isClassic }

    /// The project of the active synthesizer mode.
    var project: SynthProject {
        get { settings.mode == .pendulum ? pendulumProject : synthProject }
        set {
            if settings.mode == .pendulum {
                pendulumProject = newValue
            } else {
                synthProject = newValue
            }
        }
    }

    func setMode(_ newMode: SoundMode) {
        guard newMode != settings.mode else { return }
        settings.mode = newMode
    }

    private func modeDidChange(from oldMode: SoundMode) {
        if settings.mode.isClassic {
            resetView()
        } else {
            projectDidChange()
        }
        if oldMode.isClassic != settings.mode.isClassic || !settings.mode.isClassic {
            presetTitle = settings.mode.isClassic ? "f(x) = \(formulaDisplayBody)" : settings.mode.title
            presetSummary = settings.mode.explanation
        }
    }

    // MARK: - Classic formula handling

    private func formulaDidChange() {
        // Stop first: an invalid formula must not leave a running pass behind.
        stopForConfigurationChange()
        reparseFormula()
        scheduleCurveUpdate()
        scheduleAnalysis()
        scheduleSessionSave()
    }

    private func reparseFormula() {
        switch ParsedFormula.parse(formulaText) {
        case .success(let formula):
            parsedFormula = formula
            formulaError = nil
            if settings.mode.isClassic { transport.handle(.formulaBecameValid) }
        case .failure(let error):
            parsedFormula = nil
            formulaError = error
            if settings.mode.isClassic { transport.handle(.formulaBecameInvalid) }
        }
    }

    private func soundConfigurationDidChange(affectsGraph: Bool) {
        stopForConfigurationChange()
        if affectsGraph { scheduleCurveUpdate() }
        scheduleAnalysis()
        scheduleSessionSave()
        updateTransportValidity()
    }

    /// Formula or sound changes end the running pass; the next start builds a new configuration.
    private func stopForConfigurationChange() {
        prepareGeneration += 1
        prepareTask?.cancel()
        if transport.phase.isActive {
            playback.stop()
            transport.handle(.configurationChanged)
        }
        activePlan = nil
        preparedJob = nil
    }

    /// Classic: the formula decides; synthesizer: an audible voice with an error blocks.
    private func updateTransportValidity() {
        let valid: Bool
        if settings.mode.isClassic {
            valid = parsedFormula != nil
        } else {
            valid = compilation?.blockingIssue == nil
        }
        transport.handle(valid ? .formulaBecameValid : .formulaBecameInvalid)
    }

    /// Parameters a, b, c that appear in the formula.
    var usedParameters: [FormulaVariable] {
        guard let parsedFormula else { return [] }
        return [FormulaVariable.a, .b, .c].filter { parsedFormula.usedParameters.contains($0) }
    }

    /// "sin(x)" for "y = sin(x)".
    var formulaDisplayBody: String {
        parsedFormula?.displayBody ?? formulaText
    }

    // MARK: - Graph view (classic)

    func updatePlotWidth(_ width: Double) {
        guard width > 0, abs(width - plotWidth) > 20 else { return }
        plotWidth = width
        scheduleCurveUpdate()
    }

    func setAutoFitY(_ enabled: Bool) {
        autoFitY = enabled
        if enabled { applyAutoFit() }
        scheduleCurveUpdate()
        scheduleSessionSave()
    }

    /// Zoom by `scale` (> 1 zooms in) around an anchor in data coordinates.
    func zoom(scale: Double, anchorX: Double, anchorY: Double, from base: GraphViewport) {
        let yScale = autoFitY ? 1 : scale
        let zoomed = base.zoomed(xScale: scale, yScale: yScale, anchorX: anchorX, anchorY: anchorY)
        setViewport(zoomed)
    }

    func pan(dxData: Double, dyData: Double, from base: GraphViewport) {
        let moved = base.panned(dx: dxData, dy: autoFitY ? 0 : dyData)
        setViewport(moved)
    }

    func resetView() {
        let x: (Double, Double)
        if settings.mode == .waveform {
            let width = settings.sectionEnd - settings.sectionStart
            x = (settings.sectionStart - width * 0.25, settings.sectionEnd + width * 0.25)
        } else {
            x = (settings.playXMin, settings.playXMax)
        }
        autoFitY = true
        setViewport(GraphViewport(xMin: x.0, xMax: x.1, yMin: viewport.yMin, yMax: viewport.yMax))
        applyAutoFit()
        scheduleSessionSave()
    }

    /// Uses the visible x range as the played range.
    func adoptVisibleRangeForPlayback() {
        settings.playXMin = viewport.xMin
        settings.playXMax = viewport.xMax
    }

    private func setViewport(_ newValue: GraphViewport) {
        guard newValue.isValid else { return }
        viewport = newValue
        if autoFitY { applyAutoFit() }
        scheduleCurveUpdate()
        scheduleSessionSave()
    }

    private func applyAutoFit() {
        guard curve.pointCount > 0 else { return }
        let range = GraphViewport.fittedYRange(for: visiblePart(of: curve))
        viewport = viewport.withYRange(range)
    }

    /// Restricts a sampled curve to the visible x range (for fitting).
    private func visiblePart(of curve: SampledCurve) -> SampledCurve {
        let values = curve.segments.flatMap { $0.points }.filter { $0.x >= viewport.xMin && $0.x <= viewport.xMax && $0.y.isFinite }.map(\.y)
        var part = curve
        part.finiteYRange = values.isEmpty ? nil : (values.min()!...values.max()!)
        part.robustYRange = RobustRange.estimate(values)
        return part
    }

    private func scheduleCurveUpdate() {
        curveGeneration += 1
        let generation = curveGeneration
        curveTask?.cancel()
        guard let formula = parsedFormula else {
            curve = .empty
            return
        }
        let compiled = formula.compiled(parameters: parameters)
        let margin = viewport.width * 0.1
        let range = (viewport.xMin - margin)...(viewport.xMax + margin)
        let visibleY: ClosedRange<Double>? = autoFitY ? nil : (viewport.yMin...viewport.yMax)
        let samples = Int(min(2_400, max(400, plotWidth * 2.4)))
        curveTask = Task.detached(priority: .userInitiated) { [weak self] in
            let sampled = GraphSampler.sample({ compiled($0) }, over: range,
                                              options: GraphSampler.Options(baseSamples: samples, visibleYRange: visibleY))
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.curveGeneration == generation else { return }
                self.curve = sampled
                if self.autoFitY { self.applyAutoFit() }
            }
        }
    }

    // MARK: - Synthesizer project

    /// Changes the active project (stops a running pass, recompiles, saves the session).
    func updateProject(_ change: (inout SynthProject) -> Void) {
        var copy = project
        change(&copy)
        project = copy
    }

    func updateVoice(_ id: UUID, _ change: (inout SynthVoice) -> Void) {
        updateProject { project in
            guard let index = project.voices.firstIndex(where: { $0.id == id }) else { return }
            change(&project.voices[index])
        }
    }

    func voice(_ id: UUID) -> SynthVoice? {
        project.voices.first { $0.id == id }
    }

    var canAddVoice: Bool { project.voices.count < SynthProject.maximumVoices }

    func addVoice() {
        guard canAddVoice else { return }
        var voice = Self.starterProject.voices[0]
        voice.id = UUID()
        voice.name = "Stimme \(project.voices.count + 1)"
        let used = Set(project.voices.map(\.color))
        voice.color = VoiceColor.allCases.first { !used.contains($0) } ?? .green
        updateProject { $0.voices.append(voice) }
    }

    func duplicateVoice(_ id: UUID) {
        guard canAddVoice, var copy = voice(id) else { return }
        copy.id = UUID()
        copy.name += " (Kopie)"
        copy.isSolo = false
        updateProject { project in
            let index = project.voices.firstIndex { $0.id == id } ?? project.voices.count - 1
            project.voices.insert(copy, at: index + 1)
        }
    }

    func removeVoice(_ id: UUID) {
        updateProject { project in
            project.voices.removeAll { $0.id == id }
            project.displayCurves.removeAll { $0.voiceID == id }
        }
    }

    func moveVoice(_ id: UUID, by offset: Int) {
        updateProject { project in
            guard let index = project.voices.firstIndex(where: { $0.id == id }) else { return }
            let target = min(max(index + offset, 0), project.voices.count - 1)
            guard target != index else { return }
            let voice = project.voices.remove(at: index)
            project.voices.insert(voice, at: target)
        }
    }

    /// Adds the voices of another preset (combinations such as "Kick Roll + Cowbell").
    /// Project-wide parameters and definitions of the source are copied into each voice.
    func importVoices(from preset: SoundPreset) {
        guard let source = preset.project else { return }
        var imported: [SynthVoice] = []
        for var voice in source.voices {
            guard project.voices.count + imported.count < SynthProject.maximumVoices else { break }
            voice.id = UUID()
            let ownNames = Set(voice.parameters.map(\.name))
            voice.parameters += source.parameters.filter { !ownNames.contains($0.name) }
            if !source.definitions.trimmed.isEmpty {
                voice.definitions = source.definitions + (voice.definitions.isEmpty ? "" : "\n" + voice.definitions)
            }
            imported.append(voice)
        }
        updateProject { $0.voices += imported }
    }

    private func projectDidChange() {
        stopForConfigurationChange()
        scheduleCompilation()
        scheduleSessionSave()
    }

    /// Compiles the active project and builds the graph lanes in the background.
    private func scheduleCompilation() {
        compileGeneration += 1
        let generation = compileGeneration
        compileTask?.cancel()
        guard isSynthMode else { return }
        let project = self.project
        let sampleRate = Self.previewSampleRate
        compileTask = Task.detached(priority: .userInitiated) { [weak self] in
            let compilation = SynthCompilation(project: project, sampleRate: sampleRate)
            if Task.isCancelled { return }
            let graph = SynthAnalysis.graph(compilation)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.compileGeneration == generation else { return }
                self.compilation = compilation
                self.synthGraph = graph
                self.probes = compilation.voices.filter { $0.voice.isVisible }.map { VoiceProbe(compiled: $0, compilation: compilation) }
                self.updateTransportValidity()
            }
        }
    }

    /// Errors of a field of a voice (or of the project when `voiceID` is nil).
    func issues(voiceID: UUID?, field: SynthField) -> [SynthIssue] {
        compilation?.issues(for: voiceID, field: field) ?? []
    }

    /// Current values of the visible voices at a frame (read-out under the graph).
    func synthReadout(atFrame frame: Double) -> [VoiceReadout] {
        guard let compilation else { return [] }
        let clamped = Int(min(max(frame, 0), Double(compilation.clock.totalFrames - 1)))
        return SynthAnalysis.readout(compilation, probes: probes, frame: clamped)
    }

    /// Active case of a role formula at the current playback position (nil while idle).
    func liveActiveCase(voiceID: UUID, role: SynthField) -> Int? {
        guard let snapshot = playbackSnapshot(), let compilation,
              let probe = probes.first(where: { $0.compiled.voice.id == voiceID }) else { return nil }
        let frame = Int(min(max(snapshot.frame, 0), Double(compilation.clock.totalFrames - 1)))
        return probe.activeCase(role: role, atFrame: frame)
    }

    /// Compiled state of a voice (automatically detected parameters, warnings).
    func compiledVoice(_ id: UUID) -> CompiledVoice? {
        compilation?.voice(id)
    }

    // MARK: - Transport

    /// The immutable job for preview and export.
    func makeRenderJob(sampleRate: Double = AudiolyzerModel.previewSampleRate, duration: Double? = nil) -> RenderJob? {
        if isSynthMode {
            return .synth(SynthRenderConfiguration(project: project, sampleRate: sampleRate))
        }
        guard let configuration = makeRenderConfiguration(sampleRate: sampleRate, duration: duration) else { return nil }
        return .classic(configuration)
    }

    /// The immutable configuration of the classic modes.
    func makeRenderConfiguration(sampleRate: Double = AudiolyzerModel.previewSampleRate, duration: Double? = nil) -> RenderConfiguration? {
        guard let parsedFormula else { return nil }
        var snapshot = settings
        if let duration { snapshot.duration = duration }
        return RenderConfiguration(formula: parsedFormula, parameters: parameters, settings: snapshot, sampleRate: sampleRate)
    }

    var settingsIssue: String? {
        if isSynthMode { return compilation?.blockingIssue }
        return settings.validationIssue
    }

    /// Whether the export is possible right now.
    var canExport: Bool {
        if isSynthMode { return compilation != nil && compilation?.blockingIssue == nil }
        return parsedFormula != nil
    }

    /// "Abspielen": starts the pass from the beginning.
    func play() {
        switch transport.phase {
        case .preparing, .exporting, .invalidFormula:
            return
        case .playing, .paused:
            restartFromBeginning()
            return
        case .ready, .failed:
            break
        }
        guard let job = makeRenderJob() else { return }
        if case .classic(let configuration) = job, let issue = configuration.settings.validationIssue {
            lastError = issue
            transport.handle(.fail(issue))
            return
        }
        guard transport.handle(.play) else { return }
        lastError = nil

        if let prepared = preparedJob, prepared == job, playback.buffer != nil, activePlan != nil {
            startPlayback(fromFrame: 0)
            return
        }

        prepareGeneration += 1
        let generation = prepareGeneration
        prepareTask?.cancel()
        prepareTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = PreviewRenderer.render(job: job)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.prepareGeneration == generation, self.transport.phase == .preparing else { return }
                switch result {
                case .success(let rendered):
                    self.activePlan = rendered.plan
                    self.activeStems = rendered.stems
                    self.limiterEngaged = rendered.limitedFrames > 0
                    self.preparedJob = job
                    self.playback.load(rendered.buffer)
                    self.startPlayback(fromFrame: 0)
                case .failure(let error):
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func restartFromBeginning() {
        guard activePlan != nil else { return }
        if transport.phase == .paused {
            transport.handle(.resume)
        }
        do {
            try playback.play(fromFrame: 0, looping: isLooping)
            runID += 1
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func startPlayback(fromFrame frame: Int) {
        do {
            try playback.play(fromFrame: frame, looping: isLooping)
            transport.handle(.prepared)
            runID += 1
        } catch {
            fail(error.localizedDescription)
        }
    }

    func pause() {
        guard transport.phase == .playing else { return }
        playback.pause()
        transport.handle(.pause)
    }

    func resume() {
        guard transport.phase == .paused else { return }
        do {
            try playback.play(fromFrame: playback.pausedFrame, looping: isLooping)
            transport.handle(.resume)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func togglePause() {
        if transport.phase == .playing {
            pause()
        } else if transport.phase == .paused {
            resume()
        }
    }

    /// Stops and resets to the beginning.
    func stop() {
        prepareGeneration += 1
        prepareTask?.cancel()
        playback.stop()
        if case .failed = transport.phase {
            lastError = nil
            transport.handle(.dismissError)
        } else {
            transport.handle(.stop)
        }
    }

    func dismissError() {
        lastError = nil
        transport.handle(.dismissError)
    }

    private func fail(_ message: String) {
        playback.stop()
        lastError = message
        transport.handle(.fail(message))
    }

    private func playbackFinished() {
        transport.handle(.finished)
    }

    private func playbackInterrupted() {
        if transport.phase == .playing {
            transport.handle(.pause)
        }
    }

    /// Pauses when the app leaves the foreground (no background audio in this version).
    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            if transport.phase == .playing {
                pause()
            }
            playback.suspend()
            saveSessionNow()
        case .inactive:
            saveSessionNow()
        default:
            break
        }
    }

    // MARK: - Export coordination

    /// Called by the export screen; stops the preview and blocks the transport.
    func beginExport() -> Bool {
        if transport.phase.isActive {
            prepareGeneration += 1
            prepareTask?.cancel()
            playback.stop()
            transport.handle(.stop)
        }
        return transport.handle(.exportStarted)
    }

    func endExport() {
        transport.handle(.exportEnded)
    }

    // MARK: - Playback position (audio clock)

    /// Current state for the graph, computed from the audio clock (call on every display frame).
    func playbackSnapshot() -> PlaybackSnapshot? {
        guard let plan = activePlan else { return nil }
        let isPaused: Bool
        switch transport.phase {
        case .playing: isPaused = false
        case .paused: isPaused = true
        default: return nil
        }
        guard let frame = playback.currentFrame() else { return nil }
        let time = frame / plan.sampleRate
        let duration = Double(plan.frameCount) / plan.sampleRate
        let progress = duration > 0 ? min(1, time / duration) : 0
        switch plan {
        case .classic(let soundPlan):
            return PlaybackSnapshot(mode: soundPlan.settings.mode, frame: frame, time: time, duration: duration, progress: progress,
                                    readout: soundPlan.readout(atTime: time), isPaused: isPaused)
        case .synth:
            return PlaybackSnapshot(mode: settings.mode, frame: frame, time: time, duration: duration, progress: progress,
                                    readout: PlaybackReadout(time: time, progress: progress, x: time, y: nil, frequency: nil),
                                    isPaused: isPaused)
        }
    }

    /// Recomputes the automatic pitch range (graph mode) or the band-limited waveform
    /// (waveform mode) in the background; outdated results are dropped.
    private func scheduleAnalysis() {
        analysisGeneration += 1
        let generation = analysisGeneration
        analysisTask?.cancel()
        guard let formula = parsedFormula, settings.mode.isClassic else {
            automaticRange = nil
            waveformTable = nil
            return
        }
        let compiled = formula.compiled(parameters: parameters)
        let snapshot = settings.clamped()
        let sampleRate = Self.previewSampleRate
        analysisTask = Task.detached(priority: .utility) { [weak self] in
            var range: PitchRange?
            var table: WaveformTable?
            switch snapshot.mode {
            case .graph:
                if snapshot.playXMax > snapshot.playXMin {
                    range = PitchMapper.automaticRange(for: compiled, xMin: snapshot.playXMin, xMax: snapshot.playXMax)
                }
            case .waveform:
                if snapshot.sectionEnd > snapshot.sectionStart {
                    table = SoundPlan.makeWaveformTable(function: compiled, start: snapshot.sectionStart,
                                                        end: snapshot.sectionEnd,
                                                        baseFrequency: snapshot.baseFrequency,
                                                        sampleRate: sampleRate)
                }
            case .synthesizer, .pendulum:
                break
            }
            if Task.isCancelled { return }
            let result = (range, table)
            await MainActor.run { [weak self] in
                guard let self, self.analysisGeneration == generation else { return }
                self.automaticRange = result.0
                self.waveformTable = result.1
            }
        }
    }

    // MARK: - Presets, guide and session

    func currentPreset(named name: String? = nil) -> SoundPreset {
        SoundPreset(name: name ?? presetTitle, summary: presetSummary, formula: settings.mode.isClassic ? formulaText : project.voices.first?.pitch.formula ?? formulaText,
                    parameters: parameters, settings: settings,
                    project: isSynthMode ? project : nil)
    }

    /// The working state differs from the last loaded or saved preset.
    var hasUnsavedChanges: Bool {
        guard let baseline else { return false }
        let current = currentPreset()
        if current.settings.mode != baseline.settings.mode { return true }
        if isSynthMode { return current.project != baseline.project }
        return current.formula != baseline.formula || current.parameters != baseline.parameters || current.settings != baseline.settings
    }

    /// Marks the current state as saved (after storing a preset).
    func markSaved(as name: String? = nil) {
        if let name { presetTitle = name }
        baseline = currentPreset()
    }

    func apply(_ preset: SoundPreset) {
        stopForConfigurationChange()
        if let project = preset.project, !preset.settings.mode.isClassic {
            if preset.settings.mode == .pendulum {
                pendulumProject = project
            } else {
                synthProject = project
            }
        } else {
            formulaText = preset.formula
            parameters = preset.parameters
            classicAdvancedEditor = preset.formula.contains("\n")
        }
        var newSettings = preset.settings.clamped()
        if !newSettings.mode.isClassic {
            // Keep the classic settings of the session; only the mode changes.
            var kept = settings
            kept.mode = newSettings.mode
            newSettings = kept
        }
        settings = newSettings
        presetTitle = preset.name
        presetSummary = preset.summary
        if settings.mode.isClassic {
            resetView()
        } else {
            scheduleCompilation()
        }
        baseline = currentPreset()
        scheduleSessionSave()
    }

    /// "Im Editor öffnen" from the guide (the view asks before replacing unsaved changes).
    func openInEditor(_ payload: EditorPayload) {
        guard let preset = payload.makePreset() else { return }
        apply(preset)
        requestedTab = .graph
    }

    /// Help button of an editor: shows the matching guide entry.
    func showGuide(topic: String?) {
        if let topic, let entry = GuideCatalog.entry(forHelpTopic: topic) {
            requestedGuideEntry = entry.id
        } else {
            requestedGuideEntry = nil
        }
        requestedTab = .guides
    }

    func applyPlaybackDefaults(_ defaults: PlaybackDefaults) {
        settings.duration = defaults.duration
        settings.levelDecibels = defaults.levelDecibels
        volume = defaults.volume
        isLooping = defaults.isLooping
    }

    private func scheduleSessionSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self?.saveSessionNow()
        }
    }

    func saveSessionNow() {
        let state = SessionState(preset: currentPreset(), viewport: viewport, autoFitY: autoFitY,
                                 volume: volume, isLooping: isLooping, slowMotionWaveform: slowMotionWaveform,
                                 synthProject: synthProject, pendulumProject: pendulumProject,
                                 classicFormula: formulaText)
        sessionStore.save(state)
    }
}
