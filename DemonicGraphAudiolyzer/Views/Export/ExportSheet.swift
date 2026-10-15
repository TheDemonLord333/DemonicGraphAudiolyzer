import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Export dialog: file name, format, quality, duration, progress, cancel and the actions
/// after a successful export ("In Dateien sichern", share sheet, "Anhören").
struct ExportSheet: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exportModel: ExportModel?

    var body: some View {
        NavigationStack {
            ZStack {
                DemonBackground()
                if let exportModel {
                    ExportForm(exportModel: exportModel)
                }
            }
            .navigationTitle("Audioexport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DemonTheme.void, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        exportModel?.stopPreview()
                        dismiss()
                    }
                    .disabled(exportModel?.isRunning ?? false)
                    .accessibilityIdentifier("closeExport")
                }
            }
        }
        .interactiveDismissDisabled(exportModel?.isRunning ?? false)
        .preferredColorScheme(.dark)
        .onAppear {
            if exportModel == nil {
                exportModel = ExportModel(options: .defaults(), fileName: suggestedFileName,
                                          duration: model.isSynthMode ? model.project.duration : model.settings.duration)
            }
        }
        .onDisappear {
            exportModel?.stopPreview()
        }
    }

    private var suggestedFileName: String {
        if model.isSynthMode {
            return ExportFileName.sanitized("Demonic Graph – \(model.presetTitle)")
        }
        let body = model.formulaDisplayBody
        return ExportFileName.sanitized("Demonic Graph – \(body)")
    }
}

