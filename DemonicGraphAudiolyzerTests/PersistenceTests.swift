#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("SwiftData-Presets", .serialized)
@MainActor
struct PersistenceTests {
    private static func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("presets.store")
    }

    private static func container(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema([SavedPreset.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("Eigenes Preset bleibt nach einem Neustart erhalten (alle Felder)")
    func survivesRestart() throws {
        let url = Self.storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var preset = SoundPreset(name: "ignoriert", summary: "Test", formula: "a*sin(b*x)+c",
                                 parameters: FormulaParameters(a: 2, b: 0.5, c: -1))
        preset.settings.mode = .waveform
        preset.settings.playXMin = -4
        preset.settings.playXMax = 6
        preset.settings.pitchRangeMode = .manual
        preset.settings.manualYLow = -3
        preset.settings.manualYHigh = 3
        preset.settings.sectionStart = -1
        preset.settings.sectionEnd = 2
        preset.settings.baseFrequency = 330
        preset.settings.frequencyLow = 98
        preset.settings.frequencyHigh = 1_760
        preset.settings.timbre = .triangle
        preset.settings.glideMilliseconds = 25
        preset.settings.duration = 37

        var savedID: UUID?
        do {
            let container = try Self.container(at: url)
            let context = ModelContext(container)
            let saved = try PresetStore.save(preset, name: "  Höllenklang  ", in: context)
            savedID = saved.id
        }

        // "Restart": a completely new container on the same store file.
        let container = try Self.container(at: url)
        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<SavedPreset>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.id == savedID)
        #expect(stored.name == "Höllenklang")
        #expect(stored.createdAt <= stored.modifiedAt)

        let restored = stored.preset
        #expect(restored.formula == preset.formula)
        #expect(restored.parameters == preset.parameters)
        #expect(restored.settings.mode == .waveform)
        #expect(restored.settings.playXMin == -4 && restored.settings.playXMax == 6)
        #expect(restored.settings.pitchRangeMode == .manual)
        #expect(restored.settings.manualYLow == -3 && restored.settings.manualYHigh == 3)
        #expect(restored.settings.sectionStart == -1 && restored.settings.sectionEnd == 2)
        #expect(restored.settings.baseFrequency == 330)
        #expect(restored.settings.frequencyLow == 98 && restored.settings.frequencyHigh == 1_760)
        #expect(restored.settings.timbre == .triangle)
        #expect(restored.settings.glideMilliseconds == 25)
        #expect(restored.settings.duration == 37)
    }

    @Test("Umbenennen, Überschreiben und Löschen")
    func renameOverwriteDelete() throws {
        let url = Self.storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try Self.container(at: url)
        let context = ModelContext(container)

        let saved = try PresetStore.save(BuiltInPresets.steps, name: "Stufen 1", in: context)
        let created = saved.createdAt
        try PresetStore.rename(saved, to: "Treppe", in: context)
        #expect(saved.name == "Treppe")

        var changed = BuiltInPresets.dampedWave
        changed.settings.duration = 99
        try PresetStore.overwrite(saved, with: changed, in: context)
        #expect(saved.formula == BuiltInPresets.dampedWave.formula)
        #expect(saved.duration == 99)
        #expect(saved.name == "Treppe", "Überschreiben behält den Namen")
        #expect(saved.createdAt == created)

        try PresetStore.delete(saved, in: context)
        #expect(try context.fetch(FetchDescriptor<SavedPreset>()).isEmpty)
    }

    @Test("Leere Namen werden ersetzt")
    func emptyName() {
        #expect(PresetStore.cleanedName("   ") == "Eigenes Preset")
        #expect(PresetStore.cleanedName(String(repeating: "x", count: 200)).count == 60)
    }

    @Test("Mitgelieferte Beispiele werden nicht in die Datenbank geschrieben")
    func builtInsAreNotPersisted() throws {
        let container = PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<SavedPreset>()).isEmpty)
        #expect(BuiltInPresets.classic.count == 7)
        #expect(Set(BuiltInPresets.all.map(\.id)).count == BuiltInPresets.all.count)
    }
}
#endif
