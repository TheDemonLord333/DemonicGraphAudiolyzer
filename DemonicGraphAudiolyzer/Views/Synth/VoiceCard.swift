import SwiftUI

/// Sections of a voice card.
enum VoiceSection: String, CaseIterable, Identifiable {
    case sound, pitch, amplitude, trigger, definitions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sound: return "Klang"
        case .pitch: return "Tonhöhe"
        case .amplitude: return "Amplitude"
        case .trigger: return "Auslöser"
        case .definitions: return "Definitionen"
        }
    }

    var icon: String {
        switch self {
        case .sound: return "waveform"
        case .pitch: return "music.note"
        case .amplitude: return "speaker.wave.2"
        case .trigger: return "metronome"
        case .definitions: return "list.bullet.rectangle"
        }
    }

    var fields: [SynthField] {
        switch self {
        case .sound: return [.signal]
        case .pitch: return [.pitch]
        case .amplitude: return [.amplitude]
        case .trigger: return [.rate]
        case .definitions: return [.voiceDefinitions, .voiceParameters]
        }
    }
}

/// One voice: name, colour, visibility, mute/solo, level and pan, trigger, sound source,
/// pitch with unit, amplitude, own definitions and parameters, actions.
struct VoiceCard: View {
    @Environment(AudiolyzerModel.self) private var model
    let voiceID: UUID
    @State private var isExpanded: Bool
    @State private var section: VoiceSection = .pitch
    @State private var confirmDelete = false

    init(voiceID: UUID, startExpanded: Bool = false) {
        self.voiceID = voiceID
        _isExpanded = State(initialValue: startExpanded)
    }

    private var voice: Binding<SynthVoice> {
        Binding(get: { model.voice(voiceID) ?? SynthVoice() },
                set: { newValue in model.updateVoice(voiceID) { $0 = newValue } })
    }

    private var index: Int {
        model.project.voices.firstIndex { $0.id == voiceID } ?? 0
    }

