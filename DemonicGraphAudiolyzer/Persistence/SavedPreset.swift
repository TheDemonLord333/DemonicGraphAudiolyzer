import Foundation
import SwiftData

/// Version 1 of the store: the user presets of the first app version (classic modes only).
/// Kept unchanged so that existing stores are recognised and migrated.
enum SavedPresetSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [SavedPreset.self] }

    @Model
    final class SavedPreset {
        @Attribute(.unique) var id: UUID
        var name: String
        var summary: String
        var formula: String
        var parameterA: Double
        var parameterB: Double
        var parameterC: Double
        var modeRaw: String
        var playXMin: Double
        var playXMax: Double
        var pitchRangeModeRaw: String
        var yLow: Double
        var yHigh: Double
        var sectionStart: Double
        var sectionEnd: Double
        var baseFrequency: Double
        var frequencyLow: Double
        var frequencyHigh: Double
        var timbreRaw: String
        var glideMilliseconds: Double
        var fadeMilliseconds: Double
        var levelDecibels: Double
        var duration: Double
        var createdAt: Date
        var modifiedAt: Date

        init(preset: SoundPreset, date: Date = Date()) {
            id = preset.id
            name = preset.name
            summary = preset.summary
            formula = preset.formula
            parameterA = preset.parameters.a
            parameterB = preset.parameters.b
            parameterC = preset.parameters.c
            modeRaw = preset.settings.mode.rawValue
            playXMin = preset.settings.playXMin
            playXMax = preset.settings.playXMax
            pitchRangeModeRaw = preset.settings.pitchRangeMode.rawValue
            yLow = preset.settings.manualYLow
            yHigh = preset.settings.manualYHigh
            sectionStart = preset.settings.sectionStart
            sectionEnd = preset.settings.sectionEnd
            baseFrequency = preset.settings.baseFrequency
            frequencyLow = preset.settings.frequencyLow
            frequencyHigh = preset.settings.frequencyHigh
            timbreRaw = preset.settings.timbre.rawValue
            glideMilliseconds = preset.settings.glideMilliseconds
            fadeMilliseconds = preset.settings.fadeMilliseconds
            levelDecibels = preset.settings.levelDecibels
            duration = preset.settings.duration
            createdAt = date
            modifiedAt = date
        }
    }
}

/// Version 2: adds the project of the formula synthesizer / pendulum mode (settings, voices,
/// parameters, display curves) as versioned JSON. Classic presets keep `projectData == nil`
/// and their exact previous meaning.
enum SavedPresetSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [SavedPreset.self] }

    @Model
    final class SavedPreset {
        @Attribute(.unique) var id: UUID
        var name: String
        var summary: String
        var formula: String

        // Parameters a, b, c
        var parameterA: Double
        var parameterB: Double
        var parameterC: Double

        // Sound mode ("graph", "waveform", "synthesizer", "pendulum")
        var modeRaw: String

        // x range (Graph vertonen)
        var playXMin: Double
        var playXMax: Double

        // Pitch range (Klangbereich)
        var pitchRangeModeRaw: String
        var yLow: Double
        var yHigh: Double

        // Waveform section (Formel als Klangwelle)
        var sectionStart: Double
        var sectionEnd: Double

        // Frequencies
        var baseFrequency: Double
        var frequencyLow: Double
        var frequencyHigh: Double

        // Timbre and shaping
        var timbreRaw: String
        var glideMilliseconds: Double
        var fadeMilliseconds: Double
        var levelDecibels: Double
        var duration: Double

        var createdAt: Date
        var modifiedAt: Date

        /// New in version 2: JSON of `SynthProject` (tempo, x mapping, definitions, parameters,
        /// voices with triggers, sources and formula roles). nil for classic presets.
        var projectData: Data?

        init(preset: SoundPreset, date: Date = Date()) {
            id = preset.id
            name = preset.name
            summary = preset.summary
            formula = preset.formula
            parameterA = preset.parameters.a
            parameterB = preset.parameters.b
            parameterC = preset.parameters.c
            modeRaw = preset.settings.mode.rawValue
            playXMin = preset.settings.playXMin
            playXMax = preset.settings.playXMax
            pitchRangeModeRaw = preset.settings.pitchRangeMode.rawValue
            yLow = preset.settings.manualYLow
            yHigh = preset.settings.manualYHigh
            sectionStart = preset.settings.sectionStart
            sectionEnd = preset.settings.sectionEnd
            baseFrequency = preset.settings.baseFrequency
            frequencyLow = preset.settings.frequencyLow
            frequencyHigh = preset.settings.frequencyHigh
            timbreRaw = preset.settings.timbre.rawValue
            glideMilliseconds = preset.settings.glideMilliseconds
            fadeMilliseconds = preset.settings.fadeMilliseconds
            levelDecibels = preset.settings.levelDecibels
            duration = preset.settings.duration
            createdAt = date
            modifiedAt = date
            projectData = Self.encode(preset.project)
        }

        /// Overwrites the stored configuration (keeps id, name and creation date).
        func update(from preset: SoundPreset, date: Date = Date()) {
            formula = preset.formula
            summary = preset.summary
            parameterA = preset.parameters.a
            parameterB = preset.parameters.b
            parameterC = preset.parameters.c
            modeRaw = preset.settings.mode.rawValue
            playXMin = preset.settings.playXMin
            playXMax = preset.settings.playXMax
            pitchRangeModeRaw = preset.settings.pitchRangeMode.rawValue
            yLow = preset.settings.manualYLow
            yHigh = preset.settings.manualYHigh
            sectionStart = preset.settings.sectionStart
            sectionEnd = preset.settings.sectionEnd
            baseFrequency = preset.settings.baseFrequency
            frequencyLow = preset.settings.frequencyLow
            frequencyHigh = preset.settings.frequencyHigh
            timbreRaw = preset.settings.timbre.rawValue
            glideMilliseconds = preset.settings.glideMilliseconds
            fadeMilliseconds = preset.settings.fadeMilliseconds
            levelDecibels = preset.settings.levelDecibels
            duration = preset.settings.duration
            projectData = Self.encode(preset.project)
            modifiedAt = date
        }

        /// Value representation used by the rest of the app.
        var preset: SoundPreset {
            var settings = SoundSettings()
            settings.mode = SoundMode(rawValue: modeRaw) ?? .graph
            settings.playXMin = playXMin
            settings.playXMax = playXMax
            settings.pitchRangeMode = PitchRangeMode(rawValue: pitchRangeModeRaw) ?? .automatic
            settings.manualYLow = yLow
            settings.manualYHigh = yHigh
            settings.sectionStart = sectionStart
            settings.sectionEnd = sectionEnd
            settings.baseFrequency = baseFrequency
            settings.frequencyLow = frequencyLow
            settings.frequencyHigh = frequencyHigh
            settings.timbre = Timbre(rawValue: timbreRaw) ?? .sine
            settings.glideMilliseconds = glideMilliseconds
            settings.fadeMilliseconds = fadeMilliseconds
            settings.levelDecibels = levelDecibels
            settings.duration = duration
            var project: SynthProject?
            if let projectData {
                project = try? JSONDecoder().decode(SynthProject.self, from: projectData)
            }
            if !settings.mode.isClassic, project == nil {
                // Unreadable project data must not break the preset list: fall back to the graph mode.
                settings.mode = .graph
            }
            return SoundPreset(id: id, name: name, summary: summary, formula: formula,
                               parameters: FormulaParameters(a: parameterA, b: parameterB, c: parameterC),
                               settings: settings, project: project)
        }

        private static func encode(_ project: SynthProject?) -> Data? {
            guard let project else { return nil }
            return try? JSONEncoder().encode(project)
        }
    }
}

