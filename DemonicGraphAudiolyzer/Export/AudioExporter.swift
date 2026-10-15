import AVFoundation
import Foundation

/// Result of a finished export.
struct ExportResult: Equatable, Sendable {
    var url: URL
    var format: ExportFormat
    var options: ExportOptions
    /// Duration of the rendered signal (one complete pass).
    var renderedDuration: Double
    var byteCount: Int
}

/// Facts read back from the written file with AVFoundation (proves the file is decodable).
struct ExportVerification: Equatable, Sendable {
    var codecName: String
    var sampleRate: Double
    var channels: Int
    var decodedDuration: Double
}

enum ExportError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .cancelled: return "Der Export wurde abgebrochen."
        case .failed(let message): return message
        }
    }
}

/// Renders a configuration chunk by chunk and encodes it directly into the target format.
/// No microphone, no system audio capture – the file contains exactly the generated PCM.
enum AudioExporter {
    static let chunkFrames = 16_384

    /// Directory for finished exports. Files stay available while they are shared or saved
    /// and are removed on a later launch (see `ExportStorage.removeStaleExports`).
    static var exportsDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    /// Synchronous export of a classic configuration (see `export(job:…)`).
    static func export(configuration: RenderConfiguration, options: ExportOptions, fileName: String,
                       directory: URL = AudioExporter.exportsDirectory,
                       progress: (Double) -> Void) throws -> ExportResult {
        try export(job: .classic(configuration), options: options, fileName: fileName, directory: directory, progress: progress)
    }

    /// Synchronous export; call from a background task. Checks `Task.isCancelled` between chunks.
    /// Uses the same render core as the preview (`JobRenderer`): identical events, parameters,
    /// envelopes, effects and level.
    /// - Parameter progress: called with values 0 … 1 (from the calling thread).
    static func export(job: RenderJob, options: ExportOptions, fileName: String,
                       directory: URL = AudioExporter.exportsDirectory,
                       progress: (Double) -> Void) throws -> ExportResult {
        let job = job.withSampleRate(options.sampleRate)
        let plan: ActivePlan
        do {
            plan = try ActivePlan(job: job)
        } catch let error as RenderJobError {
            throw ExportError.invalidConfiguration(error.message)
        }

        let jobDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        } catch {
            throw ExportError.failed("Exportordner konnte nicht angelegt werden: \(error.localizedDescription)")
        }
        let baseName = ExportFileName.sanitized(fileName)
        let finalURL = jobDirectory.appendingPathComponent(baseName).appendingPathExtension(options.format.fileExtension)
        // Write to a temporary name first; the final name only appears when the file is complete.
        let partialURL = jobDirectory.appendingPathComponent("unvollstaendig-" + baseName).appendingPathExtension(options.format.fileExtension)

        var encoder: AudioFileEncoding?
        do {
            encoder = try AudioFileEncoderFactory.make(for: options, url: partialURL, maximumChunk: chunkFrames)
            let renderer = JobRenderer(plan: plan)
            var left = [Float](repeating: 0, count: chunkFrames)
            var right = [Float](repeating: 0, count: chunkFrames)
            var lastReported = -1.0
            progress(0)
            while !renderer.isFinished {
                if Task.isCancelled {
                    throw ExportError.cancelled
                }
                let written = left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        renderer.render(left: l.baseAddress!, right: r.baseAddress!, capacity: chunkFrames)
                    }
                }
                try left.withUnsafeBufferPointer { l in
                    try right.withUnsafeBufferPointer { r in
                        try encoder?.write(left: l.baseAddress!, right: r.baseAddress!, frameCount: written)
                    }
                }
                let fraction = Double(renderer.position) / Double(renderer.totalFrames)
                if fraction - lastReported >= 0.005 || renderer.isFinished {
                    lastReported = fraction
                    progress(fraction * 0.98)
                }
            }
            if Task.isCancelled {
                throw ExportError.cancelled
            }
            try encoder?.finish()
            encoder = nil
            try fileManager.moveItem(at: partialURL, to: finalURL)
            progress(1)
        } catch {
            encoder?.abandon()
            try? fileManager.removeItem(at: jobDirectory)
            if let exportError = error as? ExportError { throw exportError }
            throw ExportError.failed(error.localizedDescription)
        }

        let size = (try? fileManager.attributesOfItem(atPath: finalURL.path)[.size] as? NSNumber)?.intValue ?? 0
        return ExportResult(url: finalURL, format: options.format, options: options,
                            renderedDuration: Double(plan.frameCount) / plan.sampleRate,
                            byteCount: size)
    }

    /// Opens the written file with AVFoundation and reports codec, rate, channels and length.
    static func verify(_ url: URL) throws -> ExportVerification {
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        let formatID = (format.settings[AVFormatIDKey] as? NSNumber)?.uint32Value ?? 0
        let codec: String
        switch formatID {
        case kAudioFormatLinearPCM: codec = "PCM"
        case kAudioFormatMPEG4AAC: codec = "AAC"
        case kAudioFormatMPEGLayer3: codec = "MP3"
        default: codec = String(format: "0x%08X", formatID)
        }
        let rate = format.sampleRate
        return ExportVerification(codecName: codec, sampleRate: rate, channels: Int(format.channelCount),
                                  decodedDuration: rate > 0 ? Double(file.length) / rate : 0)
    }
}

enum ExportStorage {
    /// Removes exports older than one day (they were already shared or saved).
    static func removeStaleExports(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        let directory = AudioExporter.exportsDirectory
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-age)
        for entry in entries {
            let date = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date < limit {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}