private struct ExportForm: View {
    @Environment(AudiolyzerModel.self) private var model
    @Bindable var exportModel: ExportModel
    @State private var showFileSaver = false
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                fileSection
                formatSection
                durationSection
                actionSection
            }
            .padding(16)
        }
        .sheet(isPresented: $showFileSaver) {
            if let url = exportModel.result?.url {
                DocumentExportPicker(url: url) { saved in
                    showFileSaver = false
                    saveMessage = saved ? "In Dateien gesichert." : nil
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Sections

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Datei", systemImage: "doc")
            HStack(spacing: 6) {
                TextField("Dateiname", text: $exportModel.fileName)
                    .autocorrectionDisabled()
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DemonTheme.textPrimary)
                    .accessibilityIdentifier("exportFileName")
                Text(".\(exportModel.options.format.fileExtension)")
                    .font(.body.weight(.bold).monospaced())
                    .foregroundStyle(DemonTheme.green)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(DemonPanelShape(cornerCut: 8, spike: 0).fill(Color.black.opacity(0.5)))
            .overlay(DemonPanelShape(cornerCut: 8, spike: 0).stroke(DemonTheme.metalMid, lineWidth: 1.1))
        }
        .demonCard()
        .disabled(exportModel.isRunning)
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Format und Qualität", systemImage: "waveform.badge.plus")
            DemonSegmentedPicker(title: "Format", selection: $exportModel.options.format,
                                 options: ExportFormat.allCases.map { (value: $0, title: $0.title) })
                .accessibilityIdentifier("exportFormatPicker")
            Text(exportModel.options.format.detail)
                .font(.footnote)
                .foregroundStyle(DemonTheme.textSecondary)

            switch exportModel.options.format {
            case .wav:
                labeled("Bittiefe") {
                    DemonSegmentedPicker(title: "Bittiefe", selection: $exportModel.options.wavBitDepth,
                                         options: WAVBitDepth.allCases.map { (value: $0, title: $0.title) })
                }
            case .m4a:
                labeled("Bitrate (AAC)") {
                    DemonSegmentedPicker(title: "Bitrate", selection: $exportModel.options.aacBitrate,
                                         options: ExportOptions.aacBitrates.map { (value: $0, title: "\($0)") })
                }
                Text("kbit/s, konstante Bitrate")
                    .font(.caption)
                    .foregroundStyle(DemonTheme.textTertiary)
            case .mp3:
                labeled("Bitrate (MP3)") {
                    DemonSegmentedPicker(title: "Bitrate", selection: $exportModel.options.mp3Bitrate,
                                         options: ExportOptions.mp3Bitrates.map { (value: $0, title: "\($0)") })
                }
                Text("kbit/s, konstante Bitrate, Kodierung mit LAME \(lameVersion)")
                    .font(.caption)
                    .foregroundStyle(DemonTheme.textTertiary)
                labeled("Kodierqualität") {
                    DemonSegmentedPicker(title: "Kodierqualität", selection: $exportModel.options.mp3Quality,
                                         options: MP3EncodingQuality.allCases.map { (value: $0, title: $0.title) })
                }
            }

            labeled("Abtastrate") {
                DemonSegmentedPicker(title: "Abtastrate", selection: $exportModel.options.sampleRate,
                                     options: ExportOptions.sampleRates.map { (value: $0, title: $0 == 44_100 ? "44,1 kHz" : "48 kHz") })
            }
            Text("Stereo · \(exportModel.options.summary)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.blurpleText)
        }
        .demonCard()
        .disabled(exportModel.isRunning)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Dauer", systemImage: "timer")
            if model.isSynthMode {
                Text("Länge des Projekts: \(NumberText.seconds(model.project.duration))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DemonTheme.textPrimary)
                    .accessibilityIdentifier("exportDuration")
            } else {
                DemonSlider(title: "Länge des Durchlaufs", value: $exportModel.duration, range: SoundSettings.durationRange, step: 0.5,
                            format: { NumberText.seconds($0) })
                    .accessibilityIdentifier("exportDuration")
            }
            Text(durationExplanation)
                .font(.caption)
                .foregroundStyle(DemonTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Geschätzte Größe: \(ByteCountFormatter.string(fromByteCount: Int64(exportModel.options.estimatedSize(duration: model.isSynthMode ? model.project.duration : exportModel.duration)), countStyle: .file))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.textSecondary)
        }
        .demonCard()
        .disabled(exportModel.isRunning)
    }

    private var durationExplanation: String {
        let settings = model.settings
        let range: String
        switch settings.mode {
        case .graph:
            range = "von x = \(NumberText.compact(settings.playXMin)) bis x = \(NumberText.compact(settings.playXMax))"
        case .waveform:
            range = "der Klangwelle mit \(NumberText.frequency(settings.baseFrequency))"
        case .synthesizer, .pendulum:
            let tempo = model.project.tempo
            return "Exportiert wird der vollständige Stereo-Mix aller hörbaren Stimmen: \(tempo.bars) Takte à \(tempo.beatsPerBar) Beats bei \(NumberText.decimal(tempo.bpm, fractionDigits: 0)) BPM – mit denselben Ereignissen, Parametern, Hüllkurven, Rauschwerten und Pegeln wie die Vorschau. Die Länge folgt aus Tempo und Takten."
        }
        return "Exportiert wird ein vollständiger Durchlauf \(range) mit allen aktuellen Klangeinstellungen. Eine aktivierte Wiederholung erzeugt keinen endlosen Export."
    }

    @ViewBuilder
    private var actionSection: some View {
        VStack(spacing: 14) {
            switch exportModel.state {
            case .idle, .cancelled, .failed:
                if case .failed(let message) = exportModel.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DemonTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .cancelled = exportModel.state {
                    Text("Export abgebrochen – unvollständige Dateien wurden entfernt.")
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.textSecondary)
                }
                exportButton
            case .running(let progress):
                VStack(spacing: 10) {
                    HStack {
                        ProgressView()
                            .tint(DemonTheme.neonGreen)
                        Text("Export läuft … \(NumberText.decimal(progress * 100, fractionDigits: 0)) %")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(DemonTheme.textPrimary)
                            .accessibilityIdentifier("exportProgress")
                    }
                    DemonProgressBar(progress: progress)
                    Button(role: .cancel) {
                        exportModel.cancel()
                    } label: {
                        Label("Abbrechen", systemImage: "xmark")
                    }
                    .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.danger))
                    .accessibilityIdentifier("cancelExport")
                }
                .accessibilityElement(children: .contain)
            case .finished(let result):
                finishedView(result)
            }
        }
        .frame(maxWidth: .infinity)
        .demonCard(crest: true)
    }

    private var exportButton: some View {
        Button {
            startExport()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .foregroundStyle(DemonTheme.neonGreen)
                Text("Exportieren")
            }
        }
        .buttonStyle(DemonPrimaryButtonStyle())
        .disabled(model.parsedFormula == nil || model.settingsIssue != nil)
        .accessibilityIdentifier("startExport")
    }

    private func finishedView(_ result: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export abgeschlossen", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(DemonTheme.green)
                .accessibilityIdentifier("exportFinished")
            Text(result.url.lastPathComponent)
                .font(.callout.weight(.semibold).monospaced())
                .foregroundStyle(DemonTheme.textPrimary)
                .lineLimit(2)
            Text(fileFacts(result))
                .font(.caption)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DemonTheme.green)
            }
            VStack(spacing: 10) {
                Button {
                    showFileSaver = true
                } label: {
                    Label("In Dateien sichern", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
                .accessibilityIdentifier("saveToFiles")

                ShareLink(item: result.url,
                          preview: SharePreview(result.url.lastPathComponent, image: Image("DemonIcon"))) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DemonChipButtonStyle())
                .accessibilityIdentifier("shareExport")

                Button {
                    exportModel.togglePreview()
                } label: {
                    Label(exportModel.isPreviewPlaying ? "Anhören beenden" : "Anhören",
                          systemImage: exportModel.isPreviewPlaying ? "stop.fill" : "headphones")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DemonChipButtonStyle(isActive: exportModel.isPreviewPlaying))
                .accessibilityIdentifier("listenExport")

                Button {
                    exportModel.reset()
                    saveMessage = nil
                } label: {
                    Label("Neuer Export", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DemonChipButtonStyle())
            }
        }
    }

    private func fileFacts(_ result: ExportResult) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(result.byteCount), countStyle: .file)
        var text = "\(result.options.summary) · \(size) · erzeugt: \(NumberText.seconds(result.renderedDuration))"
        if let check = exportModel.verification {
            let rate = check.sampleRate == 44_100 ? "44,1 kHz" : NumberText.decimal(check.sampleRate / 1000, fractionDigits: 1) + " kHz"
            text += "\nGeprüft mit AVFoundation: \(check.codecName), \(rate), \(check.channels) Kanäle, \(NumberText.decimal(check.decodedDuration, fractionDigits: 2)) s dekodierbar."
        }
        return text
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DemonTheme.textSecondary)
            content()
        }
    }

    private var lameVersion: String {
        MP3EncoderInfo.version
    }

    private func startExport() {
        guard let job = model.makeRenderJob(sampleRate: exportModel.options.sampleRate) else { return }
        guard model.beginExport() else { return }
        saveMessage = nil
        let audiolyzer = model
        exportModel.start(job: job) {
            audiolyzer.endExport()
        }
    }
}

/// Saves a file to the Files app ("In Dateien sichern") as a copy.
struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(false)
        }
    }
}

extension ExportFormat {
    /// The uniform type of the exported container.
    var utType: UTType {
        switch self {
        case .mp3: return .mp3
        case .wav: return .wav
        case .m4a: return .mpeg4Audio
        }
    }
}
