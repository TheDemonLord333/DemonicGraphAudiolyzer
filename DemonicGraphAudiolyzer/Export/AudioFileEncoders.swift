import AVFoundation
import Foundation
import LameKit

/// Common interface of the three file encoders. Input is the mono signal of the renderer;
/// the encoders write it to every output channel.
protocol AudioFileEncoding: AnyObject {
    func write(mono: UnsafePointer<Float>, frameCount: Int) throws
    func finish() throws
    func abandon()
}

enum AudioFileEncoderError: LocalizedError {
    case cannotCreateFile(String)
    case bufferAllocationFailed
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let reason): return "Die Datei konnte nicht angelegt werden: \(reason)"
        case .bufferAllocationFailed: return "Der Exportpuffer konnte nicht angelegt werden."
        case .encodingFailed(let reason): return "Kodierung fehlgeschlagen: \(reason)"
        }
    }
}

enum AudioFileEncoderFactory {
    static func make(for options: ExportOptions, url: URL, maximumChunk: Int) throws -> AudioFileEncoding {
        switch options.format {
        case .wav:
            return try WAVEncoder(url: url, sampleRate: Int(options.sampleRate), channels: options.channels, bitDepth: options.wavBitDepth)
        case .m4a:
            return try AACEncoder(url: url, sampleRate: options.sampleRate, channels: options.channels,
                                  bitrate: options.aacBitrate, maximumChunk: maximumChunk)
        case .mp3:
            return try LameMP3FileEncoder(url: url, sampleRate: Int(options.sampleRate), channels: options.channels,
                                          bitrate: options.mp3Bitrate, quality: options.mp3Quality.rawValue)
        }
    }
}

// MARK: - WAV (linear PCM)

final class WAVEncoder: AudioFileEncoding {
    private let writer: WAVFileWriter
    private let channels: Int

    init(url: URL, sampleRate: Int, channels: Int, bitDepth: WAVBitDepth) throws {
        self.channels = channels
        self.writer = try WAVFileWriter(url: url, sampleRate: sampleRate, channels: channels, bitDepth: bitDepth)
    }

    func write(mono: UnsafePointer<Float>, frameCount: Int) throws {
        try writer.write(channelData: Array(repeating: mono, count: channels), frameCount: frameCount)
    }

    func finish() throws {
        try writer.finish()
    }

    func abandon() {
        writer.abandon()
    }
}

// MARK: - M4A (AAC via AVAudioFile / ExtAudioFile)

final class AACEncoder: AudioFileEncoding {
    private var file: AVAudioFile?
    private let buffer: AVAudioPCMBuffer
    private let channels: Int

    init(url: URL, sampleRate: Double, channels: Int, bitrate: Int, maximumChunk: Int) throws {
        self.channels = channels
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate * 1_000,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        do {
            // The .m4a extension selects the MPEG-4 container (kAudioFileM4AType).
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioFileEncoderError.cannotCreateFile(error.localizedDescription)
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maximumChunk)) else {
            throw AudioFileEncoderError.bufferAllocationFailed
        }
        self.buffer = buffer
    }

    func write(mono: UnsafePointer<Float>, frameCount: Int) throws {
        guard let file, let channelData = buffer.floatChannelData else { return }
        var offset = 0
        while offset < frameCount {
            let count = min(frameCount - offset, Int(buffer.frameCapacity))
            for channel in 0..<channels {
                channelData[channel].update(from: mono + offset, count: count)
            }
            buffer.frameLength = AVAudioFrameCount(count)
            do {
                try file.write(from: buffer)
            } catch {
                throw AudioFileEncoderError.encodingFailed(error.localizedDescription)
            }
            offset += count
        }
    }

    func finish() throws {
        // Releasing the AVAudioFile finalises the MPEG-4 container (moov atom, priming info).
        if #available(iOS 18.0, macOS 15.0, *) {
            file?.close()
        }
        file = nil
    }

    func abandon() {
        file = nil
    }
}

// MARK: - MP3 (LAME)

/// Information about the bundled MP3 encoder for the UI.
enum MP3EncoderInfo {
    static var version: String { MP3Encoder.lameVersion }
}

/// Writes real MPEG-1 Layer III frames produced by LAME (never a renamed WAV/M4A).
final class LameMP3FileEncoder: AudioFileEncoding {
    private let encoder: MP3Encoder
    private var handle: FileHandle?

    init(url: URL, sampleRate: Int, channels: Int, bitrate: Int, quality: Int) throws {
        do {
            encoder = try MP3Encoder(sampleRate: sampleRate, channels: channels, bitrateKbps: bitrate, quality: quality)
        } catch {
            throw AudioFileEncoderError.encodingFailed(String(describing: error))
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw AudioFileEncoderError.cannotCreateFile(url.lastPathComponent)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    deinit {
        try? handle?.close()
    }

    func write(mono: UnsafePointer<Float>, frameCount: Int) throws {
        guard let handle else { return }
        let bytes: [UInt8]
        do {
            bytes = try encoder.encode(left: mono, right: mono, frameCount: frameCount)
        } catch {
            throw AudioFileEncoderError.encodingFailed(String(describing: error))
        }
        if !bytes.isEmpty {
            try handle.write(contentsOf: bytes)
        }
    }

    func finish() throws {
        guard let handle else { return }
        do {
            let tail = try encoder.finish()
            if !tail.isEmpty {
                try handle.write(contentsOf: tail)
            }
        } catch let error as MP3EncoderError {
            throw AudioFileEncoderError.encodingFailed(error.description)
        }
        // Replace the placeholder first frame by the LAME "Info" tag (exact length, encoder
        // delay and padding → gapless decoding and correct duration).
        let tag = encoder.infoTagFrame()
        if !tag.isEmpty {
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: tag)
        }
        try handle.close()
        self.handle = nil
    }

    func abandon() {
        try? handle?.close()
        handle = nil
    }
}
