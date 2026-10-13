import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("WAV-Export (PCM)")
struct WAVWriterTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wavtest-\(UUID().uuidString)-\(name)")
    }

    private func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<offset + 4].enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * UInt32($1.offset))) }
    }

    private func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    @Test("Header und Daten 16 Bit Stereo", arguments: [WAVBitDepth.sixteen, WAVBitDepth.twentyFour])
    func writesValidRIFF(bitDepth: WAVBitDepth) throws {
        let url = temporaryURL("test.wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = 44_100
        let left = (0..<frames).map { Float(sin(2 * Double.pi * 440 * Double($0) / 44_100) * 0.5) }
        let writer = try WAVFileWriter(url: url, sampleRate: 44_100, channels: 2, bitDepth: bitDepth)
        try left.withUnsafeBufferPointer { pointer in
            // Write in two chunks.
            let base = pointer.baseAddress!
            try writer.write(channelData: [base, base], frameCount: 20_000)
            try writer.write(channelData: [base + 20_000, base + 20_000], frameCount: frames - 20_000)
        }
        try writer.finish()

        let data = try Data(contentsOf: url)
        let bytesPerSample = bitDepth.bytesPerSample
        #expect(data.count == 44 + frames * 2 * bytesPerSample)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(readUInt32(data, 4) == UInt32(data.count - 8))
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[12..<16], as: UTF8.self) == "fmt ")
        #expect(readUInt16(data, 20) == 1)
        #expect(readUInt16(data, 22) == 2)
        #expect(readUInt32(data, 24) == 44_100)
        #expect(readUInt16(data, 34) == UInt16(bitDepth.rawValue))
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        #expect(readUInt32(data, 40) == UInt32(frames * 2 * bytesPerSample))

        // Sample 1 000 of the left channel must match the source.
        let offset = 44 + 1_000 * 2 * bytesPerSample
        let decoded: Double
        if bitDepth == .sixteen {
            decoded = Double(Int16(bitPattern: readUInt16(data, offset))) / 32_767
        } else {
            let raw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            let signed = Int32(bitPattern: raw << 8) >> 8
            decoded = Double(signed) / 8_388_607
        }
        #expect(abs(decoded - Double(left[1_000])) < 1e-4)
    }

    @Test("Dateinamen werden bereinigt")
    func sanitizedNames() {
        #expect(ExportFileName.sanitized("Sanfte/Welle: sin(x)") == "Sanfte-Welle- sin(x)")
        #expect(ExportFileName.sanitized("   ") == "Demonic Graph")
        #expect(ExportFileName.sanitized("..versteckt") == "versteckt")
    }
}
