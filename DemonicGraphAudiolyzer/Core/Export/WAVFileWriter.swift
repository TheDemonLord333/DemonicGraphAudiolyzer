import Foundation

/// Streams linear PCM (16 or 24 bit, little endian, interleaved) into a RIFF/WAVE file.
/// The header sizes are patched in `finish()`.
final class WAVFileWriter {
    let url: URL
    let sampleRate: Int
    let channels: Int
    let bitDepth: WAVBitDepth

    private var handle: FileHandle?
    private var dataBytes: Int = 0
    private var scratch: [UInt8] = []

    enum WriterError: Error, Equatable {
        case cannotCreateFile
        case alreadyFinished
        case tooLarge
    }

    init(url: URL, sampleRate: Int, channels: Int, bitDepth: WAVBitDepth) throws {
        self.url = url
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw WriterError.cannotCreateFile
        }
        let handle = try FileHandle(forWritingTo: url)
        self.handle = handle
        try handle.write(contentsOf: Self.header(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth, dataBytes: 0))
    }

    deinit {
        try? handle?.close()
    }

    /// Writes `frameCount` frames. `channelData[c][i]` is sample i of channel c (−1 … 1).
    func write(channelData: [UnsafePointer<Float>], frameCount: Int) throws {
        guard let handle else { throw WriterError.alreadyFinished }
        guard frameCount > 0 else { return }
        let bytesPerSample = bitDepth.bytesPerSample
        let needed = frameCount * channels * bytesPerSample
        if scratch.count < needed {
            scratch = [UInt8](repeating: 0, count: needed)
        }
        scratch.withUnsafeMutableBufferPointer { bytes in
            var offset = 0
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let source = channelData[min(channel, channelData.count - 1)]
                    let value = Double(max(-1, min(1, source[frame])))
                    switch bitDepth {
                    case .sixteen:
                        let integer = Int16((value * 32_767).rounded())
                        let bits = UInt16(bitPattern: integer)
                        bytes[offset] = UInt8(bits & 0xFF)
                        bytes[offset + 1] = UInt8(bits >> 8)
                    case .twentyFour:
                        let integer = Int32((value * 8_388_607).rounded())
                        let bits = UInt32(bitPattern: integer)
                        bytes[offset] = UInt8(bits & 0xFF)
                        bytes[offset + 1] = UInt8((bits >> 8) & 0xFF)
                        bytes[offset + 2] = UInt8((bits >> 16) & 0xFF)
                    }
                    offset += bytesPerSample
                }
            }
        }
        try handle.write(contentsOf: scratch[0..<needed])
        dataBytes += needed
        if dataBytes > Int(UInt32.max) - 44 {
            throw WriterError.tooLarge
        }
    }

    /// Patches the RIFF and data chunk sizes and closes the file.
    func finish() throws {
        guard let handle else { throw WriterError.alreadyFinished }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Self.header(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth, dataBytes: dataBytes))
        try handle.close()
        self.handle = nil
    }

    /// Closes without finalising (used when an export is cancelled).
    func abandon() {
        try? handle?.close()
        handle = nil
    }

    static func header(sampleRate: Int, channels: Int, bitDepth: WAVBitDepth, dataBytes: Int) -> Data {
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let blockAlign = channels * bitDepth.bytesPerSample
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)                                  // fmt chunk size
        append16(1)                                   // WAVE_FORMAT_PCM
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * blockAlign))     // byte rate
        append16(UInt16(blockAlign))
        append16(UInt16(bitDepth.rawValue))
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(dataBytes))
        return data
    }
}
