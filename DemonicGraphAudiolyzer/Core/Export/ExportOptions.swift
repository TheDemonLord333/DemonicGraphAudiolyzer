import Foundation

enum ExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp3
    case wav
    case m4a

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp3: return "MP3"
        case .wav: return "WAV"
        case .m4a: return "M4A"
        }
    }

    var fileExtension: String { rawValue }

    var detail: String {
        switch self {
        case .mp3: return "MPEG-1 Layer III (LAME), überall abspielbar"
        case .wav: return "Unkomprimiertes PCM, verlustfrei"
        case .m4a: return "AAC im MPEG-4-Container, klein und hochwertig"
        }
    }

    /// Uniform type identifier string (mapped to `UTType` in the UI layer).
    var typeIdentifier: String {
        switch self {
        case .mp3: return "public.mp3"
        case .wav: return "com.microsoft.waveform-audio"
        case .m4a: return "com.apple.m4a-audio"
        }
    }
}

enum WAVBitDepth: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sixteen = 16
    case twentyFour = 24

    var id: Int { rawValue }
    var title: String { "\(rawValue) Bit" }
    var bytesPerSample: Int { rawValue / 8 }
}

enum MP3EncodingQuality: Int, Codable, CaseIterable, Identifiable, Sendable {
    /// LAME -q 0 … 9; lower is better and slower.
    case best = 0
    case high = 2
    case standard = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .best: return "Maximal"
        case .high: return "Hoch"
        case .standard: return "Schnell"
        }
    }
}

/// User-selectable export options. Duration comes from the render configuration.
struct ExportOptions: Codable, Equatable, Sendable {
    var format: ExportFormat = .mp3
    var sampleRate: Double = 44_100
    var wavBitDepth: WAVBitDepth = .sixteen
    var aacBitrate: Int = 192
    var mp3Bitrate: Int = 192
    var mp3Quality: MP3EncodingQuality = .high
    var channels: Int = 2

    static let sampleRates: [Double] = [44_100, 48_000]
    static let aacBitrates: [Int] = [128, 160, 192, 256, 320]
    static let mp3Bitrates: [Int] = [128, 160, 192, 224, 256, 320]

    /// Short human-readable description, e.g. "MP3 · 192 kbit/s · 44,1 kHz".
    var summary: String {
        let rate = sampleRate == 44_100 ? "44,1 kHz" : "48 kHz"
        switch format {
        case .wav: return "WAV · \(wavBitDepth.rawValue) Bit · \(rate)"
        case .m4a: return "M4A (AAC) · \(aacBitrate) kbit/s · \(rate)"
        case .mp3: return "MP3 · \(mp3Bitrate) kbit/s · \(rate)"
        }
    }

    /// Rough size estimate in bytes for a given duration.
    func estimatedSize(duration: Double) -> Int {
        switch format {
        case .wav: return Int(duration * sampleRate) * channels * wavBitDepth.bytesPerSample + 44
        case .m4a: return Int(duration * Double(aacBitrate) * 1000 / 8)
        case .mp3: return Int(duration * Double(mp3Bitrate) * 1000 / 8)
        }
    }
}

enum ExportFileName {
    /// Removes characters that are not allowed or awkward in file names.
    static func sanitized(_ name: String, fallback: String = "Demonic Graph") -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let limited = String(trimmed.prefix(80))
        return limited.isEmpty ? fallback : limited
    }
}