    var body: some View {
        let current = voice.wrappedValue
        VStack(alignment: .leading, spacing: 10) {
            header(current)
            if !current.summary.isEmpty {
                DemonCaption(current.summary)
            }
            Text(facts(current))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.blurpleText)
                .fixedSize(horizontal: false, vertical: true)
            if errorCount > 0 && !isExpanded {
                Label("\(errorCount) Fehler in dieser Stimme – aufklappen zum Bearbeiten", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DemonTheme.danger)
            }
            if isExpanded {
                sectionChips(current)
                switch section {
                case .sound: VoiceSoundSection(voice: voice)
                case .pitch: VoicePitchSection(voice: voice)
                case .amplitude: VoiceAmplitudeSection(voice: voice)
                case .trigger: VoiceTriggerSection(voice: voice)
                case .definitions: VoiceDefinitionsSection(voice: voice)
                }
                actions
            }
        }
        .demonCard(padding: 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(current.color.color)
                .frame(width: 3)
                .padding(.vertical, 14)
                .shadow(color: current.color.color.opacity(0.8), radius: 4)
                .accessibilityHidden(true)
        }
        .confirmationDialog("Stimme löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("„\(current.name)“ löschen", role: .destructive) { model.removeVoice(voiceID) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Stimme und ihre Anzeigekurven werden aus dem Projekt entfernt.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceCard-\(index)")
    }

    // MARK: Header

    private func header(_ current: SynthVoice) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(VoiceColor.allCases) { color in
                    Button {
                        voice.wrappedValue.color = color
                    } label: {
                        if color == current.color {
                            Label(color.title, systemImage: "checkmark")
                        } else {
                            Text(color.title)
                        }
                    }
                }
            } label: {
                VoiceColorDot(color: current.color, size: 16)
                    .frame(minWidth: 36, minHeight: 44)
            }
            .accessibilityLabel("Farbe: \(current.color.title)")

            TextField("Name", text: voice.name)
                .font(.headline.weight(.heavy))
                .foregroundStyle(DemonTheme.textPrimary)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .frame(minHeight: 44)
                .accessibilityLabel("Name der Stimme")
                .accessibilityIdentifier("voiceName-\(index)")

            toggleButton(isOn: current.isVisible, on: "eye.fill", off: "eye.slash",
                         label: current.isVisible ? "Im Graphen sichtbar" : "Im Graphen ausgeblendet") {
                voice.wrappedValue.isVisible.toggle()
            }
            toggleButton(isOn: current.isMuted, on: "speaker.slash.fill", off: "speaker.wave.2",
                         label: current.isMuted ? "Stumm" : "Hörbar", activeTint: DemonTheme.danger) {
                voice.wrappedValue.isMuted.toggle()
            }
            .accessibilityIdentifier("mute-\(index)")
            Button {
                voice.wrappedValue.isSolo.toggle()
            } label: {
                Text("S")
                    .font(.subheadline.weight(.black))
                    .frame(minWidth: 30, minHeight: 44)
            }
            .buttonStyle(DemonChipButtonStyle(isActive: current.isSolo))
            .accessibilityLabel("Solo")
            .accessibilityValue(current.isSolo ? "ein" : "aus")
            .accessibilityIdentifier("solo-\(index)")

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DemonTheme.green)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(minWidth: 36, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Stimme zuklappen" : "Stimme bearbeiten")
            .accessibilityIdentifier("expandVoice-\(index)")
        }
    }

    private func toggleButton(isOn: Bool, on: String, off: String, label: String, activeTint: Color = DemonTheme.neonGreen,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? on : off)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? activeTint : DemonTheme.textTertiary)
                .frame(minWidth: 34, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sectionChips(_ current: SynthVoice) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(VoiceSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.icon)
                            Text(item.title)
                            if hasIssues(in: item) {
                                Circle().fill(DemonTheme.danger).frame(width: 7, height: 7)
                            }
                        }
                        .font(.caption.weight(.bold))
                    }
                    .buttonStyle(DemonChipButtonStyle(isActive: section == item))
                    .accessibilityLabel(item.title + (hasIssues(in: item) ? ", enthält Fehler" : ""))
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                    .accessibilityIdentifier("voiceSection-\(item.rawValue)-\(index)")
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                model.duplicateVoice(voiceID)
            } label: {
                Label("Duplizieren", systemImage: "plus.square.on.square")
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(!model.canAddVoice)
            Spacer(minLength: 0)
            Button {
                model.moveVoice(voiceID, by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(index == 0)
            .accessibilityLabel("Nach oben")
            Button {
                model.moveVoice(voiceID, by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(index >= model.project.voices.count - 1)
            .accessibilityLabel("Nach unten")
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.danger))
            .accessibilityLabel("Stimme löschen")
            .accessibilityIdentifier("deleteVoice-\(index)")
        }
    }

    // MARK: Status

    private var errorCount: Int {
        VoiceSection.allCases.flatMap(\.fields).reduce(0) { $0 + model.issues(voiceID: voiceID, field: $1).count }
    }

    private func hasIssues(in section: VoiceSection) -> Bool {
        section.fields.contains { !model.issues(voiceID: voiceID, field: $0).isEmpty }
    }

    private func facts(_ voice: SynthVoice) -> String {
        var parts = ["Auslöser: \(voice.trigger.kind.title)", voice.source.kind.title]
        if voice.source.kind == .oscillator { parts[1] += " (\(voice.source.waveform.title))" }
        if voice.source.kind == .drum { parts[1] += " (\(voice.source.drum.title))" }
        if voice.source.kind.usesPitch && voice.source.kind != .riser {
            parts.append("Tonhöhe in \(voice.pitch.unit.title)")
        }
        parts.append("\(NumberText.decimal(voice.volumeDecibels, fractionDigits: 1)) dB")
        if voice.isMuted { parts.append("stumm") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shared helpers

/// Formula definitions that the readable notation of a voice formula needs.
@MainActor
private func definitionSources(_ model: AudiolyzerModel, _ voice: SynthVoice) -> [String] {
    [model.project.parameters.map(\.definitionLine).joined(separator: "\n"),
     model.project.definitions,
     voice.parameters.map(\.definitionLine).joined(separator: "\n"),
     voice.definitions].filter { !$0.trimmed.isEmpty }
}

// MARK: - Sound

struct VoiceSoundSection: View {
    @Environment(AudiolyzerModel.self) private var model
    @Binding var voice: SynthVoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSlider(title: "Lautstärke", value: $voice.volumeDecibels, range: SynthVoice.volumeRange, step: 0.5,
                        format: { NumberText.decimal($0, fractionDigits: 1) + " dB" })
            DemonSlider(title: "Panorama", value: $voice.pan, range: -1...1, step: 0.05,
                        format: { value in
                            if abs(value) < 0.025 { return "Mitte" }
                            return (value < 0 ? "L " : "R ") + NumberText.decimal(abs(value) * 100, fractionDigits: 0) + " %"
                        })
            DemonMenuPicker(title: "Klangquelle", selection: $voice.source.kind,
                            options: VoiceSource.Kind.allCases.map { (value: $0, title: $0.title) },
                            identifier: "sourceKind")
            switch voice.source.kind {
            case .oscillator:
                oscillator
            case .periodicFormula, .directSignal:
                signal
            case .drum:
                drum
            case .riser:
                riser
            }
        }
    }

    private var oscillator: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonMenuPicker(title: "Wellenform", selection: $voice.source.waveform,
                            options: OscillatorWaveform.allCases.map { (value: $0, title: $0.title) })
            DemonStepper(title: "Unisono-Oszillatoren", value: $voice.source.unison, range: VoiceSource.unisonRange)
            if voice.source.unison > 1 {
                DemonSlider(title: "Verstimmung", value: $voice.source.detuneCents, range: 0...50, step: 0.5,
                            format: { "± " + NumberText.decimal($0, fractionDigits: 1) + " Cent" })
            }
            Toggle("Phase bei jedem Auslösen neu starten", isOn: $voice.source.resetPhaseOnTrigger)
                .toggleStyle(DemonToggleStyle())
                .font(.subheadline.weight(.semibold))
            DemonCaption("Bandbegrenzt erzeugt: Sägezahn, Rechteck und obertonreiche Wellen enthalten nur Teiltöne unterhalb der Nyquist-Grenze.")
        }
    }

    private var signal: some View {
        let isPeriodic = voice.source.kind == .periodicFormula
        return VStack(alignment: .leading, spacing: 10) {
            FormulaFieldEditor(text: $voice.source.signalFormula,
                               title: "Audiosignal",
                               meaning: isPeriodic
                                   ? "Audiosignal · eine Periode: x läuft je Schwingung von \(NumberText.compact(voice.source.sectionStart)) bis \(NumberText.compact(voice.source.sectionEnd)); Tonhöhe aus der Tonhöhenformel"
                                   : "Audiosignal · Abtastwerte direkt (etwa −1 … 1) aus t, beat, localTime …",
                               meaningIcon: "waveform.path",
                               context: .synth,
                               definitions: definitionSources(model, voice),
                               error: model.issues(voiceID: voice.id, field: .signal).first?.error,
                               advanced: $voice.useAdvancedEditor,
                               outputLabel: "Signal",
                               liveCase: { model.liveActiveCase(voiceID: voice.id, role: .signal) },
                               fieldIdentifier: "signalField",
                               onHelp: { topic in model.showGuide(topic: topic ?? "topic-signal") })
            if isPeriodic {
                HStack(spacing: 10) {
                    NumericField(title: "Abschnitt von", value: $voice.source.sectionStart)
                    NumericField(title: "bis", value: $voice.source.sectionEnd)
                }
            }
            DemonSegmentedPicker(title: "Überabtastung", selection: $voice.source.oversampling,
                                 options: VoiceSource.oversamplingOptions.map { (value: $0, title: "\($0)×") })
            DemonCaption("Überabtastung: Die Formel wird mehrfach pro Abtastwert berechnet und vor dem Herunterrechnen tiefpassgefiltert. Höher = weniger Aliasing bei scharfen Kanten, mehr Rechenzeit.")
            DemonSegmentedPicker(title: "Normalisierung", selection: $voice.source.normalization,
                                 options: SignalNormalization.allCases.map { (value: $0, title: $0.title) })
            DemonCaption(voice.source.normalization == .automatic
                         ? "Gleichanteil wird entfernt und die Spitze vor der Wiedergabe auf 1 skaliert."
                         : "Gleichanteil wird entfernt; die Werte werden nicht skaliert (der Schutzbegrenzer fängt Spitzen ab).")
        }
    }

    private var drum: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonSegmentedPicker(title: "Instrument", selection: $voice.source.drum,
                                 options: DrumKind.allCases.map { (value: $0, title: $0.title) })
            DemonCaption(voice.source.drum.explanation)
            DemonSlider(title: "Abklingzeit", value: $voice.source.decayMilliseconds, range: 20...2000, logarithmic: true,
                        format: { NumberText.decimal($0, fractionDigits: 0) + " ms" })
            DemonSlider(title: voice.source.drum == .kick ? "Klick" : (voice.source.drum == .hihat ? "Helligkeit" : "Ton / Rauschen"),
                        value: $voice.source.tone, range: 0...1, step: 0.01,
                        format: { NumberText.decimal($0 * 100, fractionDigits: 0) + " %" })
            Button {
                model.showGuide(topic: "topic-drums")
            } label: {
                Label("Wie die Schlaginstrumente entstehen", systemImage: "book.fill")
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
        }
    }

    private var riser: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonStepper(title: "Teiltöne (Oktavabstand)", value: $voice.source.riserPartials, range: VoiceSource.riserPartialsRange)
            DemonSlider(title: "Beats pro Oktave", value: $voice.source.riserCycleBeats, range: 0.5...32, step: 0.5,
                        format: { NumberText.compact($0) + " Beats" })
            DemonSlider(title: "Tiefster Teilton", value: $voice.source.riserLowestFrequency, range: 16...440, logarithmic: true,
                        format: { NumberText.frequency($0) })
            DemonSegmentedPicker(title: "Richtung", selection: $voice.source.riserRising,
                                 options: [(value: true, title: "Steigend"), (value: false, title: "Fallend")])
            DemonCaption("Psychoakustische Illusion: Die Teiltöne steigen gemeinsam, werden oben ausgeblendet und unten wieder eingeblendet. Die Frequenzen steigen nicht unbegrenzt.")
            Button {
                model.showGuide(topic: "topic-riser")
            } label: {
                Label("Endless Riser erklärt", systemImage: "book.fill")
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
        }
    }
}

