import SwiftUI

/// Multi-lane graph of the synthesizer, animated from the audio clock.
struct SynthGraphView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var appearance: GraphAppearance
    var options: SynthGraphOptions

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30.0 : nil, paused: model.phase != .playing)) { _ in
            let snapshot = model.playbackSnapshot()
            let clock = model.compilation?.clock ?? MusicalClock(tempo: model.project.tempo, sampleRate: AudiolyzerModel.previewSampleRate)
            let snippet = options.showSnippet ? snippetSource() : nil
            Canvas { context, size in
                SynthGraphRenderer.draw(in: &context, size: size, data: model.synthGraph, clock: clock,
                                        cursorFrame: snapshot?.frame, isPlaying: snapshot.map { !$0.isPaused } ?? false,
                                        appearance: appearance, options: options, snippet: snippet)
            }
        }
        .clipShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Mehrspur-Graph: \(model.synthGraph.lanes.map(\.title).joined(separator: ", "))")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("synthGraph")
    }

    private var accessibilityValue: String {
        guard let snapshot = model.playbackSnapshot() else {
            return "\(model.synthGraph.voiceOrder.count) sichtbare Stimmen, \(NumberText.seconds(model.project.duration))"
        }
        let values = model.synthReadout(atFrame: snapshot.frame).map { readout in
            "\(readout.name) \(readout.frequency.map(NumberText.frequency) ?? "ohne Tonhöhe")"
        }
        return "Zeit \(NumberText.seconds(snapshot.time)). " + values.joined(separator: ", ")
    }

    private func snippetSource() -> SnippetSource? {
        guard let compilation = model.compilation else { return nil }
        var stems: [(color: VoiceColor, name: String, samples: [Int16])] = []
        for compiled in compilation.voices where compiled.voice.isVisible {
            if let samples = model.activeStems[compiled.voice.id] {
                stems.append((compiled.voice.color, compiled.voice.name, samples))
            }
        }
        var signals: [(color: VoiceColor, name: String, value: (Double) -> Double)] = []
        for display in compilation.displayCurves where display.curve.unit == .signal {
            let program = display.program
            let buffer = EvaluationBuffer(capacity: program.slotCount)
            let clock = compilation.clock
            let mapping = compilation.xMapping
            signals.append((display.curve.color, display.curve.name, { time in
                VoiceInputs.set(buffer, frame: time * clock.sampleRate, eventFrame: nil, event: nil, clock: clock, xMapping: mapping)
                return buffer.evaluate(program)
            }))
        }
        if stems.isEmpty && signals.isEmpty && model.synthGraph.lanes.isEmpty { return nil }
        return SnippetSource(stems: stems, sampleRate: AudiolyzerModel.previewSampleRate, displaySignals: signals)
    }
}

