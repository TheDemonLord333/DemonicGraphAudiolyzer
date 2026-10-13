import AVFoundation
import Foundation
import Observation

/// State of the export dialog. Rendering and encoding run in a detached task; the UI
/// only receives progress updates on the main actor.
@MainActor
@Observable
final class ExportModel {
    enum State: Equatable {
        case idle
        case running(progress: Double)
        case finished(ExportResult)
        case failed(String)
        case cancelled
    }

    var options: ExportOptions
    var fileName: String
    /// Duration of the exported pass (defaults to the current pass duration).
    var duration: Double
    private(set) var state: State = .idle
    private(set) var verification: ExportVerification?
    private(set) var isPreviewPlaying = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var previewPlayer: AVAudioPlayer?
    @ObservationIgnored private var previewDelegate: PreviewDelegate?

    init(options: ExportOptions, fileName: String, duration: Double) {
        self.options = options
        self.fileName = fileName
        self.duration = duration
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var result: ExportResult? {
        if case .finished(let result) = state { return result }
        return nil
    }

    /// Starts the export of `configuration`. `onEnd` is called on the main actor when it finishes.
    func start(configuration: RenderConfiguration, onEnd: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        stopPreview()
        verification = nil
        state = .running(progress: 0)
        var job = configuration
        job.settings.duration = duration.clamped(to: SoundSettings.durationRange, fallback: configuration.settings.duration)
        let options = self.options
        let name = fileName
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: Result<ExportResult, ExportError>
            do {
                let result = try AudioExporter.export(configuration: job, options: options, fileName: name) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .running(let current) = self.state, fraction > current else { return }
                        self.state = .running(progress: fraction)
                    }
                }
                outcome = .success(result)
            } catch let error as ExportError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.failed(error.localizedDescription))
            }
            var verification: ExportVerification?
            if case .success(let result) = outcome {
                verification = try? AudioExporter.verify(result.url)
            }
            let checked = verification
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let result):
                    self.state = .finished(result)
                    self.verification = checked
                case .failure(.cancelled):
                    self.state = .cancelled
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                }
                onEnd()
            }
        }
    }

    /// Cancels the running export; partial files are deleted by the exporter.
    func cancel() {
        task?.cancel()
    }

    func reset() {
        stopPreview()
        state = .idle
        verification = nil
    }

    // MARK: "Anhören" – plays the exported file itself

    func togglePreview() {
        if isPreviewPlaying {
            stopPreview()
            return
        }
        guard let url = result?.url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PreviewDelegate { [weak self] in
                self?.isPreviewPlaying = false
            }
            player.delegate = delegate
            player.volume = 0.8
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            previewDelegate = delegate
            isPreviewPlaying = true
        } catch {
            state = .failed("Die exportierte Datei kann nicht abgespielt werden: \(error.localizedDescription)")
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewDelegate = nil
        isPreviewPlaying = false
    }
}

private final class PreviewDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @MainActor () -> Void

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let handler = onFinish
        Task { @MainActor in handler() }
    }
}
