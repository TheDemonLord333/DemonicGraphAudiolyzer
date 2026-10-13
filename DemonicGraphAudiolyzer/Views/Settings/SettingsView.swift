import SwiftUI

/// "Einstellungen": graph display, defaults for playback and export, explanation of the
/// sound modes, formula syntax and licences.
struct SettingsView: View {
    @Environment(AudiolyzerModel.self) private var model

    @AppStorage(PreferenceKey.lightGraph) private var lightGraph = false
    @AppStorage(PreferenceKey.showGrid) private var showGrid = true
    @AppStorage(PreferenceKey.showPreview) private var showPreview = true
    @AppStorage(PreferenceKey.showCursorLine) private var showCursorLine = true

    @AppStorage(PreferenceKey.defaultDuration) private var defaultDuration = 10.0
    @AppStorage(PreferenceKey.defaultVolume) private var defaultVolume = 0.6
    @AppStorage(PreferenceKey.defaultLoop) private var defaultLoop = false
    @AppStorage(PreferenceKey.defaultLevel) private var defaultLevel = -3.0

    @AppStorage(PreferenceKey.exportFormat) private var exportFormat = ExportFormat.mp3.rawValue
    @AppStorage(PreferenceKey.exportSampleRate) private var exportSampleRate = 44_100.0
    @AppStorage(PreferenceKey.exportWAVBitDepth) private var exportWAVBitDepth = 16
    @AppStorage(PreferenceKey.exportAACBitrate) private var exportAACBitrate = 192
    @AppStorage(PreferenceKey.exportMP3Bitrate) private var exportMP3Bitrate = 192
    @AppStorage(PreferenceKey.exportMP3Quality) private var exportMP3Quality = MP3EncodingQuality.high.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DemonHeader(compact: true)
                    .padding(.top, 4)
                graphSection
                playbackSection
                exportSection
                SoundModeExplanation()
                FormulaSyntaxReference()
                AboutSection()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Graphdarstellung", systemImage: "chart.xyaxis.line")
            DemonSegmentedPicker(title: "Graphmodus", selection: $lightGraph,
                                 options: [(value: false, title: "Dunkel"), (value: true, title: "Hell")])
            Text("Der helle Modus ändert nur die Graphfläche (heller Hintergrund, schwarze Achsen und Kurve). Die übrige App bleibt dämonisch dunkel.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            MiniGraphView(formula: "sin(x)", parameters: FormulaParameters(), xRange: -6.3...6.3,
                          appearance: GraphAppearance(isLight: lightGraph))
                .frame(height: 70)
            Toggle("Raster anzeigen", isOn: $showGrid)
                .toggleStyle(DemonToggleStyle())
            Toggle("Kurvenvorschau während der Wiedergabe", isOn: $showPreview)
                .toggleStyle(DemonToggleStyle())
            Toggle("Senkrechte Positionslinie", isOn: $showCursorLine)
                .toggleStyle(DemonToggleStyle())
            Toggle("y-Bereich automatisch anpassen", isOn: Binding(get: { model.autoFitY }, set: { model.setAutoFitY($0) }))
                .toggleStyle(DemonToggleStyle())
        }
        .font(.subheadline.weight(.semibold))
        .demonCard()
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Standardwerte Wiedergabe", systemImage: "play.circle")
            DemonSlider(title: "Dauer", value: $defaultDuration, range: SoundSettings.durationRange, step: 0.5,
                        format: { NumberText.seconds($0) })
            DemonSlider(title: "Lautstärke", value: $defaultVolume, range: 0...1,
                        format: { NumberText.decimal($0 * 100, fractionDigits: 0) + " %" })
            DemonSlider(title: "Pegel / Exportpegel", value: $defaultLevel, range: SoundSettings.levelRange, step: 0.5,
                        format: { NumberText.decimal($0, fractionDigits: 1) + " dBFS" })
            Toggle("Wiederholung", isOn: $defaultLoop)
                .toggleStyle(DemonToggleStyle())
                .font(.subheadline.weight(.semibold))
            Button {
                model.applyPlaybackDefaults(PlaybackDefaults.load())
            } label: {
                Label("Auf aktuelle Formel anwenden", systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
        }
        .demonCard()
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Standardwerte Export", systemImage: "square.and.arrow.up")
            DemonSegmentedPicker(title: "Format", selection: $exportFormat,
                                 options: ExportFormat.allCases.map { (value: $0.rawValue, title: $0.title) })
            subtitle("WAV-Bittiefe")
            DemonSegmentedPicker(title: "WAV-Bittiefe", selection: $exportWAVBitDepth,
                                 options: WAVBitDepth.allCases.map { (value: $0.rawValue, title: $0.title) })
            subtitle("AAC-Bitrate (kbit/s)")
            DemonSegmentedPicker(title: "AAC-Bitrate", selection: $exportAACBitrate,
                                 options: ExportOptions.aacBitrates.map { (value: $0, title: "\($0)") })
            subtitle("MP3-Bitrate (kbit/s)")
            DemonSegmentedPicker(title: "MP3-Bitrate", selection: $exportMP3Bitrate,
                                 options: ExportOptions.mp3Bitrates.map { (value: $0, title: "\($0)") })
            subtitle("MP3-Kodierqualität")
            DemonSegmentedPicker(title: "MP3-Kodierqualität", selection: $exportMP3Quality,
                                 options: MP3EncodingQuality.allCases.map { (value: $0.rawValue, title: $0.title) })
            subtitle("Abtastrate")
            DemonSegmentedPicker(title: "Abtastrate", selection: $exportSampleRate,
                                 options: ExportOptions.sampleRates.map { (value: $0, title: $0 == 44_100 ? "44,1 kHz" : "48 kHz") })
        }
        .demonCard()
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DemonTheme.textSecondary)
    }
}

