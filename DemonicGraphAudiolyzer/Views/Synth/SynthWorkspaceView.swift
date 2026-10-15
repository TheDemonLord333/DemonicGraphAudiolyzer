import SwiftUI

/// Cards of the synthesizer and pendulum modes below the transport: project (tempo, x mapping,
/// mix), voices, shared definitions and display curves, export.
struct SynthControlCards: View {
    @Environment(AudiolyzerModel.self) private var model
    var onExport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if model.mode == .pendulum {
                PendulumSettingsCard()
            }
            SynthProjectCard()
            VoiceListSection()
            ProjectFormulasCard()
            ExportEntryCard(onExport: onExport)
        }
    }
}

/// Tempo, length, meaning of x, level of the mix, lane layout, noise seed.
struct SynthProjectCard: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Projekt und Takt", systemImage: "metronome")
            DemonSlider(title: "Tempo", value: $model.project.tempo.bpm, range: TempoSettings.bpmRange, step: 1,
                        format: { NumberText.decimal($0, fractionDigits: 0) + " BPM" })
            DemonStepper(title: "Beats pro Takt", value: $model.project.tempo.beatsPerBar, range: TempoSettings.beatsPerBarRange)
            DemonStepper(title: "Takte", value: $model.project.tempo.bars, range: TempoSettings.barsRange)
            Text("Länge: \(NumberText.seconds(model.project.duration)) · \(Int(model.project.tempo.totalBeats)) Beats · ein Beat = \(NumberText.decimal(model.project.tempo.secondsPerBeat * 1000, fractionDigits: 0)) ms")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(DemonTheme.blurpleText)
            if let issue = model.project.tempo.validationIssue {
                DemonCaption(issue, warning: true)
            }

            DemonSubheader("Bedeutung von x")
            DemonSegmentedPicker(title: "Bedeutung von x", selection: $model.project.xMapping,
                                 options: XMapping.allCases.map { (value: $0, title: $0.shortTitle) })
            DemonCaption(xExplanation)
            if model.project.xMapping == .freeRange {
                HStack(spacing: 10) {
                    NumericField(title: "x von", value: $model.project.freeXMin)
                    NumericField(title: "x bis", value: $model.project.freeXMax)
                }
            }
            Button {
                model.showGuide(topic: "topic-x-mapping")
            } label: {
                Label("Sekunden, Beats und x erklärt", systemImage: "book.fill")
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))

            DemonSubheader("Mischung")
            DemonSlider(title: "Projektpegel (Spitze)", value: $model.project.masterLevelDecibels, range: SynthProject.masterLevelRange, step: 0.5,
                        format: { NumberText.decimal($0, fractionDigits: 1) + " dBFS" })
            DemonCaption("Die Stimmen werden als Signale addiert, mit 1/√(Anzahl hörbarer Stimmen) Reserve. Ein weicher Schutzbegrenzer hält die Spitzen unter −1 dBFS.")
            DemonSegmentedPicker(title: "Graphbahnen", selection: $model.project.laneLayout,
                                 options: LaneLayout.allCases.map { (value: $0, title: $0.title) })
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Startwert für Rauschen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DemonTheme.textSecondary)
                    Text(String(format: "%016llX", model.project.noiseSeed))
                        .font(.caption.monospaced())
                        .foregroundStyle(DemonTheme.textTertiary)
                }
                Spacer(minLength: 6)
                Button {
                    model.project.noiseSeed = UInt64.random(in: 1...UInt64.max)
                } label: {
                    Label("Neu", systemImage: "dice")
                }
                .buttonStyle(DemonChipButtonStyle())
                .accessibilityLabel("Neuen Startwert für Rauschen würfeln")
            }
            DemonCaption("Gleicher Startwert = gleiches Rauschen in Vorschau und Export.")
        }
        .demonCard()
        .accessibilityIdentifier("projectCard")
    }

    private var xExplanation: String {
        switch model.project.xMapping {
        case .seconds: return "x = t: x zählt die Sekunden seit dem Start."
        case .beats: return "x = beat: x zählt die Beats seit dem Start (unabhängig vom Tempo)."
        case .freeRange: return "x läuft während des Durchlaufs gleichmäßig von „x von“ bis „x bis“ (wie in „Graph vertonen“)."
        }
    }
}

