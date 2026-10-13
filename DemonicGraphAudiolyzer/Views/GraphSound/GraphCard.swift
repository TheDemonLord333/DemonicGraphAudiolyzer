import SwiftUI

/// The framed graph with formula label, live read-out and view tools.
struct GraphCard: View {
    @Environment(AudiolyzerModel.self) private var model
    var appearance: GraphAppearance
    /// Fixed plot height; nil lets the plot fill the available height (landscape).
    var plotHeight: CGFloat?
    var onFullscreen: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            GraphView(appearance: appearance)
                .frame(height: plotHeight)
                .frame(maxHeight: plotHeight == nil ? .infinity : nil)
                .clipShape(DemonPanelShape(cornerCut: 10, spike: 0))
                .overlay(DemonPanelShape(cornerCut: 10, spike: 0).stroke(DemonTheme.metalMid.opacity(0.75), lineWidth: 1))

            Text("f(x) = \(model.formulaDisplayBody)")
                .font(.callout.weight(.bold).monospaced())
                .foregroundStyle(DemonTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("graphFormulaLabel")

            PlaybackReadoutView()

            GraphToolbar(onFullscreen: onFullscreen)
        }
        .demonCard(crest: true, padding: 12)
    }
}

struct GraphToolbar: View {
    @Environment(AudiolyzerModel.self) private var model
    var onFullscreen: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons(showTitles: true) }
            HStack(spacing: 8) { buttons(showTitles: false) }
        }
    }

    @ViewBuilder
    private func buttons(showTitles: Bool) -> some View {
        Button {
            model.resetView()
        } label: {
            label("Ansicht zurücksetzen", short: "Zurücksetzen", icon: "arrow.counterclockwise", showTitle: showTitles)
        }
        .buttonStyle(DemonChipButtonStyle())
        .accessibilityLabel("Ansicht zurücksetzen")
        .accessibilityIdentifier("resetViewButton")

        Button {
            model.setAutoFitY(!model.autoFitY)
        } label: {
            label("y automatisch", short: "y-Auto", icon: "arrow.up.and.down.text.horizontal", showTitle: showTitles)
        }
        .buttonStyle(DemonChipButtonStyle(isActive: model.autoFitY))
        .accessibilityLabel("y-Bereich automatisch anpassen")
        .accessibilityValue(model.autoFitY ? "ein" : "aus")
        .accessibilityAddTraits(model.autoFitY ? .isSelected : [])

        if let onFullscreen {
            Button(action: onFullscreen) {
                label("Vergrößern", short: "Groß", icon: "arrow.up.left.and.arrow.down.right", showTitle: showTitles)
            }
            .buttonStyle(DemonChipButtonStyle())
            .accessibilityLabel("Graph vergrößern")
            .accessibilityIdentifier("fullscreenButton")
        }
    }

    private func label(_ title: String, short: String, icon: String, showTitle: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(showTitle ? title : short)
                .lineLimit(1)
        }
    }
}

/// x, y and frequency of the current position – read from the audio clock.
struct PlaybackReadoutView: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: model.phase != .playing)) { _ in
            let snapshot = model.phase == .playing || model.phase == .paused ? model.playbackSnapshot() : nil
            content(snapshot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readout")
    }

    @ViewBuilder
    private func content(_ snapshot: PlaybackSnapshot?) -> some View {
        let settings = model.settings
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                switch settings.mode {
                case .graph:
                    if let snapshot {
                        ReadoutValue(label: "x", value: NumberText.decimal(snapshot.readout.x, fractionDigits: 2))
                        ReadoutValue(label: "y", value: snapshot.readout.y.map { NumberText.decimal($0, fractionDigits: 3) } ?? "undefiniert")
                        ReadoutValue(label: "Frequenz", value: snapshot.readout.frequency.map(NumberText.frequency) ?? "stumm", highlighted: true)
                    } else {
                        ReadoutValue(label: "x-Bereich", value: "\(NumberText.compact(settings.playXMin)) … \(NumberText.compact(settings.playXMax))")
                        ReadoutValue(label: "Dauer", value: NumberText.seconds(settings.duration))
                        ReadoutValue(label: "Töne", value: "\(NumberText.frequency(settings.frequencyLow)) – \(NumberText.frequency(settings.frequencyHigh))", highlighted: true)
                    }
                case .waveform:
                    ReadoutValue(label: "Grundfrequenz", value: NumberText.frequency(settings.baseFrequency), highlighted: true)
                    ReadoutValue(label: "Abschnitt", value: "\(NumberText.compact(settings.sectionStart, maximumFractionDigits: 2)) … \(NumberText.compact(settings.sectionEnd, maximumFractionDigits: 2))")
                    ReadoutValue(label: "Zeit", value: snapshot.map { NumberText.seconds($0.time) } ?? NumberText.seconds(settings.duration))
                }
            }
            if let snapshot {
                DemonProgressBar(progress: snapshot.progress)
                    .accessibilityHidden(true)
                HStack {
                    Text(NumberText.clock(snapshot.time))
                    Spacer()
                    Text(NumberText.clock(snapshot.duration))
                }
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DemonTheme.textTertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zeit \(NumberText.seconds(snapshot.time)) von \(NumberText.seconds(snapshot.duration))")
            }
        }
    }
}

struct DemonProgressBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule().stroke(DemonTheme.metalMid.opacity(0.7), lineWidth: 1)
                Capsule()
                    .fill(DemonTheme.greenFill)
                    .frame(width: max(6, geometry.size.width * CGFloat(min(max(progress, 0), 1))))
                    .shadow(color: DemonTheme.neonGreen.opacity(0.7), radius: 4)
            }
        }
        .frame(height: 8)
    }
}
