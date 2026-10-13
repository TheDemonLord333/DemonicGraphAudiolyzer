import SwiftData
import SwiftUI

/// "Presets": shipped examples and own presets (SwiftData).
struct PresetsView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPreset.modifiedAt, order: .reverse) private var savedPresets: [SavedPreset]
    @AppStorage(PreferenceKey.lightGraph) private var lightGraph = false

    /// Called after a preset was loaded (switches to "Graph & Klang").
    var onLoad: () -> Void

    @State private var showSaveAlert = false
    @State private var newName = ""
    @State private var renaming: SavedPreset?
    @State private var renameText = ""
    @State private var deleting: SavedPreset?
    @State private var overwriting: SavedPreset?
    @State private var errorMessage: String?

    private var appearance: GraphAppearance { GraphAppearance(isLight: lightGraph) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DemonHeader(compact: true)
                    .padding(.top, 4)

                saveCard

                DemonSectionHeader(title: "Eigene Presets", systemImage: "tray.full")
                if savedPresets.isEmpty {
                    Text("Noch keine eigenen Presets. Speichere die aktuelle Formel mit allen Klangeinstellungen – sie bleiben auch nach einem Neustart erhalten.")
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(savedPresets) { saved in
                        PresetCard(preset: saved.preset,
                                   detail: "Geändert: " + saved.modifiedAt.formatted(.dateTime.locale(NumberText.locale).day().month().year().hour().minute()),
                                   appearance: appearance,
                                   onLoad: { load(saved.preset) },
                                   onRename: {
                                       renameText = saved.name
                                       renaming = saved
                                   },
                                   onOverwrite: { overwriting = saved },
                                   onDelete: { deleting = saved })
                    }
                }

                DemonSectionHeader(title: "Mitgelieferte Beispiele", systemImage: "sparkles")
                ForEach(BuiltInPresets.all) { preset in
                    PresetCard(preset: preset, detail: nil, appearance: appearance, onLoad: { load(preset) })
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.danger)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .alert("Preset speichern", isPresented: $showSaveAlert) {
            TextField("Name", text: $newName)
            Button("Speichern") { saveCurrent() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Speichert Formel, Parameter, Klangmodus, Bereiche, Frequenzen, Klangfarbe und Dauer.")
        }
        .alert("Preset umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") { renameSelected() }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Preset löschen?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible,
                            presenting: deleting) { preset in
            Button("„\(preset.name)“ löschen", role: .destructive) { delete(preset) }
            Button("Abbrechen", role: .cancel) { deleting = nil }
        } message: { _ in
            Text("Das Löschen kann nicht rückgängig gemacht werden.")
        }
        .confirmationDialog("Preset überschreiben?",
                            isPresented: Binding(get: { overwriting != nil }, set: { if !$0 { overwriting = nil } }),
                            titleVisibility: .visible,
                            presenting: overwriting) { preset in
            Button("„\(preset.name)“ mit aktuellen Einstellungen überschreiben") { overwrite(preset) }
            Button("Abbrechen", role: .cancel) { overwriting = nil }
        }
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aktuell: f(x) = \(model.formulaDisplayBody)")
                .font(.callout.weight(.semibold).monospaced())
                .foregroundStyle(DemonTheme.textPrimary)
                .lineLimit(2)
            Text("\(model.settings.mode.title) · \(NumberText.seconds(model.settings.duration))")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
            Button {
                newName = suggestedName
                showSaveAlert = true
            } label: {
                Label("Aktuelle Einstellungen speichern", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
            .disabled(model.parsedFormula == nil)
            .accessibilityIdentifier("savePresetButton")
        }
        .demonCard(crest: true)
    }

    private var suggestedName: String {
        "Preset \(savedPresets.count + 1)"
    }

    // MARK: Actions

    private func load(_ preset: SoundPreset) {
        model.apply(preset)
        onLoad()
    }

    private func saveCurrent() {
        do {
            var preset = model.currentPreset()
            preset.summary = model.settings.mode.title
            try PresetStore.save(preset, name: newName, in: context)
            errorMessage = nil
        } catch {
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func renameSelected() {
        guard let renaming else { return }
        do {
            try PresetStore.rename(renaming, to: renameText, in: context)
        } catch {
            errorMessage = "Umbenennen fehlgeschlagen: \(error.localizedDescription)"
        }
        self.renaming = nil
    }

    private func overwrite(_ saved: SavedPreset) {
        do {
            var preset = model.currentPreset(named: saved.name)
            preset.summary = model.settings.mode.title
            try PresetStore.overwrite(saved, with: preset, in: context)
        } catch {
            errorMessage = "Überschreiben fehlgeschlagen: \(error.localizedDescription)"
        }
        overwriting = nil
    }

    private func delete(_ saved: SavedPreset) {
        do {
            try PresetStore.delete(saved, in: context)
        } catch {
            errorMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
        deleting = nil
    }
}

/// One preset with mini graph, description and actions.
struct PresetCard: View {
    let preset: SoundPreset
    let detail: String?
    var appearance: GraphAppearance
    var onLoad: () -> Void
    var onRename: (() -> Void)?
    var onOverwrite: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MiniGraphView(formula: preset.formula, parameters: preset.parameters,
                          xRange: previewRange, section: preset.settings.mode == .waveform ? sectionRange : nil,
                          appearance: appearance)
                .frame(width: 92, height: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(DemonTheme.textPrimary)
                Text("f(x) = \(preset.formula)")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(DemonTheme.green)
                    .lineLimit(2)
                if !preset.summary.isEmpty {
                    Text(preset.summary)
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(facts)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DemonTheme.blurpleText)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(DemonTheme.textTertiary)
                }
                HStack(spacing: 8) {
                    Button(action: onLoad) {
                        Label("Laden", systemImage: "play.square")
                    }
                    .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
                    .accessibilityLabel("\(preset.name) laden")
                    .accessibilityIdentifier("loadPreset-\(preset.name)")

                    if onRename != nil || onDelete != nil {
                        Menu {
                            if let onRename {
                                Button(action: onRename) { Label("Umbenennen", systemImage: "pencil") }
                            }
                            if let onOverwrite {
                                Button(action: onOverwrite) { Label("Mit aktuellen Einstellungen überschreiben", systemImage: "square.and.arrow.down.on.square") }
                            }
                            if let onDelete {
                                Button(role: .destructive, action: onDelete) { Label("Löschen", systemImage: "trash") }
                            }
                        } label: {
                            Label("Mehr", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .foregroundStyle(DemonTheme.blurpleText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Aktionen für \(preset.name)")
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .demonCard(padding: 12)
        .accessibilityElement(children: .contain)
    }

    private var previewRange: ClosedRange<Double> {
        let settings = preset.settings
        if settings.mode == .waveform {
            let width = max(settings.sectionEnd - settings.sectionStart, 1e-6)
            return (settings.sectionStart - width * 0.1)...(settings.sectionEnd + width * 0.1)
        }
        return settings.playXMin...max(settings.playXMax, settings.playXMin + 1e-6)
    }

    private var sectionRange: ClosedRange<Double> {
        preset.settings.sectionStart...max(preset.settings.sectionEnd, preset.settings.sectionStart + 1e-6)
    }

    private var facts: String {
        let settings = preset.settings
        switch settings.mode {
        case .graph:
            return "\(settings.mode.title) · \(settings.timbre.title) · \(NumberText.seconds(settings.duration))"
        case .waveform:
            return "\(settings.mode.title) · \(NumberText.frequency(settings.baseFrequency)) · \(NumberText.seconds(settings.duration))"
        }
    }
}

/// Small graph preview, sampled in the background.
struct MiniGraphView: View {
    let formula: String
    let parameters: FormulaParameters
    let xRange: ClosedRange<Double>
    var section: ClosedRange<Double>?
    var appearance: GraphAppearance

    @State private var curve: SampledCurve?

    private var taskKey: String {
        "\(formula)|\(parameters.a)|\(parameters.b)|\(parameters.c)|\(xRange.lowerBound)|\(xRange.upperBound)"
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(appearance.background))
            guard let curve, curve.pointCount > 0 else { return }
            let yRange = GraphViewport.fittedYRange(for: curve, margin: 0.15)
            let viewport = GraphViewport(xMin: xRange.lowerBound, xMax: xRange.upperBound, yMin: yRange.lowerBound, yMax: yRange.upperBound)
            let transform = PlotTransform(viewport: viewport, rect: rect.insetBy(dx: 4, dy: 4))
            if let section {
                let band = CGRect(x: transform.x(section.lowerBound), y: 0,
                                  width: transform.x(section.upperBound) - transform.x(section.lowerBound), height: size.height)
                context.fill(Path(band), with: .color(appearance.highlightBand))
            }
            if (viewport.yMin...viewport.yMax).contains(0) {
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: transform.y(0)))
                axis.addLine(to: CGPoint(x: size.width, y: transform.y(0)))
                context.stroke(axis, with: .color(appearance.axis.opacity(0.6)), lineWidth: 0.8)
            }
            let path = GraphRenderer.curvePath(curve, transform: transform)
            if let glow = appearance.glow {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.stroke(path, with: .color(glow.opacity(0.5)), lineWidth: 3.5)
                }
            }
            context.stroke(path, with: .color(appearance.curve), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .clipShape(DemonPanelShape(cornerCut: 7, spike: 0))
        .overlay(DemonPanelShape(cornerCut: 7, spike: 0).stroke(DemonTheme.metalStroke, lineWidth: 1))
        .task(id: taskKey) {
            curve = await Self.sample(formula: formula, parameters: parameters, range: xRange)
        }
        .accessibilityHidden(true)
    }

    private static func sample(formula: String, parameters: FormulaParameters, range: ClosedRange<Double>) async -> SampledCurve? {
        guard case .success(let parsed) = ParsedFormula.parse(formula), range.upperBound > range.lowerBound else { return nil }
        let compiled = parsed.compiled(parameters: parameters)
        return await Task.detached(priority: .utility) {
            GraphSampler.sample({ compiled($0) }, over: range, options: GraphSampler.Options(baseSamples: 160))
        }.value
    }
}
