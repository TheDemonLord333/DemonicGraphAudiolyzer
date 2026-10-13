import AVFoundation
import Foundation
import Observation
import SwiftUI

/// What the graph shows about the running pass (nil while idle → full curve).
struct PlaybackSnapshot: Equatable {
    var mode: SoundMode
    var time: Double
    var duration: Double
    var progress: Double
    var readout: PlaybackReadout
    var isPaused: Bool
}

/// Central state of the instrument (MainActor). Owns formula, graph view, sound settings,
/// transport state machine and the audio engine. Heavy work (sampling, rendering) runs in
/// detached tasks; outdated results are discarded via generation counters.
@MainActor
@Observable
final class AudiolyzerModel {
    // MARK: Formula

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
    private(set) var activePlan: SoundPlan?
    private(set) var lastError: String?
    /// Increments on every start so views can restart animations.
    private(set) var runID = 0

    private let playback: AudioPlaybackEngine
    @ObservationIgnored private var prepareGeneration = 0
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var preparedConfiguration: RenderConfiguration?

    // MARK: Persistence

    private let sessionStore: SessionStateStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?

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
        formulaText = preset.formula
        parameters = preset.parameters
        settings = preset.settings.clamped()
        volume = restored?.volume ?? defaults.volume
        isLooping = restored?.isLooping ?? defaults.isLooping
        slowMotionWaveform = restored?.slowMotionWaveform ?? false
        viewport = restored?.viewport ?? GraphViewport(xMin: preset.settings.playXMin, xMax: preset.settings.playXMax, yMin: -1.5, yMax: 1.5)
        autoFitY = restored?.autoFitY ?? true
        if !viewport.isValid { viewport = .standard }

        playback.volume = Float(volume)
        playback.onFinished = { [weak self] in self?.playbackFinished() }
        playback.onInterrupted = { [weak self] _ in self?.playbackInterrupted() }

        reparseFormula()
        scheduleCurveUpdate()
        scheduleAnalysis()
    }

    // MARK: - Formula handling

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
            transport.handle(.formulaBecameValid)
        case .failure(let error):
            parsedFormula = nil
            formulaError = error
            transport.handle(.formulaBecameInvalid)
        }
    }

    private func soundConfigurationDidChange(affectsGraph: Bool) {
        stopForConfigurationChange()
        if affectsGraph { scheduleCurveUpdate() }
        scheduleAnalysis()
        scheduleSessionSave()
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
        preparedConfiguration = nil
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

    // MARK: - Graph view

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

    // MARK: - Transport

    /// The immutable configuration for preview and export.
    func makeRenderConfiguration(sampleRate: Double = AudiolyzerModel.previewSampleRate, duration: Double? = nil) -> RenderConfiguration? {
        guard let parsedFormula else { return nil }
        var snapshot = settings
        if let duration { snapshot.duration = duration }
        return RenderConfiguration(formula: parsedFormula, parameters: parameters, settings: snapshot, sampleRate: sampleRate)
    }

    var settingsIssue: String? { settings.validationIssue }

    /// "Graph abspielen": starts the pass from the beginning.
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
        guard let configuration = makeRenderConfiguration() else { return }
        if let issue = configuration.settings.validationIssue {
            lastError = issue
            transport.handle(.fail(issue))
            return
        }
        guard transport.handle(.play) else { return }
        lastError = nil

        if let prepared = preparedConfiguration, prepared == configuration, playback.buffer != nil, activePlan != nil {
            startPlayback(fromFrame: 0)
            return
        }

        prepareGeneration += 1
        let generation = prepareGeneration
        prepareTask?.cancel()
        prepareTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = PreviewRenderer.render(configuration)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.prepareGeneration == generation, self.transport.phase == .preparing else { return }
                switch result {
                case .success(let rendered):
                    self.activePlan = rendered.plan
                    self.preparedConfiguration = configuration
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
        let readout = plan.readout(atTime: time)
        return PlaybackSnapshot(mode: plan.settings.mode, time: time, duration: duration,
                                progress: duration > 0 ? min(1, time / duration) : 0,
                                readout: readout, isPaused: isPaused)
    }

    /// Recomputes the automatic pitch range (graph mode) or the band-limited waveform
    /// (waveform mode) in the background; outdated results are dropped.
    private func scheduleAnalysis() {
        analysisGeneration += 1
        let generation = analysisGeneration
        analysisTask?.cancel()
        guard let formula = parsedFormula else {
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

    // MARK: - Presets and session

    func currentPreset(named name: String = "Aktuelle Einstellungen") -> SoundPreset {
        SoundPreset(name: name, summary: "", formula: formulaText, parameters: parameters, settings: settings)
    }

    func apply(_ preset: SoundPreset) {
        formulaText = preset.formula
        parameters = preset.parameters
        settings = preset.settings.clamped()
        resetView()
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
                                 volume: volume, isLooping: isLooping, slowMotionWaveform: slowMotionWaveform)
        sessionStore.save(state)
    }
}
