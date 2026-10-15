import SwiftUI

/// Mode specific settings of the classic modes (timbre or waveform section).
struct SoundModeCard: View {
    @Environment(AudiolyzerModel.self) private var model
    var appearance: GraphAppearance

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            DemonSectionHeader(title: model.settings.mode.title, systemImage: model.settings.mode.icon)
            Text(model.settings.mode.explanation)
                .font(.footnote)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            switch model.settings.mode {
            case .graph:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Klangfarbe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DemonTheme.textSecondary)
                    DemonSegmentedPicker(title: "Klangfarbe", selection: $model.settings.timbre,
                                         options: Timbre.allCases.map { (value: $0, title: $0.title) })
                    Text(model.settings.timbre.explanation)
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textTertiary)
                }
            case .waveform:
                WaveformSettingsSection(appearance: appearance)
            case .synthesizer, .pendulum:
                EmptyView()
            }
        }
        .demonCard()
    }
}

/// The four modes of "Graph & Klang".
struct ModePicker: View {
    @Environment(AudiolyzerModel.self) private var model
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SoundMode.allCases) { mode in
                let isSelected = model.settings.mode == mode
                Button {
                    model.setMode(mode)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.icon)
                            .font(.system(size: compact ? 15 : 17, weight: .semibold))
                        Text(mode.shortTitle)
                            .font(.caption.weight(isSelected ? .heavy : .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isSelected ? DemonTheme.greenCore : DemonTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: compact ? 46 : 54)
                    .background {
                        if isSelected {
                            ZStack {
                                DemonRuneShape().fill(DemonTheme.green.opacity(0.22))
                                DemonRuneShape().stroke(DemonTheme.green, lineWidth: 1.4)
                            }
                            .shadow(color: DemonTheme.green.opacity(0.45), radius: 6)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("mode-\(mode.rawValue)")
            }
        }
        .padding(4)
        .background(DemonPanelShape(cornerCut: 12, spike: 4).fill(DemonTheme.cardFill))
        .overlay(DemonPanelShape(cornerCut: 12, spike: 4).stroke(DemonTheme.metalStroke, lineWidth: 1.2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modus")
        .accessibilityIdentifier("modePicker")
    }
}

/// Settings and display of "Formel als Klangwelle".
struct WaveformSettingsSection: View {
    @Environment(AudiolyzerModel.self) private var model
    var appearance: GraphAppearance

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NumericField(title: "Abschnitt von", value: $model.settings.sectionStart, accessibilityIdentifier: "sectionStart")
                NumericField(title: "bis", value: $model.settings.sectionEnd, accessibilityIdentifier: "sectionEnd")
            }
            Text("Die Abschnittsgrenzen sind eigene Einstellungen und haben nichts mit den Formelparametern a und b zu tun. Eingaben wie 2pi sind erlaubt.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            DemonSlider(title: "Grundfrequenz", value: $model.settings.baseFrequency,
                        range: SoundSettings.baseFrequencyRange, logarithmic: true,
                        format: { NumberText.frequency($0) })

            WaveformDisplayView(appearance: appearance)

            Toggle("Zeitlupe der Wellenform", isOn: $model.slowMotionWaveform)
                .toggleStyle(DemonToggleStyle())
                .font(.subheadline.weight(.semibold))
                .accessibilityHint("Zeigt den Phasencursor stark verlangsamt, nicht in Echtzeit")

            if let table = model.waveformTable {
                WaveformNotes(table: table)
            }
        }
    }
}

