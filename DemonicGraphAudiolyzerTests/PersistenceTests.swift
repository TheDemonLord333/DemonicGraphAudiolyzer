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

    /// Current schema (version 2) with the migration plan – exactly as the app opens its store.
    private static func container(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: SavedPresetSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: SavedPresetMigrationPlan.self, configurations: [configuration])
    }

    /// A store as written by the first app version (schema version 1, no versioning information).
    private static func legacyContainer(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema([SavedPresetSchemaV1.SavedPreset.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("Migration: Presets der ersten Version bleiben mit allen Werten erhalten")
    func migrationFromVersionOne() throws {
        let url = Self.storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var preset = SoundPreset(name: "Alt", summary: "Version 1", formula: "asin(bx)+c",
                                 parameters: FormulaParameters(a: 1, b: 0.25, c: 0.5))
        preset.settings.mode = .graph
        preset.settings.playXMin = -3
        preset.settings.playXMax = 3
        preset.settings.timbre = .rich
        preset.settings.duration = 17
        let oldID = preset.id
        do {
            let container = try Self.legacyContainer(at: url)
            let context = ModelContext(container)
            context.insert(SavedPresetSchemaV1.SavedPreset(preset: preset))
            try context.save()
        }

        // Open the same file with the current schema and the migration plan.
        let container = try Self.container(at: url)
        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<SavedPreset>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.id == oldID)
        #expect(stored.name == "Alt")
        #expect(stored.projectData == nil)
        let restored = stored.preset
        #expect(restored.formula == "asin(bx)+c")
        #expect(restored.parameters == preset.parameters)
        #expect(restored.settings.mode == .graph, "Bedeutung unverändert")
        #expect(restored.settings.playXMin == -3 && restored.settings.playXMax == 3)
        #expect(restored.settings.timbre == .rich)
        #expect(restored.settings.duration == 17)
        #expect(restored.project == nil)
        // The formula still means the same.
        if case .success(let formula) = ParsedFormula.parse(restored.formula) {
            #expect(abs(formula.root.evaluate(x: 2, parameters: restored.parameters) - (asin(0.5) + 0.5)) < 1e-12)
        } else {
            Issue.record("Formel nicht mehr lesbar")
        }
    }

    @Test("Synthesizer-Projekte mit Stimmen werden gespeichert und wiederhergestellt")
    func synthProjectRoundTrip() throws {
        let url = Self.storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = SynthPresets.finalBoss
        do {
            let container = try Self.container(at: url)
            try PresetStore.save(original, name: "Boss", in: ModelContext(container))
        }
        let container = try Self.container(at: url)
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<SavedPreset>()).first)
        let restored = stored.preset
        #expect(restored.settings.mode == .synthesizer)
        #expect(restored.project == original.project)
        #expect(restored.project?.voices.count == original.project?.voices.count)
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
