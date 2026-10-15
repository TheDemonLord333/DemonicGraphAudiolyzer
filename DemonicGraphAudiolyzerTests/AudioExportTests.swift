#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

/// Real encoding with the shipped codecs, then decoding with AVFoundation.
@Suite("Audioexport: echte Codecs, Dekodierbarkeit, Dauer", .serialized)
struct AudioExportTests {
    private static func configuration(_ text: String = "sin(x) + 0.5sin(2x)", duration: Double = 3,
                                      mode: SoundMode = .graph, sampleRate: Double = 44_100) throws -> RenderConfiguration {
        guard case .success(let formula) = ParsedFormula.parse(text) else { throw ExportError.failed("Formel") }
        var settings = SoundSettings()
        settings.duration = duration
        settings.mode = mode
        settings.timbre = .rich
        return RenderConfiguration(formula: formula, parameters: FormulaParameters(), settings: settings, sampleRate: sampleRate)
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExportTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func decode(_ url: URL) throws -> (file: AVAudioFile, samples: [Float]) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ExportError.failed("Puffer")
        }
        try file.read(into: buffer)
        let channel = buffer.floatChannelData![0]
        return (file, Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
    }

    private static func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    @Test("Export ist mit dem richtigen Codec dekodierbar", arguments: ExportFormat.allCases)
    func exportDecodes(format: ExportFormat) throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = ExportOptions()
        options.format = format
        let configuration = try Self.configuration()
        let result = try AudioExporter.export(configuration: configuration, options: options,
                                              fileName: "Test \(format.title)", directory: directory) { _ in }

        #expect(result.url.pathExtension == format.fileExtension)
        #expect(result.byteCount > 1_000)
        #expect(!FileManager.default.fileExists(atPath: result.url.deletingLastPathComponent()
            .appendingPathComponent("unvollstaendig-Test \(format.title).\(format.fileExtension)").path))

        // Container signature – an MP3 is never a renamed WAV/M4A.
        let data = try Data(contentsOf: result.url)
        let bytes = [UInt8](data.prefix(12))
        switch format {
        case .wav:
            #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
            #expect(String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE")
        case .m4a:
            #expect(String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp")
        case .mp3:
            #expect(bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0, "MPEG audio frame sync")
            #expect((bytes[1] >> 1) & 0x03 == 1, "Layer III")
        }

        // Codec reported by AVFoundation.
        let verification = try AudioExporter.verify(result.url)
        switch format {
        case .wav: #expect(verification.codecName == "PCM")
        case .m4a: #expect(verification.codecName == "AAC")
        case .mp3: #expect(verification.codecName == "MP3")
        }
        #expect(verification.channels == 2)
        #expect(verification.sampleRate == 44_100)

        // Duration: exact for WAV, within codec priming/padding for AAC and MP3.
        let tolerance = format == .wav ? 1.0 / 44_100 : 0.12
        #expect(abs(verification.decodedDuration - 3) <= tolerance, "\(format): \(verification.decodedDuration) s")

        // The decoded signal has the energy of the rendered signal.
        let decoded = try Self.decode(result.url).samples
        let reference = PCMRenderer(plan: try SoundPlan(configuration: configuration)).renderAll()
        let decodedRMS = Self.rms(decoded[22_050..<88_200])
        let referenceRMS = Self.rms(reference[22_050..<88_200])
        #expect(abs(20 * log10(decodedRMS / referenceRMS)) < 1.0, "\(format): RMS \(decodedRMS) vs \(referenceRMS)")
    }

    @Test("Vorschau und Export verwenden identische PCM-Daten")
    func previewMatchesExport() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for mode in SoundMode.classic {
            let configuration = try Self.configuration("sin(4*x)exp(-0.2abs(x))", duration: 2, mode: mode)
            // Preview buffer exactly as the player receives it.
            guard case .success(let preview) = PreviewRenderer.render(configuration) else {
                Issue.record("Vorschau konnte nicht erzeugt werden")
                return
            }
            let previewBuffer = preview.buffer
            let previewSamples = Array(UnsafeBufferPointer(start: previewBuffer.floatChannelData![0], count: Int(previewBuffer.frameLength)))

            var options = ExportOptions()
            options.format = .wav
            options.wavBitDepth = .twentyFour
            let result = try AudioExporter.export(configuration: configuration, options: options,
                                                  fileName: "Vergleich", directory: directory) { _ in }
            let decoded = try Self.decode(result.url).samples
            #expect(decoded.count == previewSamples.count)
            var maximumDifference: Float = 0
            for index in 0..<min(decoded.count, previewSamples.count) {
                maximumDifference = max(maximumDifference, abs(decoded[index] - previewSamples[index]))
            }
            #expect(maximumDifference < 2.0 / 8_388_607, "\(mode): \(maximumDifference)")
        }
    }

    @Test("Wiederholung erzeugt keinen endlosen Export – genau ein Durchlauf")
    func exportIsOnePass() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = ExportOptions()
        options.format = .wav
        options.sampleRate = 48_000
        let result = try AudioExporter.export(configuration: try Self.configuration(duration: 1.5), options: options,
                                              fileName: "Ein Durchlauf", directory: directory) { _ in }
        let verification = try AudioExporter.verify(result.url)
        #expect(verification.sampleRate == 48_000)
        #expect(abs(verification.decodedDuration - 1.5) < 1.0 / 48_000)
    }

    @Test("Abbrechen entfernt temporäre Dateien")
    func cancellationCleansUp() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try Self.configuration(duration: 120)
        var options = ExportOptions()
        options.format = .mp3
        let task = Task.detached {
            try AudioExporter.export(configuration: configuration, options: options, fileName: "Abbruch", directory: directory) { _ in }
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Export hätte abgebrochen werden müssen")
        } catch let error as ExportError {
            #expect(error == .cancelled)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty, "Übrig: \(leftovers)")
    }

    @Test("120-Sekunden-Export blockiert den Main Actor nicht")
    @MainActor
    func longExportKeepsMainActorResponsive() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try Self.configuration(duration: 120)
        var options = ExportOptions()
        options.format = .mp3
        options.mp3Quality = .standard
        let progress = ProgressRecorder()
        let task = Task.detached(priority: .userInitiated) {
            defer { progress.finish() }
            return try AudioExporter.export(configuration: configuration, options: options, fileName: "Lang", directory: directory) { value in
                progress.record(value)
            }
        }
        var longestGap: TimeInterval = 0
        var last = Date()
        while !progress.isFinished {
            try await Task.sleep(nanoseconds: 20_000_000)
            let now = Date()
            longestGap = max(longestGap, now.timeIntervalSince(last))
            last = now
        }
        let result = try await task.value
        #expect(longestGap < 0.5, "Main Actor war \(longestGap) s blockiert")
        #expect(progress.values.count > 10)
        #expect(progress.values == progress.values.sorted(), "Fortschritt steigt monoton")
        let verification = try AudioExporter.verify(result.url)
        #expect(abs(verification.decodedDuration - 120) < 0.12)
    }
}

/// Thread-safe progress collector for the export test.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    private var finished = false

    func record(_ value: Double) {
        lock.lock(); storage.append(value); lock.unlock()
    }

    func finish() {
        lock.lock(); finished = true; lock.unlock()
    }

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    var values: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
#endif