/// One period of the generated (band-limited) waveform with phase cursor.
struct WaveformDisplayView: View {
    @Environment(AudiolyzerModel.self) private var model
    var appearance: GraphAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.animation(minimumInterval: nil, paused: model.phase != .playing)) { _ in
                let snapshot = model.playbackSnapshot()
                Canvas { context, size in
                    draw(in: &context, size: size, snapshot: snapshot)
                }
            }
            .frame(height: 118)
            .clipShape(DemonPanelShape(cornerCut: 8, spike: 0))
            .overlay(DemonPanelShape(cornerCut: 8, spike: 0).stroke(DemonTheme.metalMid.opacity(0.75), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("Wellenform: eine Periode der erzeugten Klangwelle")
            .accessibilityValue(caption)

            Text(caption)
                .font(.caption)
                .foregroundStyle(model.slowMotionWaveform ? DemonTheme.neonGreen : DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        let frequency = NumberText.frequency(model.settings.baseFrequency)
        if model.slowMotionWaveform {
            return "Zeitlupe der Wellenform – nicht in Echtzeit: Der Cursor braucht \(NumberText.decimal(GraphView.slowMotionCycle, fractionDigits: 0)) s für einen Durchlauf, im Klang sind es \(frequency) Durchläufe pro Sekunde."
        }
        if model.phase == .playing {
            return "Der Abschnitt wird \(frequency)-mal pro Sekunde durchlaufen – zu schnell für eine Einzelbildanzeige, deshalb leuchtet die ganze Periode."
        }
        return "Eine Periode der erzeugten Klangwelle: gleichanteilfrei, normalisiert und bandbegrenzt."
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, snapshot: PlaybackSnapshot?) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(appearance.background))
        let midY = size.height / 2
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: midY))
        axis.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(axis, with: .color(appearance.axis.opacity(0.7)), lineWidth: 1)

        guard let table = model.waveformTable, !table.displayPeriod.isEmpty else {
            let text = context.resolve(Text("Keine Klangwelle").font(.caption).foregroundStyle(appearance.label))
            context.draw(text, at: CGPoint(x: size.width / 2, y: midY), anchor: .center)
            return
        }
        let values = table.displayPeriod
        let amplitude = size.height * 0.42
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = midY - CGFloat(value) * amplitude
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let sounding = snapshot != nil && snapshot?.isPaused == false
        if let glow = appearance.glow, sounding {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.stroke(path, with: .color(glow.opacity(0.6)), lineWidth: 6)
            }
        }
        let curveColor = snapshot == nil ? appearance.curve.opacity(0.85) : appearance.curve
        context.stroke(path, with: .color(curveColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

        guard let snapshot else { return }
        if model.slowMotionWaveform {
            let phase = (snapshot.time / GraphView.slowMotionCycle).truncatingRemainder(dividingBy: 1)
            let index = min(values.count - 1, Int(phase * Double(values.count)))
            let x = size.width * CGFloat(phase)
            let y = midY - CGFloat(values[index]) * amplitude
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(appearance.curve.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)),
                         with: .color(appearance.isLight ? DemonTheme.ink : DemonTheme.greenCore))
            let label = context.resolve(Text("ZEITLUPE").font(.caption2.weight(.heavy)).foregroundStyle(appearance.isLight ? DemonTheme.ink : DemonTheme.neonGreen))
            context.draw(label, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
        } else if sounding {
            // The cursor would alias at display rate – show the whole period as active instead.
            context.fill(Path(rect), with: .color(appearance.curve.opacity(0.07)))
        }
    }
}

struct WaveformNotes: View {
    let table: WaveformTable

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            note("Bandbegrenzt auf \(table.harmonicCount) Obertöne (Anti-Aliasing).", icon: "waveform.path")
            if table.isSilent {
                note("Im Abschnitt ist die Funktion konstant oder undefiniert – es entsteht Stille.", icon: "speaker.slash", warning: true)
            }
            if table.undefinedFraction > 0 {
                note("\(NumberText.decimal(table.undefinedFraction * 100, fractionDigits: 0)) % des Abschnitts sind undefiniert und werden als 0 behandelt.", icon: "exclamationmark.triangle", warning: true)
            }
            if table.boundaryJump > 0.05 {
                note("Sprung zwischen Abschnittsende und -anfang – wird durch die Bandbegrenzung geglättet.", icon: "arrow.uturn.left")
            }
            if table.limitedOutliers {
                note("Extreme Ausreißer wurden vor der Normalisierung sanft begrenzt.", icon: "chart.line.flattrend.xyaxis")
            }
        }
    }

    private func note(_ text: String, icon: String, warning: Bool = false) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption)
        .foregroundStyle(warning ? DemonTheme.danger : DemonTheme.textTertiary)
    }
}