// MARK: - Pitch

struct VoicePitchSection: View {
    @Environment(AudiolyzerModel.self) private var model
    @Binding var voice: SynthVoice

    var body: some View {
        if !voice.source.kind.usesPitch || voice.source.kind == .riser {
            DemonCaption(voice.source.kind == .riser
                         ? "Der Endless Riser bestimmt seine Teiltöne selbst (Einstellungen unter „Klang“)."
                         : "Ein direktes Signal erzeugt seine Schwingung selbst und nutzt keine Tonhöhenformel.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                DemonMenuPicker(title: "Einheit der Formel", selection: $voice.pitch.unit,
                                options: PitchUnit.allCases.map { (value: $0, title: $0.title) },
                                identifier: "pitchUnit")
                FormulaFieldEditor(text: $voice.pitch.formula,
                                   title: "Tonhöhe",
                                   meaning: "Tonhöhe · \(voice.pitch.unit.meaning)",
                                   meaningIcon: "music.note",
                                   context: .synth,
                                   definitions: definitionSources(model, voice),
                                   error: model.issues(voiceID: voice.id, field: .pitch).first?.error,
                                   advanced: $voice.useAdvancedEditor,
                                   outputLabel: outputLabel,
                                   liveCase: { model.liveActiveCase(voiceID: voice.id, role: .pitch) },
                                   fieldIdentifier: "pitchField",
                                   onHelp: { topic in model.showGuide(topic: topic ?? "topic-pitch-units") })
                switch voice.pitch.unit {
                case .semitones, .octaves:
                    DemonSlider(title: "Grundfrequenz", value: $voice.pitch.baseFrequency, range: PitchControl.baseFrequencyRange,
                                logarithmic: true, format: { NumberText.frequency($0) })
                case .hertz:
                    DemonCaption("Die Formel liefert direkt Hertz. Werte ≤ 0 oder undefinierte Stellen sind stumm; über 45 % der Abtastrate wird begrenzt.")
                case .normalized:
                    normalized
                }
                if voice.pitch.unit != .hertz {
                    DemonMenuPicker(title: "Tonleiter-Quantisierung", selection: $voice.pitch.quantization,
                                    options: ScaleQuantization.allCases.map { (value: $0, title: $0.title) })
                    if voice.pitch.quantization != .none {
                        DemonCaption("Rastet die Tonhöhe auf Töne der Tonleiter über der Grundfrequenz ein – anders als floor/round, die nur Zahlen runden.")
                    }
                }
                DemonSlider(title: "Gleiten (Glide)", value: $voice.pitch.glideMilliseconds, range: PitchControl.glideRange, step: 5,
                            format: { NumberText.decimal($0, fractionDigits: 0) + " ms" })
            }
        }
    }

    private var outputLabel: String {
        switch voice.pitch.unit {
        case .hertz: return "f"
        case .semitones: return "s"
        case .octaves: return "o"
        case .normalized: return "y"
        }
    }

    private var normalized: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Graphbereich automatisch bestimmen", isOn: $voice.pitch.automaticRange)
                .toggleStyle(DemonToggleStyle())
                .font(.subheadline.weight(.semibold))
            if !voice.pitch.automaticRange {
                HStack(spacing: 10) {
                    NumericField(title: "yLow", value: $voice.pitch.yLow)
                    NumericField(title: "yHigh", value: $voice.pitch.yHigh)
                }
            }
            HStack(spacing: 10) {
                NumericField(title: "fLow (Hz)", value: $voice.pitch.frequencyLow, range: 8...20_000)
                NumericField(title: "fHigh (Hz)", value: $voice.pitch.frequencyHigh, range: 8...20_000)
            }
            DemonCaption("Wie „Graph vertonen“: u = (y − yLow)/(yHigh − yLow), f = fLow · (fHigh/fLow)^u.")
        }
    }
}

