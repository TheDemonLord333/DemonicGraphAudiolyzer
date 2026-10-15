import AVFoundation
import Foundation

/// Result of rendering a pass for the preview.
struct RenderedPreview: @unchecked Sendable {
    let plan: ActivePlan
    /// Float buffer (mono for the classic modes, stereo for the synthesizer) at the job's sample
    /// rate. Created in the render task and handed over to the main actor exactly once
    /// (hence `@unchecked Sendable`).
    let buffer: AVAudioPCMBuffer
    /// Per-voice signals for the audio snippet display (synthesizer only).
    let stems: [UUID: [Int16]]
    /// Frames in which the safety limiter acted.
    let limitedFrames: Int

    var soundPlan: SoundPlan? {
        if case .classic(let plan) = plan { return plan }
        return nil
    }

    var synthPlan: SynthPlan? {
        if case .synth(let plan) = plan { return plan }
        return nil
    }
}

enum PreviewError: LocalizedError, Sendable {
    case plan(String)
    case buffer

    var errorDescription: String? {
        switch self {
        case .plan(let message): return message
        case .buffer: return "Der Audiopuffer konnte nicht angelegt werden."
        }
    }
}

/// Renders a complete pass for the player with the same `JobRenderer` that the export uses.
/// Runs off the main thread; checks for cancellation between blocks.
enum PreviewRenderer {
    static let blockFrames = 32_768

    static func render(_ configuration: RenderConfiguration) -> Result<RenderedPreview, PreviewError> {
        render(job: .classic(configuration))
    }

    static func render(job: RenderJob) -> Result<RenderedPreview, PreviewError> {
        let plan: ActivePlan
        do {
            plan = try ActivePlan(job: job)
        } catch let error as RenderJobError {
            return .failure(.plan(error.message))
        } catch {
            return .failure(.plan(error.localizedDescription))
        }
        let channels = AVAudioChannelCount(job.channelCount)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: job.sampleRate, channels: channels),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(plan.frameCount)),
              let data = buffer.floatChannelData else {
            return .failure(.buffer)
        }
        let renderer = JobRenderer(plan: plan, captureStems: true)
        let left = data[0]
        // Mono buffers: the renderer writes the copy for the right channel into scratch space.
        var scratch = channels == 1 ? [Float](repeating: 0, count: blockFrames) : []
        var offset = 0
        while !renderer.isFinished {
            if Task.isCancelled { break }
            if channels == 1 {
                offset += scratch.withUnsafeMutableBufferPointer { right in
                    renderer.render(left: left + offset, right: right.baseAddress!, capacity: blockFrames)
                }
            } else {
                offset += renderer.render(left: left + offset, right: data[1] + offset, capacity: blockFrames)
            }
        }
        buffer.frameLength = AVAudioFrameCount(offset)
        return .success(RenderedPreview(plan: plan, buffer: buffer, stems: renderer.stems, limitedFrames: renderer.limitedFrames))
    }
}