/// Sliders and manual input for the parameters a, b, c used in the formula.
struct ParameterCard: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DemonSectionHeader(title: "Parameter", systemImage: "slider.horizontal.3")
            if model.usedParameters.isEmpty {
                Text("Verwende a, b oder c in der Formel (z. B. a*sin(b*x)+c) – dann erscheinen hier Regler.")
                    .font(.footnote)
                    .foregroundStyle(DemonTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.usedParameters, id: \.self) { variable in
                    ParameterRow(variable: variable)
                }
            }
        }
        .demonCard()
    }
}

struct ParameterRow: View {
    @Environment(AudiolyzerModel.self) private var model
    let variable: FormulaVariable

    static let sliderRange: ClosedRange<Double> = -10...10

    var body: some View {
        let binding = Binding<Double>(
            get: { model.parameters[variable] },
            set: { model.parameters[variable] = $0 })
        HStack(alignment: .bottom, spacing: 12) {
            DemonSlider(title: "Parameter \(variable.rawValue)", value: binding, range: Self.sliderRange, step: 0.01,
                        format: { NumberText.decimal($0, fractionDigits: 2) })
            NumericField(title: "Wert", value: binding, range: -1e6...1e6, accessibilityIdentifier: "parameter-\(variable.rawValue)")
                .frame(width: 92)
        }
    }
}

/// Duration and volume.
struct PlaybackCard: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            DemonSectionHeader(title: "Wiedergabe", systemImage: "metronome")
            DemonSlider(title: "Dauer", value: $model.settings.duration, range: SoundSettings.durationRange, step: 0.5,
                        format: { NumberText.seconds($0) })
                .accessibilityIdentifier("durationSlider")
            DemonSlider(title: "Lautstärke", value: $model.volume, range: 0...1,
                        format: { NumberText.decimal($0 * 100, fractionDigits: 0) + " %" })
                .accessibilityIdentifier("volumeSlider")
            Text("Die Lautstärke wirkt nur auf die Vorschau, nicht auf exportierte Dateien.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
        }
        .demonCard()
    }
}

/// "Erweiterte Einstellungen": ranges, pitch mapping, smoothing, fades, level.
struct AdvancedSettingsCard: View {
    @Environment(AudiolyzerModel.self) private var model
    @State private var isExpanded = false

    var body: some View {
        @Bindable var model = model
        DemonDisclosure(title: "Erweiterte Einstellungen", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                if model.settings.mode == .graph {
                    graphModeSettings
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ausgabe (Vorschau und Export)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DemonTheme.textSecondary)
                    DemonSlider(title: "Ein- und Ausblendung", value: $model.settings.fadeMilliseconds,
                                range: SoundSettings.fadeRange, step: 1,
                                format: { NumberText.decimal($0, fractionDigits: 0) + " ms" })
                    DemonSlider(title: "Pegel", value: $model.settings.levelDecibels, range: SoundSettings.levelRange, step: 0.5,
                                format: { NumberText.decimal($0, fractionDigits: 1) + " dBFS" })
                    Text("Der Pegel ist der Spitzenwert des erzeugten Signals und damit der definierte Exportpegel – unabhängig von Lautstärke und Systemlautstärke.")
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    model.applyPlaybackDefaults(PlaybackDefaults.load())
                } label: {
                    Label("Wiedergabe-Standardwerte anwenden", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(DemonChipButtonStyle())
            }
        }
        .demonCard()
    }

