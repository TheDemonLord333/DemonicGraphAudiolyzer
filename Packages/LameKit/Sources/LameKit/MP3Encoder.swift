import CLame

/// Errors reported by `MP3Encoder`.
public enum MP3EncoderError: Error, Equatable, CustomStringConvertible {
    /// `lame_init()` returned no encoder instance.
    case initializationFailed
    /// `lame_init_params()` rejected the parameter combination.
    case invalidParameters(code: Int32)
    /// A LAME encode call returned a negative status.
    case encodingFailed(code: Int32)
    /// The encoder was used after `finish()`.
    case alreadyFinished
    /// Unsupported sample rate, channel count or bitrate.
    case unsupportedConfiguration(String)

    public var description: String {
        switch self {
        case .initializationFailed:
            return "LAME konnte nicht initialisiert werden."
        case .invalidParameters(let code):
            return "LAME hat die Encoder-Parameter abgelehnt (Code \(code))."
        case .encodingFailed(let code):
            return "MP3-Kodierung fehlgeschlagen (LAME-Code \(code))."
        case .alreadyFinished:
            return "Der MP3-Encoder wurde bereits abgeschlossen."
        case .unsupportedConfiguration(let reason):
            return "Nicht unterstützte MP3-Einstellung: \(reason)"
        }
    }
}

/// A narrow, allocation-conscious Swift interface to the LAME MP3 encoder.
///
/// Usage:
/// 1. `init` with sample rate, channel count and constant bitrate.
/// 2. Call `encode(left:right:frameCount:)` repeatedly with float PCM in [-1, 1].
/// 3. Call `finish()` once to flush the last frames.
/// 4. Optionally overwrite the first `infoTagFrame().count` bytes of the written
///    file with `infoTagFrame()` (LAME/Xing "Info" tag with exact length,
///    encoder delay and padding, used by decoders for gapless playback).
///
/// The class is not thread-safe; use one instance per export on one thread.
public final class MP3Encoder {
    /// Bitrates (kbit/s) that MPEG-1 Layer III supports at 32/44.1/48 kHz.
    public static let supportedBitrates: [Int] = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    /// Sample rates (Hz) of MPEG-1 Layer III.
    public static let supportedSampleRates: [Int] = [32_000, 44_100, 48_000]

    public let sampleRate: Int
    public let channels: Int
    public let bitrateKbps: Int

    private var handle: lame_t?
    private var buffer: [UInt8]
    private var finished = false

    /// The version string of the linked LAME library, e.g. "3.100".
    public static var lameVersion: String {
        guard let cString = get_lame_version() else { return "unbekannt" }
        return String(cString: cString)
    }

    /// - Parameters:
    ///   - sampleRate: 32000, 44100 or 48000 Hz (no resampling is performed).
    ///   - channels: 1 (mono) or 2 (joint stereo).
    ///   - bitrateKbps: constant bitrate, one of `supportedBitrates`.
    ///   - quality: LAME algorithm quality 0 (best, slowest) … 9 (worst, fastest). 2 ≙ `-h`.
    ///   - writeInfoTag: reserve the first frame for the LAME "Info" tag.
    public init(sampleRate: Int, channels: Int, bitrateKbps: Int, quality: Int = 2, writeInfoTag: Bool = true) throws {
        guard Self.supportedSampleRates.contains(sampleRate) else {
            throw MP3EncoderError.unsupportedConfiguration("Abtastrate \(sampleRate) Hz")
        }
        guard channels == 1 || channels == 2 else {
            throw MP3EncoderError.unsupportedConfiguration("\(channels) Kanäle")
        }
        guard Self.supportedBitrates.contains(bitrateKbps) else {
            throw MP3EncoderError.unsupportedConfiguration("\(bitrateKbps) kbit/s")
        }
        guard let gfp = lame_init() else {
            throw MP3EncoderError.initializationFailed
        }
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitrateKbps = bitrateKbps
        self.handle = gfp
        // Worst case output size per LAME documentation: 1.25 * samples + 7200.
        self.buffer = [UInt8](repeating: 0, count: 7200)

        // Silence LAME's stderr reporting; errors are reported through return codes.
        lame_set_errorf(gfp, nil)
        lame_set_debugf(gfp, nil)
        lame_set_msgf(gfp, nil)

        lame_set_in_samplerate(gfp, Int32(sampleRate))
        lame_set_out_samplerate(gfp, Int32(sampleRate))
        lame_set_num_channels(gfp, Int32(channels))
        lame_set_mode(gfp, channels == 1 ? MONO : JOINT_STEREO)
        lame_set_VBR(gfp, vbr_off)
        lame_set_brate(gfp, Int32(bitrateKbps))
        lame_set_quality(gfp, Int32(max(0, min(9, quality))))
        lame_set_bWriteVbrTag(gfp, writeInfoTag ? 1 : 0)
        lame_set_write_id3tag_automatic(gfp, 0)

        let status = lame_init_params(gfp)
        guard status >= 0 else {
            lame_close(gfp)
            self.handle = nil
            throw MP3EncoderError.invalidParameters(code: status)
        }
    }

