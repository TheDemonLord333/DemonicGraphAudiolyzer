import Foundation

/// What is rendered: a classic configuration ("Graph vertonen", "Formel als Klangwelle") or a
/// synthesizer project. Preview and export are created from the same job type.
enum RenderJob: Equatable, Sendable {
    case classic(RenderConfiguration)
    case synth(SynthRenderConfiguration)

    var sampleRate: Double {
        switch self {
        case .classic(let configuration): return configuration.sampleRate
        case .synth(let configuration): return configuration.sampleRate
        }
    }

    func withSampleRate(_ rate: Double) -> RenderJob {
        switch self {
        case .classic(let configuration): return .classic(configuration.withSampleRate(rate))
        case .synth(let configuration): return .synth(configuration.withSampleRate(rate))
        }
    }

    var frameCount: Int {
        switch self {
        case .classic(let configuration): return configuration.frameCount
        case .synth(let configuration): return configuration.frameCount
        }
    }

    var duration: Double { Double(frameCount) / sampleRate }

    /// Channels of the generated signal (classic: mono, written to both channels).
    var channelCount: Int {
        switch self {
        case .classic: return 1
        case .synth: return 2
        }
    }
}

enum RenderJobError: Error, Equatable, Sendable {
    case invalid(String)

    var message: String {
        switch self {
        case .invalid(let text): return text
        }
    }
}

/// The prepared plan of a job.
enum ActivePlan: Sendable {
    case classic(SoundPlan)
    case synth(SynthPlan)

    var sampleRate: Double {
        switch self {
        case .classic(let plan): return plan.sampleRate
        case .synth(let plan): return plan.sampleRate
        }
    }

    var frameCount: Int {
        switch self {
        case .classic(let plan): return plan.frameCount
        case .synth(let plan): return plan.frameCount
        }
    }

    init(job: RenderJob) throws {
        switch job {
        case .classic(let configuration):
            do {
                self = .classic(try SoundPlan(configuration: configuration))
            } catch let error as SoundPlanError {
                throw RenderJobError.invalid(error.message)
            }
        case .synth(let configuration):
            do {
                self = .synth(try SynthPlan(configuration: configuration))
            } catch let error as SynthPlanError {
                throw RenderJobError.invalid(error.message)
            }
        }
    }
}

/// Renders a job as stereo – the single render core of preview and export.
final class JobRenderer {
    let plan: ActivePlan
    private let classic: PCMRenderer?
    private let synth: SynthRenderer?

    init(plan: ActivePlan, captureStems: Bool = false) {
        self.plan = plan
        switch plan {
        case .classic(let soundPlan):
            classic = PCMRenderer(plan: soundPlan)
            synth = nil
        case .synth(let synthPlan):
            classic = nil
            synth = SynthRenderer(plan: synthPlan, captureStems: captureStems)
        }
    }

    convenience init(job: RenderJob, captureStems: Bool = false) throws {
        self.init(plan: try ActivePlan(job: job), captureStems: captureStems)
    }

    var totalFrames: Int { classic?.totalFrames ?? synth?.totalFrames ?? 0 }
    var position: Int { classic?.position ?? synth?.position ?? 0 }
    var isFinished: Bool { position >= totalFrames }
    var stems: [UUID: [Int16]] { synth?.stems ?? [:] }
    var limitedFrames: Int { synth?.limitedFrames ?? 0 }

    /// Renders up to `capacity` frames into both channels. Returns the frames written.
    @discardableResult
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        if let classic {
            let written = classic.render(into: left, capacity: capacity)
            right.update(from: left, count: written)
            return written
        }
        return synth?.render(left: left, right: right, capacity: capacity) ?? 0
    }
}