    @ViewBuilder
    private var graphModeSettings: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Text("Abgespielter x-Bereich")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DemonTheme.textSecondary)
            HStack(spacing: 10) {
                NumericField(title: "xMin", value: $model.settings.playXMin, accessibilityIdentifier: "playXMin")
                NumericField(title: "xMax", value: $model.settings.playXMax, accessibilityIdentifier: "playXMax")
            }
            Button {
                model.adoptVisibleRangeForPlayback()
            } label: {
                Label("Sichtbaren Ausschnitt übernehmen", systemImage: "viewfinder")
            }
            .buttonStyle(DemonChipButtonStyle())
            Text("Der abgespielte Bereich ist unabhängig vom sichtbaren Ausschnitt.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Klangbereich (y → Tonhöhe)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DemonTheme.textSecondary)
            DemonSegmentedPicker(title: "Klangbereich", selection: $model.settings.pitchRangeMode,
                                 options: PitchRangeMode.allCases.map { (value: $0, title: $0.title) })
            switch model.settings.pitchRangeMode {
            case .automatic:
                Text(automaticRangeText)
                    .font(.footnote)
                    .foregroundStyle(DemonTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .manual:
                HStack(spacing: 10) {
                    NumericField(title: "yLow", value: $model.settings.manualYLow, accessibilityIdentifier: "yLow")
                    NumericField(title: "yHigh", value: $model.settings.manualYHigh, accessibilityIdentifier: "yHigh")
                }
                if let range = model.automaticRange, range.hasDefinedValues {
                    Button {
                        model.settings.manualYLow = range.low
                        model.settings.manualYHigh = range.high
                    } label: {
                        Label("Automatische Werte übernehmen", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(DemonChipButtonStyle())
                }
            }
            Text("Zoomen oder Verschieben des Graphen verändert den Klangbereich nicht. Werte außerhalb erklingen mit der tiefsten bzw. höchsten Frequenz.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Frequenzbereich")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DemonTheme.textSecondary)
            DemonSlider(title: "Tiefste Frequenz (fLow)", value: $model.settings.frequencyLow,
                        range: SoundSettings.frequencyRange, logarithmic: true, format: { NumberText.frequency($0) })
            DemonSlider(title: "Höchste Frequenz (fHigh)", value: $model.settings.frequencyHigh,
                        range: SoundSettings.frequencyRange, logarithmic: true, format: { NumberText.frequency($0) })
            DemonSlider(title: "Glättung der Tonhöhe", value: $model.settings.glideMilliseconds,
                        range: SoundSettings.glideRange, step: 1,
                        format: { $0 == 0 ? "aus" : NumberText.decimal($0, fractionDigits: 0) + " ms" })
        }
    }

    private var automaticRangeText: String {
        guard let range = model.automaticRange else { return "Wird ermittelt …" }
        if !range.hasDefinedValues {
            return "Die Funktion ist im x-Bereich nirgends definiert – der Durchlauf bleibt still."
        }
        if range.isConstant {
            return "Konstante Funktion – sie erklingt mit der mittleren Frequenz."
        }
        var text = "Automatisch vor dem Durchlauf ermittelt: yLow = \(NumberText.compact(range.low)), yHigh = \(NumberText.compact(range.high))."
        if range.ignoredOutliers {
            text += " Extreme Ausreißer (z. B. Polstellen) werden ignoriert."
        }
        return text
    }
}

/// Entry to the export dialog.
struct ExportEntryCard: View {
    @Environment(AudiolyzerModel.self) private var model
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Audioexport", systemImage: "square.and.arrow.up")
            Text(model.isSynthMode
                 ? "Exportiert den vollständigen Mehrstimmen-Mix in Stereo – gleiche Ereignisse, Parameter, Hüllkurven und Pegel wie die Vorschau."
                 : "Exportiert genau den erzeugten Klang als MP3, WAV oder M4A – ohne Mikrofon, ohne Systemaufnahme.")
                .font(.footnote)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onExport) {
                Label("Audio exportieren …", systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
            .disabled(!model.canExport || model.phase == .exporting)
            .accessibilityIdentifier("exportButton")
        }
        .demonCard()
    }
}
