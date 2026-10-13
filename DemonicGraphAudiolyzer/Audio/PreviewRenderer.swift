import AVFoundation
import Foundation

/// Result of rendering a pass for the preview.
struct RenderedPreview: @unchecked Sendable {
    let plan: SoundPlan
    /// Mono float buffer at the configuration's sample rate. Created in the render task and
    /// handed over to the main actor exactly once (hence `@unchecked Sendable`).
    let buffer: AVAudioPCMBuffer
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

/// Renders a complete pass for the player with the same `PCMRenderer` that the export uses.
/// Runs off the main thread; checks for cancellation between blocks.
enum PreviewRenderer {
    static let blockFrames = 32_768

    static func render(_ configuration: RenderConfiguration) -> Result<RenderedPreview, PreviewError> {
        let plan: SoundPlan
        do {
            plan = try SoundPlan(configuration: configuration)
        } catch let error as SoundPlanError {
            return .failure(.plan(error.message))
        } catch {
            return .failure(.plan(error.localizedDescription))
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: configuration.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(plan.frameCount)),
              let channel = buffer.floatChannelData?[0] else {
            return .failure(.buffer)
        }
        let renderer = PCMRenderer(plan: plan)
        var offset = 0
        while !renderer.isFinished {
            if Task.isCancelled { break }
            offset += renderer.render(into: channel + offset, capacity: blockFrames)
        }
        buffer.frameLength = AVAudioFrameCount(offset)
        return .success(RenderedPreview(plan: plan, buffer: buffer))
    }
}
