import Foundation
import SwiftData

/// A user preset stored locally with SwiftData (no CloudKit).
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

    // Sound mode
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
        return SoundPreset(id: id, name: name, summary: summary, formula: formula,
                           parameters: FormulaParameters(a: parameterA, b: parameterB, c: parameterC),
                           settings: settings)
    }
}

enum PersistenceController {
    /// Local SwiftData store. CloudKit is explicitly disabled.
    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([SavedPreset.self])
        let configuration = ModelConfiguration("DemonicPresets", schema: schema,
                                               isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A damaged store must not prevent the instrument from working: fall back to memory.
            let fallback = ModelConfiguration("DemonicPresetsFallback", schema: schema,
                                              isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
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