/// Graph card of the synthesizer: lanes, legend, live values, preset title and explanation.
struct SynthGraphCard: View {
    @Environment(AudiolyzerModel.self) private var model
    var appearance: GraphAppearance
    var options: SynthGraphOptions
    var plotHeight: CGFloat?
    var compact = false
    var onFullscreen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.presetTitle)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(DemonTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(projectFacts)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DemonTheme.blurpleText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Button(action: onFullscreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(DemonChipButtonStyle())
                .accessibilityLabel("Graph vergrößern")
                .accessibilityIdentifier("fullscreenButton")
            }
            SynthGraphView(appearance: appearance, options: options)
                .frame(height: plotHeight)
                .frame(maxHeight: plotHeight == nil ? .infinity : nil)
                .clipShape(DemonPanelShape(cornerCut: 10, spike: 0))
                .overlay(DemonPanelShape(cornerCut: 10, spike: 0).stroke(DemonTheme.metalMid.opacity(0.75), lineWidth: 1))
            VoiceLegend()
            SynthReadoutView(compact: compact)
            if !compact, !model.presetSummary.isEmpty {
                Text(model.presetSummary)
                    .font(.footnote)
                    .foregroundStyle(DemonTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("presetSummary")
            }
            if model.limiterEngaged {
                Label("Der Schutzbegrenzer hat Spitzen über −1 dBFS weich abgefangen. Für mehr Reserve den Projektpegel oder Stimmen leiser stellen.",
                      systemImage: "waveform.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xFFC857))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .demonCard(crest: !compact, padding: compact ? 10 : 12, hornHeight: compact ? 26 : 38)
    }

    private var projectFacts: String {
        let tempo = model.project.tempo
        return "\(NumberText.decimal(tempo.bpm, fractionDigits: 0)) BPM · \(tempo.beatsPerBar)/4 · \(tempo.bars) Takte · \(NumberText.seconds(tempo.duration)) · x = \(model.project.xMapping.shortTitle)"
    }
}

/// Legend: voice colours, names, tap toggles the graph visibility.
struct VoiceLegend: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.project.voices) { voice in
                    Button {
                        model.updateVoice(voice.id) { $0.isVisible.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            VoiceColorDot(color: voice.color, size: 9)
                                .opacity(voice.isVisible ? 1 : 0.3)
                            Text(voice.name)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .strikethrough(voice.isMuted)
                            if voice.isSolo {
                                Text("S").font(.caption2.weight(.black)).foregroundStyle(DemonTheme.neonGreen)
                            }
                        }
                        .foregroundStyle(voice.isVisible ? DemonTheme.textPrimary : DemonTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 32)
                        .background(DemonPanelShape(cornerCut: 6, spike: 0).fill(Color.black.opacity(0.35)))
                        .overlay(DemonPanelShape(cornerCut: 6, spike: 0).stroke(voice.color.color.opacity(voice.isVisible ? 0.8 : 0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(voice.name): im Graphen \(voice.isVisible ? "sichtbar" : "ausgeblendet")\(voice.isMuted ? ", stumm" : "")")
                    .accessibilityHint("Doppeltippen blendet die Kurven der Stimme ein oder aus")
                }
                ForEach(model.project.displayCurves) { curve in
                    HStack(spacing: 5) {
                        Rectangle().fill(curve.color.color).frame(width: 12, height: 2)
                        Text(curve.name).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(DemonTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 32)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Anzeigekurve \(curve.name)")
                }
            }
        }
    }
}

/// Live values from the audio clock: musical position, pitch and gain of every visible voice,
/// current parameters.
struct SynthReadoutView: View {
    @Environment(AudiolyzerModel.self) private var model
    var compact = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: model.phase != .playing)) { _ in
            let snapshot = model.phase == .playing || model.phase == .paused ? model.playbackSnapshot() : nil
            content(snapshot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readout")
    }

    @ViewBuilder
    private func content(_ snapshot: PlaybackSnapshot?) -> some View {
        let frame = snapshot?.frame ?? 0
        let clock = model.compilation?.clock ?? MusicalClock(tempo: model.project.tempo, sampleRate: AudiolyzerModel.previewSampleRate)
        let position = clock.position(atFrame: frame)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ReadoutValue(label: "Takt", value: "\(Int(position.bar) + 1)")
                ReadoutValue(label: "Beat im Takt", value: NumberText.decimal(position.beatInBar, fractionDigits: 2))
                ReadoutValue(label: "t", value: NumberText.seconds(position.time), highlighted: snapshot != nil)
            }
            if !compact {
                ForEach(model.synthReadout(atFrame: frame)) { readout in
                    HStack(spacing: 6) {
                        VoiceColorDot(color: readout.color, size: 8)
                        Text(readout.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DemonTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(readout.frequency.map(NumberText.frequency) ?? "–")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(DemonTheme.green)
                        Text("· \(readout.gain.map { NumberText.decimal($0, fractionDigits: 2) } ?? "–")×")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DemonTheme.textTertiary)
                        if let index = readout.eventIndex {
                            Text("n = \(index)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DemonTheme.blurpleText)
                        }
                    }
                }
                if !parameterText(position).isEmpty {
                    Text(parameterText(position))
                        .font(.caption.monospaced())
                        .foregroundStyle(DemonTheme.blurpleText)
                        .lineLimit(3)
                        .accessibilityLabel("Aktuelle Parameter: \(parameterText(position))")
                }
            }
        }
    }

    private func parameterText(_ position: MusicalPosition) -> String {
        var parts: [String] = []
        for parameter in model.project.parameters {
            parts.append("\(parameter.name) = \(NumberText.compact(SynthAnalysis.value(of: parameter, position: position)))")
        }
        for voice in model.project.voices where voice.isVisible {
            for parameter in voice.parameters {
                parts.append("\(parameter.name) = \(NumberText.compact(SynthAnalysis.value(of: parameter, position: position)))")
            }
        }
        return parts.prefix(8).joined(separator: " · ")
    }
}

/// Enlarged synthesizer graph.
struct FullscreenSynthGraphView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var appearance: GraphAppearance
    var options: SynthGraphOptions

    var body: some View {
        ZStack {
            DemonBackground()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(model.presetTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(DemonTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(DemonRuneButtonStyle(minWidth: 52))
                    .accessibilityLabel("Vergrößerte Ansicht schließen")
                    .accessibilityIdentifier("closeFullscreen")
                }
                SynthGraphView(appearance: appearance, options: options)
                    .clipShape(DemonPanelShape(cornerCut: 12, spike: 0))
                    .overlay(DemonPanelShape(cornerCut: 12, spike: 0).stroke(DemonTheme.metalStroke, lineWidth: 1.6))
                    .frame(maxHeight: .infinity)
                VoiceLegend()
                if verticalSizeClass == .compact {
                    HStack(spacing: 12) {
                        SynthReadoutView(compact: true).frame(maxWidth: 320)
                        TransportControls(compact: true)
                    }
                } else {
                    SynthReadoutView()
                    TransportControls(compact: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .preferredColorScheme(.dark)
    }
}