/// All voices of the project with add and import actions.
struct VoiceListSection: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                DemonSectionHeader(title: "Stimmen (\(model.project.voices.count)/\(SynthProject.maximumVoices))", systemImage: "square.stack.3d.up")
                Button {
                    model.showGuide(topic: "topic-roles")
                } label: {
                    Image(systemName: "book.fill")
                        .foregroundStyle(DemonTheme.neonGreen)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anleitung zu den Formelrollen öffnen")
            }
            .padding(.horizontal, 4)
            if model.project.voices.isEmpty {
                DemonCaption("Das Projekt hat keine Stimme. Füge eine hinzu oder übernimm Stimmen aus einem Preset.")
                    .padding(.horizontal, 4)
            }
            ForEach(model.project.voices) { voice in
                VoiceCard(voiceID: voice.id, startExpanded: model.project.voices.count == 1)
            }
            HStack(spacing: 8) {
                Button {
                    model.addVoice()
                } label: {
                    Label("Stimme hinzufügen", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
                .disabled(!model.canAddVoice)
                .accessibilityIdentifier("addVoice")

                Menu {
                    ForEach(PresetCategory.allCases.filter { $0 != .classic }) { category in
                        Section(category.title) {
                            ForEach(SynthPresets.all.filter { $0.category == category }) { preset in
                                Button(preset.name) { model.importVoices(from: preset) }
                            }
                        }
                    }
                } label: {
                    Label("Aus Preset", systemImage: "square.and.arrow.down.on.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(model.canAddVoice ? DemonTheme.blurpleText : DemonTheme.textTertiary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(DemonPanelShape(cornerCut: 8, spike: 0).fill(Color.black.opacity(0.35)))
                        .overlay(DemonPanelShape(cornerCut: 8, spike: 0).stroke(DemonTheme.metalMid.opacity(0.85), lineWidth: 1.1))
                }
                .disabled(!model.canAddVoice)
                .accessibilityLabel("Stimmen aus einem Preset hinzufügen")
                .accessibilityIdentifier("importVoices")
            }
            if !model.canAddVoice {
                DemonCaption("Höchstens \(SynthProject.maximumVoices) Stimmen pro Projekt.")
            }
        }
    }
}

/// Shared definitions and parameters of the project, and display-only curves.
struct ProjectFormulasCard: View {
    @Environment(AudiolyzerModel.self) private var model
    @State private var isExpanded = false
    @State private var advanced = true

    var body: some View {
        @Bindable var model = model
        DemonDisclosure(title: "Gemeinsame Definitionen und Anzeigekurven", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                FormulaFieldEditor(text: $model.project.definitions,
                                   title: "Gemeinsame Definitionen",
                                   meaning: "Definitionen · gelten in allen Stimmen (Listen, Zwischenwerte, Hilfsfunktionen)",
                                   meaningIcon: "list.bullet.rectangle",
                                   context: .synth,
                                   definitions: [model.project.parameters.map(\.definitionLine).joined(separator: "\n")],
                                   error: model.issues(voiceID: nil, field: .projectDefinitions).first?.error,
                                   advanced: $advanced,
                                   outputLabel: "",
                                   requiresOutput: false,
                                   fieldIdentifier: "projectDefinitionsField",
                                   onHelp: { topic in model.showGuide(topic: topic ?? "topic-helper-functions") })
                SynthParameterListEditor(parameters: $model.project.parameters,
                                         issues: model.issues(voiceID: nil, field: .projectParameters),
                                         identifierPrefix: "projectParameter",
                                         onHelp: { model.showGuide(topic: "topic-parameters") })
                DisplayCurvesEditor()
            }
        }
        .demonCard()
    }
}

/// Curves that are only drawn (explanations such as an envelope or a reference signal).
struct DisplayCurvesEditor: View {
    @Environment(AudiolyzerModel.self) private var model
    @State private var advanced = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DemonSubheader("Anzeigekurven")
                Spacer()
                Button {
                    model.showGuide(topic: "topic-display")
                } label: {
                    Image(systemName: "book.fill")
                        .foregroundStyle(DemonTheme.neonGreen)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anleitung zu Anzeigekurven öffnen")
            }
            DemonCaption("Anzeigekurven werden nur gezeichnet, nie hörbar. Einheit „Signal“ erscheint im Audioausschnitt mit Millisekundenachse.")
            ForEach($model.project.displayCurves) { $curve in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 8) {
                        DemonTextField(title: "Name", text: $curve.name)
                        Button(role: .destructive) {
                            let id = curve.id
                            model.updateProject { $0.displayCurves.removeAll { $0.id == id } }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(DemonTheme.danger)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Anzeigekurve \(curve.name) entfernen")
                    }
                    DemonMenuPicker(title: "Einheit", selection: $curve.unit,
                                    options: DisplayCurve.Unit.allCases.map { (value: $0, title: $0.title) })
                    DemonMenuPicker(title: "Farbe", selection: $curve.color,
                                    options: VoiceColor.allCases.map { (value: $0, title: $0.title) })
                    DemonMenuPicker(title: "Bezug", selection: $curve.voiceID,
                                    options: [(value: UUID?.none, title: "Nur Projekt")]
                                        + model.project.voices.map { (value: Optional($0.id), title: $0.name) })
                    FormulaFieldEditor(text: $curve.formula,
                                       title: curve.name,
                                       meaning: "Anzeige · \(curve.unit.title) (nicht hörbar)",
                                       meaningIcon: "eye",
                                       context: .synth,
                                       error: model.issues(voiceID: nil, field: .display(curve.id)).first?.error,
                                       advanced: $advanced,
                                       outputLabel: curve.name.isEmpty ? "y" : curve.name,
                                       fieldIdentifier: "displayCurveField",
                                       onHelp: { topic in model.showGuide(topic: topic ?? "topic-display") })
                }
                .demonInset(tint: curve.color.color.opacity(0.6))
            }
            Button {
                let used = Set(model.project.displayCurves.map(\.color))
                let color = VoiceColor.allCases.reversed().first { !used.contains($0) } ?? .violet
                model.updateProject {
                    $0.displayCurves.append(DisplayCurve(name: "Anzeige \($0.displayCurves.count + 1)", formula: "exp(-4*localBeat)",
                                                         color: color, unit: .gain))
                }
            } label: {
                Label("Anzeigekurve hinzufügen", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(model.project.displayCurves.count >= 6)
        }
    }
}
