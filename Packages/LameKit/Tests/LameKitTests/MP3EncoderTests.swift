import Foundation
import XCTest
@testable import LameKit

final class MP3EncoderTests: XCTestCase {
    private func sine(frequency: Double, sampleRate: Int, frames: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<frames).map { index in
            amplitude * Float(sin(2.0 * Double.pi * frequency * Double(index) / Double(sampleRate)))
        }
    }

    /// Parses the MPEG audio frame header at `offset` and returns (bitrate kbps, sample rate, frame length).
    private func parseFrameHeader(_ bytes: [UInt8], at offset: Int) -> (bitrate: Int, sampleRate: Int, length: Int)? {
        guard offset + 4 <= bytes.count else { return nil }
        let b1 = bytes[offset], b2 = bytes[offset + 1], b3 = bytes[offset + 2]
        guard b1 == 0xFF, (b2 & 0xE0) == 0xE0 else { return nil }
        let version = (b2 >> 3) & 0x03   // 3 = MPEG-1
        let layer = (b2 >> 1) & 0x03     // 1 = Layer III
        guard version == 3, layer == 1 else { return nil }
        let bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
        let rates = [44_100, 48_000, 32_000, 0]
        let bitrate = bitrates[Int(b3 >> 4)]
        let rate = rates[Int((b3 >> 2) & 0x03)]
        let padding = Int((b3 >> 1) & 0x01)
        guard bitrate > 0, rate > 0 else { return nil }
        return (bitrate, rate, 144_000 * bitrate / rate + padding)
    }

    func testEncodesRealMPEG1Layer3Frames() throws {
        let sampleRate = 44_100
        let encoder = try MP3Encoder(sampleRate: sampleRate, channels: 2, bitrateKbps: 192)
        let pcm = sine(frequency: 440, sampleRate: sampleRate, frames: sampleRate * 2)
        var output: [UInt8] = []
        let chunk = 4096
        var position = 0
        try pcm.withUnsafeBufferPointer { samples in
            while position < pcm.count {
                let count = min(chunk, pcm.count - position)
                let pointer = samples.baseAddress! + position
                output += try encoder.encode(left: pointer, right: pointer, frameCount: count)
                position += count
            }
        }
        output += try encoder.finish()
        let tag = encoder.infoTagFrame()
        XCTAssertFalse(tag.isEmpty)
        XCTAssertGreaterThanOrEqual(output.count, tag.count)
        output.replaceSubrange(0..<tag.count, with: tag)

        // Walk the frame chain: every frame must start with a valid MPEG-1 Layer III header.
        var offset = 0
        var frames = 0
        while offset < output.count {
            guard let header = parseFrameHeader(output, at: offset) else {
                XCTFail("Invalid frame header at byte \(offset)")
                return
            }
            XCTAssertEqual(header.sampleRate, sampleRate)
            XCTAssertEqual(header.bitrate, 192)
            offset += header.length
            frames += 1
        }
        XCTAssertEqual(offset, output.count, "Frames must exactly fill the stream")
        // 2 s at 1152 samples per frame ≈ 77 frames + info tag frame + delay/padding.
        XCTAssertGreaterThanOrEqual(frames, 77)
        XCTAssertLessThanOrEqual(frames, 81)

        // The info tag ("Info" for CBR) lives inside the first frame.
        let tagString = String(decoding: tag, as: UTF8.self)
        XCTAssertTrue(tagString.contains("Info") || tagString.contains("Xing"))
        XCTAssertTrue(tagString.contains("LAME"))

        if let path = ProcessInfo.processInfo.environment["LAMEKIT_TEST_OUTPUT"] {
            try Data(output).write(to: URL(fileURLWithPath: path))
        }
    }

    func testMonoEncoding() throws {
        let encoder = try MP3Encoder(sampleRate: 48_000, channels: 1, bitrateKbps: 128)
        let pcm = sine(frequency: 220, sampleRate: 48_000, frames: 48_000)
        var output = try pcm.withUnsafeBufferPointer { try encoder.encode(left: $0.baseAddress!, right: nil, frameCount: pcm.count) }
        output += try encoder.finish()
        XCTAssertGreaterThan(output.count, 10_000)
        XCTAssertNotNil(parseFrameHeader(output, at: 0))
    }

    func testRejectsUnsupportedConfiguration() {
        XCTAssertThrowsError(try MP3Encoder(sampleRate: 22_050 * 3, channels: 2, bitrateKbps: 192))
        XCTAssertThrowsError(try MP3Encoder(sampleRate: 44_100, channels: 3, bitrateKbps: 192))
        XCTAssertThrowsError(try MP3Encoder(sampleRate: 44_100, channels: 2, bitrateKbps: 100))
    }

    func testFinishTwiceThrows() throws {
        let encoder = try MP3Encoder(sampleRate: 44_100, channels: 2, bitrateKbps: 192)
        _ = try encoder.finish()
        XCTAssertThrowsError(try encoder.finish())
    }

    func testVersion() {
        XCTAssertTrue(MP3Encoder.lameVersion.hasPrefix("3.100"))
    }
}