/// Understandable explanation of both sound modes.
struct SoundModeExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DemonSectionHeader(title: "Klangmodi erklärt", systemImage: "questionmark.circle")
            explanation(title: SoundMode.graph.title, icon: "chart.xyaxis.line", lines: [
                "Ein Punkt wandert in der eingestellten Dauer D von xMin nach xMax: x(t) = xMin + (xMax − xMin) · t / D.",
                "Die Höhe y = f(x) bestimmt die Tonhöhe. Der Klangbereich [yLow, yHigh] wird auf [fLow, fHigh] abgebildet: u = (y − yLow) / (yHigh − yLow), Frequenz = fLow · (fHigh / fLow)^u. Höher heißt höher.",
                "Standard: 110 Hz bis 880 Hz (drei Oktaven). Negative y-Werte sind ganz normale, tiefere Töne.",
                "Automatischer Klangbereich: wird vor jedem Durchlauf aus dem gesamten x-Bereich bestimmt; konstante Funktionen klingen in der Mitte, Ausreißer an Polstellen werden ignoriert.",
                "Definitionslücken (z. B. sqrt(x) für x < 0) werden in 5 ms sanft stummgeschaltet, die Zeit läuft weiter.",
                "Klangfarben: Sinus (rein), Dreieck (weich) und Obertonreich (kräftig). Obertöne werden bandbegrenzt erzeugt – nichts liegt über der Nyquist-Grenze."
            ])
            explanation(title: SoundMode.waveform.title, icon: "waveform", lines: [
                SoundMode.waveform.explanation,
                "Der gewählte Abschnitt [Anfang, Ende] wird als eine Periode gelesen: p(t) = Bruchteil(Grundfrequenz · t), x(t) = Anfang + (Ende − Anfang) · p(t).",
                "Die Welle wird gleichanteilfrei gemacht, auf den Pegel normalisiert und bandbegrenzt. Sprünge zwischen Ende und Anfang werden dabei geglättet; undefinierte Stellen zählen als 0.",
                "Bei hohen Frequenzen ist ein wandernder Cursor nicht darstellbar – optional zeigt die „Zeitlupe der Wellenform“ ihn deutlich verlangsamt."
            ])
            Text("Das Audioverfahren des Referenzvideos ist nicht bekannt; die App setzt diese beiden klar definierten Verfahren um und behauptet keine exakte Rekonstruktion.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .demonCard()
    }

    private func explanation(title: String, icon: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(DemonTheme.green)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    DiamondShape()
                        .fill(DemonTheme.blurple)
                        .frame(width: 6, height: 6)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct FormulaSyntaxReference: View {
    private let rows: [(String, String)] = [
        ("Schreibweisen", "sin(x) · y = sin(x) · f(x) = sin(x)"),
        ("Variable und Parameter", "x sowie a, b, c (mit Reglern)"),
        ("Konstanten", "pi oder π, e"),
        ("Operatoren", "+  −  *  /  ^  und Klammern"),
        ("Rangfolge", "-x^2 = -(x^2), 2^3^2 = 2^(3^2)"),
        ("Implizite Multiplikation", "2x, 2sin(x), bx, (x+1)(x-1)"),
        ("Funktionen", "sin cos tan asin acos atan abs sqrt ln log10 exp floor ceil round min max mod"),
        ("Winkel", "Trigonometrie arbeitet in Radiant"),
        ("mod(a,b)", "a − b·floor(a/b), nur für b > 0 definiert"),
        ("Dezimalzahlen", "mit Punkt: 0.5 (Komma trennt Argumente)")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Formelsyntax", systemImage: "function")
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DemonTheme.blurpleText)
                    Text(row.1)
                        .font(.footnote.monospaced())
                        .foregroundStyle(DemonTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .demonCard()
    }
}

struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Über", systemImage: "info.circle")
            HStack(spacing: 14) {
                Image("DemonIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("App-Symbol")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Demonic Graph Audiolyzer")
                        .font(.headline)
                        .foregroundStyle(DemonTheme.textPrimary)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textTertiary)
                    Text("Arbeitet vollständig offline – ohne Anmeldung, Server oder Mikrofon.")
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("MP3-Kodierung: LAME \(MP3EncoderInfo.version) (lame.sourceforge.io), lizenziert unter der GNU LGPL Version 2. Der vollständige Quelltext liegt dem Projekt unter Packages/LameKit bei.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .demonCard()
    }
}