// MARK: - Amplitude

struct VoiceAmplitudeSection: View {
    @Environment(AudiolyzerModel.self) private var model
    @Binding var voice: SynthVoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSegmentedPicker(title: "Skala", selection: $voice.amplitude.scale,
                                 options: AmplitudeScale.allCases.map { (value: $0, title: $0.title) })
            FormulaFieldEditor(text: $voice.amplitude.formula,
                               title: "Amplitude",
                               meaning: "Amplitude · \(voice.amplitude.scale.meaning)",
                               meaningIcon: "speaker.wave.2",
                               context: .synth,
                               definitions: definitionSources(model, voice),
                               error: model.issues(voiceID: voice.id, field: .amplitude).first?.error,
                               advanced: $voice.useAdvancedEditor,
                               outputLabel: "A",
                               liveCase: { model.liveActiveCase(voiceID: voice.id, role: .amplitude) },
                               fieldIdentifier: "amplitudeField",
                               onHelp: { topic in model.showGuide(topic: topic ?? "topic-amplitude") })
            DemonCaption("Typische Hüllkurve: exp(-4*localTime) klingt nach jedem Auslösen ab. localTime ist die Zeit seit dem letzten Ereignis der Stimme.")
        }
    }
}

// MARK: - Trigger

struct VoiceTriggerSection: View {
    @Environment(AudiolyzerModel.self) private var model
    @Binding var voice: SynthVoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonMenuPicker(title: "Auslöser", selection: $voice.trigger.kind,
                            options: VoiceTrigger.Kind.allCases.map { (value: $0, title: $0.title) },
                            identifier: "triggerKind")
            switch voice.trigger.kind {
            case .continuous:
                DemonCaption("Ein einziges Ereignis am Anfang: localTime = t, n = 0. Gut für Flächen, Riser und direkte Signale.")
            case .pattern:
                pattern
            case .rate:
                rate
            case .pendulum:
                pendulum
            case .sequencer:
                sequencer
            }
            DemonStepper(title: "Gleichzeitige Noten", value: $voice.polyphony, range: SynthVoice.polyphonyRange)
            if voice.polyphony > 1 {
                NumericField(title: "Notenlänge (Beats)", value: $voice.trigger.noteLengthBeats, range: 1.0 / 64...64)
            }
            Button {
                model.showGuide(topic: helpTopic)
            } label: {
                Label("Anleitung: \(voice.trigger.kind.title)", systemImage: "book.fill")
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
        }
    }

    private var helpTopic: String {
        switch voice.trigger.kind {
        case .continuous: return "topic-triggers"
        case .pattern: return "topic-rhythm"
        case .rate: return "topic-accelerating"
        case .pendulum: return "topic-pendulum"
        case .sequencer:
            switch voice.trigger.sequencer.kind {
            case .fibonacci: return "topic-fibonacci"
            case .pascal: return "topic-pascal"
            case .circleOfFifths, .diatonicFifths: return "topic-fifths"
            case .tritone: return "topic-tritone"
            }
        }
    }

    private var pattern: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonTextField(title: "Muster", text: $voice.trigger.pattern, monospaced: true, identifier: "patternField")
            DemonCaption("x = Schlag, o = leiser Schlag (halbe Stärke), . = Pause. Das Muster wiederholt sich; jeder Schritt dauert die Schrittlänge.")
            HStack(spacing: 10) {
                NumericField(title: "Schritt (Beats)", value: $voice.trigger.stepBeats, range: VoiceTrigger.stepRange)
                NumericField(title: "Versatz (Beats)", value: $voice.trigger.offsetBeats, range: -64...64)
            }
        }
    }

    private var rate: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormulaFieldEditor(text: $voice.trigger.rateFormula,
                               title: "Wiederholrate",
                               meaning: "Wiederholrate · Ereignisse pro Beat (Phase = Integral der Rate)",
                               meaningIcon: "speedometer",
                               context: .synth,
                               definitions: definitionSources(model, voice),
                               error: model.issues(voiceID: voice.id, field: .rate).first?.error,
                               advanced: $voice.useAdvancedEditor,
                               outputLabel: "Rate",
                               fieldIdentifier: "rateField",
                               onHelp: { topic in model.showGuide(topic: topic ?? "topic-accelerating") })
            DemonSlider(title: "Höchstens", value: $voice.trigger.maximumEventsPerSecond, range: 1...VoiceTrigger.maximumRate, step: 1,
                        format: { NumberText.decimal($0, fractionDigits: 0) + " Ereignisse/s" })
            DemonCaption("Ein Ereignis entsteht bei jedem ganzzahligen Durchgang der Phase. Über der Grenze wird die Rate begrenzt und im Graphen markiert.")
        }
    }

    private var pendulum: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonStepper(title: "Schwingungen N pro Zyklus", value: $voice.trigger.pendulumCycles, range: 1...64)
            DemonSlider(title: "Zykluslänge P", value: $voice.trigger.pendulumPeriodBeats, range: 1...64, step: 1,
                        format: { NumberText.compact($0) + " Beats" })
            DemonSegmentedPicker(title: "Auslösen", selection: $voice.trigger.pendulumBothDirections,
                                 options: [(value: true, title: "Beide Richtungen"), (value: false, title: "Eine Richtung")])
            DemonCaption("position = cos(2π · N · beat / P). Ausgelöst wird beim Mitteldurchgang, analytisch berechnet.")
        }
    }

    private var sequencer: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonMenuPicker(title: "Folge", selection: $voice.trigger.sequencer.kind,
                            options: SequencerSettings.Kind.allCases.map { (value: $0, title: $0.title) },
                            identifier: "sequencerKind")
            DemonCaption(voice.trigger.sequencer.kind.formula)
            NumericField(title: "Schritt (Beats)", value: $voice.trigger.sequencer.stepBeats, range: VoiceTrigger.stepRange)
            switch voice.trigger.sequencer.kind {
            case .fibonacci:
                DemonStepper(title: "Modul m", value: $voice.trigger.sequencer.modulus, range: SequencerSettings.modulusRange)
                NumberListField(title: "Noten (Halbtöne, Rest r wählt Note r)", values: $voice.trigger.sequencer.notes)
            case .pascal:
                DemonStepper(title: "Zeilen", value: $voice.trigger.sequencer.rows, range: SequencerSettings.rowsRange)
                DemonStepper(title: "Höchstens gleichzeitig", value: $voice.trigger.sequencer.maximumVoices, range: SequencerSettings.voicesRange)
                NumberListField(title: "Noten (Halbtöne je Position)", values: $voice.trigger.sequencer.notes)
            case .circleOfFifths, .diatonicFifths, .tritone:
                EmptyView()
            }
            DemonTextField(title: "Rhythmus (unabhängig von der Notenfolge)", text: $voice.trigger.sequencer.rhythm, monospaced: true)
            DemonCaption("Die erzeugte Note steht in der Tonhöhenformel als Variable note (Halbtöne) zur Verfügung, z. B. Tonhöhe = note.")
        }
    }
}

