import AVFoundation
import Foundation

/// Plays a pre-rendered PCM pass with `AVAudioEngine` + `AVAudioPlayerNode`.
///
/// The audio clock of the player node (frames actually rendered by the engine) is the only
/// source of the playback position. The UI reads `currentFrame()` on every display frame;
/// a display timer never advances the position on its own. The output latency of the
/// current route (e.g. Bluetooth headphones) is subtracted.
///
/// Pause/stop use a short fade of a sub-mixer before the player is stopped, resume fades in,
/// so there are no clicks. Pausing stores the position; resuming schedules the rest of the
/// buffer, which also makes resuming after engine restarts and route changes robust.
@MainActor
final class AudioPlaybackEngine {
    enum EngineError: LocalizedError {
        case formatUnavailable
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .formatUnavailable: return "Das Audioformat konnte nicht erstellt werden."
            case .engineStartFailed(let reason): return "Die Audioausgabe konnte nicht gestartet werden (\(reason))."
            }
        }
    }

    /// Reasons why the engine stopped on its own.
    enum Interruption {
        case systemInterruption      // phone call, Siri, alarm …
        case outputDeviceRemoved     // headphones unplugged
        case mediaServicesReset
    }

    /// Called when a non-looping pass has been played completely.
    var onFinished: (() -> Void)?
    /// Called when the system interrupted playback; the engine is already paused at `pausedFrame`.
    var onInterrupted: ((Interruption) -> Void)?

    private(set) var isPlaying = false
    private(set) var buffer: AVAudioPCMBuffer?
    private(set) var timeline: PlaybackTimeline?
    private(set) var pausedFrame: Int = 0

    var volume: Float = 0.6 {
        didSet { player.volume = volume }
    }

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var fader = AVAudioMixerNode()
    private var connectedFormat: AVAudioFormat?
    private var scheduleGeneration = 0
    private var fadeTask: Task<Void, Never>?
    private var lastReportedFrame: Double = 0
    private var observers: [NSObjectProtocol] = []

    static let fadeDuration: TimeInterval = 0.03

    init() {
        attachNodes()
        observeSystemNotifications()
    }

    // MARK: Loading and transport

    /// Loads a new pass. Stops anything that is currently playing.
    func load(_ newBuffer: AVAudioPCMBuffer) {
        stopImmediately()
        buffer = newBuffer
        pausedFrame = 0
        timeline = PlaybackTimeline(totalFrames: Int(newBuffer.frameLength),
                                    sampleRate: newBuffer.format.sampleRate,
                                    startFrame: 0, isLooping: false)
    }

    func unload() {
        stopImmediately()
        buffer = nil
        timeline = nil
        pausedFrame = 0
    }

    /// Starts playback at `frame` (0 = beginning).
    func play(fromFrame frame: Int, looping: Bool) throws {
        guard let buffer else { return }
        try startEngineIfNeeded(format: buffer.format)
        let total = Int(buffer.frameLength)
        let start = (frame >= 0 && frame < total) ? frame : 0
        schedule(from: start, looping: looping)
        fader.outputVolume = 0
        player.play()
        isPlaying = true
        ramp(to: 1, duration: Self.fadeDuration, then: nil)
    }

    /// Fades out, stops the player and returns the audible position (frames).
    @discardableResult
    func pause() -> Int {
        guard isPlaying else { return pausedFrame }
        let frame = Int(currentFrame() ?? Double(pausedFrame))
        pausedFrame = frame
        isPlaying = false
        let generation = scheduleGeneration
        ramp(to: 0, duration: Self.fadeDuration) { [weak self] in
            guard let self, self.scheduleGeneration == generation, !self.isPlaying else { return }
            self.player.stop()
        }
        return frame
    }

    /// Fades out and resets to the beginning.
    func stop() {
        guard isPlaying else {
            stopImmediately()
            return
        }
        isPlaying = false
        pausedFrame = 0
        scheduleGeneration += 1
        let generation = scheduleGeneration
        ramp(to: 0, duration: Self.fadeDuration) { [weak self] in
            guard let self, self.scheduleGeneration == generation, !self.isPlaying else { return }
            self.player.stop()
        }
    }

    /// Changes looping while playing by re-scheduling from the current position.
    func setLooping(_ looping: Bool) {
        guard var timeline else { return }
        guard isPlaying else {
            timeline.isLooping = looping
            self.timeline = timeline
            return
        }
        let frame = Int(currentFrame() ?? 0)
        schedule(from: frame, looping: looping)
        player.play()
    }

    /// Stops the engine completely (app in background).
    func suspend() {
        if isPlaying { _ = pause() }
        fadeTask?.cancel()
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Audio clock

    /// Audible position in frames of the current pass, derived from the player's render time.
    func currentFrame() -> Double? {
        guard let timeline else { return nil }
        guard isPlaying else { return Double(pausedFrame) }
        guard let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return lastReportedFrame
        }
        let sampleRate = playerTime.sampleRate > 0 ? playerTime.sampleRate : timeline.sampleRate
        var played = Double(playerTime.sampleTime)
        // Interpolate between render cycles with the host clock for a smooth display.
        if nodeTime.isHostTimeValid {
            let renderSeconds = AVAudioTime.seconds(forHostTime: nodeTime.hostTime)
            let nowSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            let maximumStep = max(0.005, AVAudioSession.sharedInstance().ioBufferDuration * 2)
            played += min(max(nowSeconds - renderSeconds, 0), maximumStep) * sampleRate
        }
        // What is rendered now is heard after the output latency.
        played -= AVAudioSession.sharedInstance().outputLatency * sampleRate
        let position = timeline.position(playedFrames: played * timeline.sampleRate / sampleRate)
        let frame = Double(position.frame)
        lastReportedFrame = frame
        return frame
    }

    // MARK: Scheduling

    private func schedule(from start: Int, looping: Bool) {
        guard let buffer else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        fadeTask?.cancel()
        player.stop()   // clears pending buffers; their completion handlers see an old generation

        let total = Int(buffer.frameLength)
        let first = start > 0 ? (Self.subBuffer(of: buffer, from: start) ?? buffer) : buffer
        if looping {
            if start > 0 {
                player.scheduleBuffer(first, at: nil, options: [], completionHandler: nil)
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        } else {
            player.scheduleBuffer(first, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCompletion(generation: generation)
                }
            }
        }
        timeline = PlaybackTimeline(totalFrames: total, sampleRate: buffer.format.sampleRate,
                                    startFrame: start, isLooping: looping)
        lastReportedFrame = Double(start)
    }

    private func handleCompletion(generation: Int) {
        guard generation == scheduleGeneration, isPlaying else { return }
        isPlaying = false
        pausedFrame = 0
        player.stop()
        onFinished?()
    }

    /// Copy of the frames `start ..< frameLength` (created on the main thread, never in the render path).
    private static func subBuffer(of buffer: AVAudioPCMBuffer, from start: Int) -> AVAudioPCMBuffer? {
        let total = Int(buffer.frameLength)
        let count = total - start
        guard count > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count)),
              let source = buffer.floatChannelData, let target = copy.floatChannelData else { return nil }
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel] + start, count: count)
        }
        copy.frameLength = AVAudioFrameCount(count)
        return copy
    }

    // MARK: Fades

    /// Ramps the sub-mixer volume in small steps (≈ 4 ms) to avoid clicks.
    private func ramp(to target: Float, duration: TimeInterval, then completion: (() -> Void)?) {
        fadeTask?.cancel()
        let start = fader.outputVolume
        let steps = 8
        fadeTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
                if Task.isCancelled { return }
                guard let self else { return }
                let fraction = Float(step) / Float(steps)
                self.fader.outputVolume = start + (target - start) * fraction
            }
            completion?()
        }
    }

    private func stopImmediately() {
        scheduleGeneration += 1
        fadeTask?.cancel()
        isPlaying = false
        player.stop()
        fader.outputVolume = 1
    }

    // MARK: Engine setup

    private func attachNodes() {
        engine.attach(player)
        engine.attach(fader)
        player.volume = volume
        connectedFormat = nil
    }

    private func startEngineIfNeeded(format: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            throw EngineError.engineStartFailed(error.localizedDescription)
        }
        if connectedFormat != format {
            if engine.isRunning { engine.stop() }
            engine.connect(player, to: fader, format: format)
            engine.connect(fader, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                throw EngineError.engineStartFailed(error.localizedDescription)
            }
        }
    }

    // MARK: System events

    private func observeSystemNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let rawType, AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
                self.handleInterruption(.systemInterruption)
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let rawReason,
                      AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
                self.handleInterruption(.outputDeviceRemoved)
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildAfterMediaServicesReset()
            }
        })

        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            let sender = note.object as AnyObject?
            MainActor.assumeIsolated {
                guard let self, sender === self.engine else { return }
                self.handleConfigurationChange()
            }
        })
    }

    private func handleInterruption(_ reason: Interruption) {
        guard isPlaying else { return }
        let frame = Int(currentFrame() ?? Double(pausedFrame))
        pausedFrame = frame
        isPlaying = false
        scheduleGeneration += 1
        fadeTask?.cancel()
        player.stop()
        onInterrupted?(reason)
    }

    /// The engine stops itself when the output hardware changes (sample rate, channels).
    /// Restart it and continue at the same position.
    private func handleConfigurationChange() {
        connectedFormat = nil
        guard isPlaying, let timeline, let buffer else { return }
        let frame = Int(currentFrame() ?? Double(timeline.startFrame))
        do {
            try startEngineIfNeeded(format: buffer.format)
            schedule(from: frame, looping: timeline.isLooping)
            fader.outputVolume = 1
            player.play()
        } catch {
            pausedFrame = frame
            isPlaying = false
            onInterrupted?(.outputDeviceRemoved)
        }
    }

    private func rebuildAfterMediaServicesReset() {
        let wasPlaying = isPlaying
        if wasPlaying {
            pausedFrame = Int(lastReportedFrame)
        }
        isPlaying = false
        fadeTask?.cancel()
        scheduleGeneration += 1
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        fader = AVAudioMixerNode()
        attachNodes()
        if wasPlaying {
            onInterrupted?(.mediaServicesReset)
        }
    }
}