/// Lightweight migration: version 2 only adds an optional attribute, all presets of version 1
/// are kept with all their values.
enum SavedPresetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SavedPresetSchemaV1.self, SavedPresetSchemaV2.self] }
    static var stages: [MigrationStage] { [migrateV1toV2] }

    static let migrateV1toV2 = MigrationStage.lightweight(fromVersion: SavedPresetSchemaV1.self, toVersion: SavedPresetSchemaV2.self)
}

/// The current model.
typealias SavedPreset = SavedPresetSchemaV2.SavedPreset

enum PersistenceController {
    /// Local SwiftData store with the versioned schema and migration plan. CloudKit is explicitly disabled.
    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema(versionedSchema: SavedPresetSchemaV2.self)
        let configuration = ModelConfiguration("DemonicPresets", schema: schema,
                                               isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: SavedPresetMigrationPlan.self, configurations: [configuration])
        } catch {
            // A damaged store must not prevent the instrument from working: fall back to memory.
            let fallback = ModelConfiguration("DemonicPresetsFallback", schema: schema,
                                              isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, migrationPlan: SavedPresetMigrationPlan.self, configurations: [fallback])
            } catch {
                fatalError("SwiftData-Container konnte nicht erstellt werden: \(error)")
            }
        }
    }
}

/// Preset operations on a model context (save, rename, update, delete).
@MainActor
enum PresetStore {
    @discardableResult
    static func save(_ preset: SoundPreset, name: String, in context: ModelContext) throws -> SavedPreset {
        var copy = preset
        copy.id = UUID()
        copy.name = cleanedName(name)
        let saved = SavedPreset(preset: copy)
        context.insert(saved)
        try context.save()
        return saved
    }

    static func rename(_ saved: SavedPreset, to name: String, in context: ModelContext) throws {
        saved.name = cleanedName(name)
        saved.modifiedAt = Date()
        try context.save()
    }

    static func overwrite(_ saved: SavedPreset, with preset: SoundPreset, in context: ModelContext) throws {
        saved.update(from: preset)
        try context.save()
    }

    static func delete(_ saved: SavedPreset, in context: ModelContext) throws {
        context.delete(saved)
        try context.save()
    }

    static func cleanedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Eigenes Preset" : String(trimmed.prefix(60))
    }
}