    deinit {
        if let handle {
            lame_close(handle)
        }
    }

    /// Samples of encoder delay that LAME prepends (needed to compute exact lengths).
    public var encoderDelay: Int {
        guard let handle else { return 0 }
        return Int(lame_get_encoder_delay(handle))
    }

    /// Samples of padding appended to the last frame (valid after `finish()`).
    public var encoderPadding: Int {
        guard let handle else { return 0 }
        return Int(lame_get_encoder_padding(handle))
    }

    /// Number of MPEG frames produced so far.
    public var frameCount: Int {
        guard let handle else { return 0 }
        return Int(lame_get_frameNum(handle))
    }

    /// Encodes `frameCount` float samples per channel (range -1 … 1).
    /// For mono encoders `right` is ignored.
    /// - Returns: the MP3 bytes produced by this call (may be empty while LAME buffers).
    public func encode(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, frameCount: Int) throws -> [UInt8] {
        guard let handle else { throw MP3EncoderError.initializationFailed }
        guard !finished else { throw MP3EncoderError.alreadyFinished }
        guard frameCount > 0 else { return [] }

        let required = frameCount + frameCount / 4 + 7200
        if buffer.count < required {
            buffer = [UInt8](repeating: 0, count: required)
        }
        let rightChannel = channels == 2 ? (right ?? left) : left
        let capacity = Int32(buffer.count)
        let written = buffer.withUnsafeMutableBufferPointer { out -> Int32 in
            lame_encode_buffer_ieee_float(handle, left, rightChannel, Int32(frameCount), out.baseAddress, capacity)
        }
        guard written >= 0 else { throw MP3EncoderError.encodingFailed(code: written) }
        return Array(buffer[0..<Int(written)])
    }

    /// Flushes the remaining samples (pads the final frame). Call exactly once.
    public func finish() throws -> [UInt8] {
        guard let handle else { throw MP3EncoderError.initializationFailed }
        guard !finished else { throw MP3EncoderError.alreadyFinished }
        finished = true
        if buffer.count < 7200 {
            buffer = [UInt8](repeating: 0, count: 7200)
        }
        let capacity = Int32(buffer.count)
        let written = buffer.withUnsafeMutableBufferPointer { out -> Int32 in
            lame_encode_flush(handle, out.baseAddress, capacity)
        }
        guard written >= 0 else { throw MP3EncoderError.encodingFailed(code: written) }
        return Array(buffer[0..<Int(written)])
    }

    /// The final LAME "Info" tag frame. Its size equals the placeholder frame
    /// LAME emitted at the very beginning of the stream; write it at offset 0
    /// after `finish()`. Empty when the tag was disabled.
    public func infoTagFrame() -> [UInt8] {
        guard let handle else { return [] }
        let size = lame_get_lametag_frame(handle, nil, 0)
        guard size > 0 else { return [] }
        var tag = [UInt8](repeating: 0, count: Int(size))
        let written = tag.withUnsafeMutableBufferPointer { out -> Int in
            Int(lame_get_lametag_frame(handle, out.baseAddress, size))
        }
        guard written > 0 else { return [] }
        return Array(tag[0..<written])
    }
}