// MARK: - Definitions and parameters

struct VoiceDefinitionsSection: View {
    @Environment(AudiolyzerModel.self) private var model
    @Binding var voice: SynthVoice
    @State private var definitionsAdvanced = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormulaFieldEditor(text: $voice.definitions,
                               title: "Definitionen der Stimme",
                               meaning: "Definitionen · Listen, Zwischenwerte und Hilfsfunktionen dieser Stimme (eine pro Zeile)",
                               meaningIcon: "list.bullet.rectangle",
                               context: .synth,
                               definitions: [model.project.parameters.map(\.definitionLine).joined(separator: "\n"),
                                             model.project.definitions,
                                             voice.parameters.map(\.definitionLine).joined(separator: "\n")].filter { !$0.trimmed.isEmpty },
                               error: model.issues(voiceID: voice.id, field: .voiceDefinitions).first?.error,
                               advanced: $definitionsAdvanced,
                               outputLabel: "",
                               requiresOutput: false,
                               fieldIdentifier: "voiceDefinitionsField",
                               onHelp: { topic in model.showGuide(topic: topic ?? "topic-intermediate-values") })
            DemonCaption("Beispiele: notes = [0, 3, 7, 10] · env = exp(-4*localTime) · f(k) = 2^(k/12). Die Namen gelten in allen Formeln dieser Stimme.")
            SynthParameterListEditor(parameters: $voice.parameters,
                                     issues: model.issues(voiceID: voice.id, field: .voiceParameters),
                                     autoParameters: model.compiledVoice(voice.id)?.autoParameters ?? [],
                                     identifierPrefix: "voiceParameter",
                                     onHelp: { model.showGuide(topic: "topic-parameters") })
            Toggle("Erweiterter Editor für alle Formeln dieser Stimme", isOn: $voice.useAdvancedEditor)
                .toggleStyle(DemonToggleStyle())
                .font(.subheadline.weight(.semibold))
            DemonCaption(voice.useAdvancedEditor
                         ? "Erweitert: mehrzeilige Formeln; unbekannte Namen sind Fehler (keine automatischen Parameter)."
                         : "Einfach: unbekannte einzelne Namen werden als Parameter mit Wert 1 erkannt und können als Regler übernommen werden.")
            let warnings = model.compiledVoice(voice.id)?.warnings ?? []
            ForEach(warnings.indices, id: \.self) { index in
                Label(warnings[index].message, systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xFFC857))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
