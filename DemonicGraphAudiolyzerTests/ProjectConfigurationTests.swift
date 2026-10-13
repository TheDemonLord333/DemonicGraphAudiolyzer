import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

/// Static checks of the Xcode project and the app icon. They read the sources next to this
/// file (available on the Mac/simulator and in CI; skipped on a physical device).
@Suite("Projektkonfiguration und App-Icon")
struct ProjectConfigurationTests {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static let projectFile = repositoryRoot.appendingPathComponent("DemonicGraphAudiolyzer.xcodeproj/project.pbxproj")
    static let iconSet = repositoryRoot.appendingPathComponent("DemonicGraphAudiolyzer/Assets.xcassets/AppIcon.appiconset")
    static let originalIcon = repositoryRoot.appendingPathComponent("Dämonischer Audiograph mit Neonhörnern.png")
    static let sourcesAvailable = FileManager.default.fileExists(atPath: projectFile.path)

    static let bundleIdentifier = "me.thedemonlord333.DemonicGraphAudiolyzer"

    /// Build settings blocks of the app target configurations (Debug and Release).
    private func appTargetConfigurations() throws -> [String] {
        let lines = try String(contentsOf: Self.projectFile, encoding: .utf8).components(separatedBy: "\n")
        // 1. Ids listed in the configuration list of the app target.
        guard let listStart = lines.firstIndex(where: {
            $0.contains("Build configuration list for PBXNativeTarget \"DemonicGraphAudiolyzer\"") && $0.hasSuffix("= {")
        }) else { return [] }
        var ids: [String] = []
        for line in lines[(listStart + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("};") { break }
            if trimmed.hasSuffix("*/,"), let id = trimmed.split(separator: " ").first, id.count == 24 {
                ids.append(String(id))
            }
        }
        // 2. The corresponding XCBuildConfiguration blocks.
        return ids.compactMap { id in
            guard let start = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(id) && $0.hasSuffix("= {")
            }) else { return nil }
            var block: [String] = []
            for line in lines[start...] {
                block.append(line.trimmingCharacters(in: .whitespaces))
                if line == "\t\t};" { break }
            }
            return block.joined(separator: "\n")
        }
    }

    @Test("Bundle-ID in allen App-Build-Konfigurationen", .enabled(if: ProjectConfigurationTests.sourcesAvailable))
    func bundleIdentifierInAllConfigurations() throws {
        let configurations = try appTargetConfigurations()
        #expect(configurations.count == 2)
        for configuration in configurations {
            #expect(configuration.contains("PRODUCT_BUNDLE_IDENTIFIER = \(Self.bundleIdentifier);"))
            #expect(configuration.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"))
            #expect(configuration.contains("INFOPLIST_KEY_CFBundleDisplayName = \"Demonic Graph Audiolyzer\";"))
            #expect(configuration.contains("DEVELOPMENT_TEAM = LWL7HM459L;"))
        }
        #expect(configurations.contains { $0.contains("name = Debug;") })
        #expect(configurations.contains { $0.contains("name = Release;") })
    }

    @Test("Test-Targets haben eigene, abgeleitete Bundle-IDs", .enabled(if: ProjectConfigurationTests.sourcesAvailable))
    func testTargetIdentifiers() throws {
        let text = try String(contentsOf: Self.projectFile, encoding: .utf8)
        #expect(text.contains("PRODUCT_BUNDLE_IDENTIFIER = \(Self.bundleIdentifier)Tests;"))
        #expect(text.contains("PRODUCT_BUNDLE_IDENTIFIER = \(Self.bundleIdentifier)UITests;"))
        #expect(!text.contains("IPHONEOS_DEPLOYMENT_TARGET = 16"))
        #expect(text.contains("XCLocalSwiftPackageReference \"Packages/LameKit\""))
    }

    @Test("App-Icon: 1024 × 1024 px, deckend (kein Alphakanal), Originalmotiv", .enabled(if: ProjectConfigurationTests.sourcesAvailable))
    func appIcon() throws {
        let contentsData = try Data(contentsOf: Self.iconSet.appendingPathComponent("Contents.json"))
        let contents = try JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
        let images = contents?["images"] as? [[String: Any]] ?? []
        let universal = images.first { ($0["appearances"] == nil) && ($0["size"] as? String) == "1024x1024" }
        let fileName = try #require(universal?["filename"] as? String)

        let png = try Data(contentsOf: Self.iconSet.appendingPathComponent(fileName))
        let header = try PNGHeader(png)
        #expect(header.width == 1024 && header.height == 1024)
        #expect(header.colorType == 2, "Farbtyp 2 = RGB ohne Alphakanal")
        #expect(header.bitDepth == 8)

        // The original artwork stays in the repository and is square (motif not cropped).
        let original = try PNGHeader(Data(contentsOf: Self.originalIcon))
        #expect(original.width == original.height)
    }

    @Test("Laufzeit: Bundle-ID und Anzeigename der App")
    func runtimeBundle() {
        // In the hosted unit test bundle, Bundle.main is the app.
        guard Bundle.main.bundleIdentifier?.hasPrefix("me.thedemonlord333") == true else { return }
        #expect(Bundle.main.bundleIdentifier == Self.bundleIdentifier)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Demonic Graph Audiolyzer")
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        #expect(primary?["CFBundleIconName"] as? String == "AppIcon")
    }
}

/// Minimal PNG IHDR reader.
struct PNGHeader {
    let width: Int
    let height: Int
    let bitDepth: Int
    let colorType: Int

    struct InvalidPNG: Error {}

    init(_ data: Data) throws {
        let bytes = [UInt8](data.prefix(33))
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 33, Array(bytes[0..<8]) == signature, String(decoding: bytes[12..<16], as: UTF8.self) == "IHDR" else {
            throw InvalidPNG()
        }
        func uint32(_ offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        width = uint32(16)
        height = uint32(20)
        bitDepth = Int(bytes[24])
        colorType = Int(bytes[25])
    }
}
