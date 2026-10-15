import SwiftUI

/// Main screen "Graph & Klang" with the mode selection on top (graph, waveform, synthesizer,
/// pendulum). Portrait: one scrolling column. Landscape: the graph takes the left side at full
/// height, transport and controls are on the right.
struct GraphSoundView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @AppStorage(PreferenceKey.lightGraph) private var lightGraph = false
    @AppStorage(PreferenceKey.showGrid) private var showGrid = true
    @AppStorage(PreferenceKey.showPreview) private var showPreview = true
    @AppStorage(PreferenceKey.showCursorLine) private var showCursorLine = true
    @AppStorage(PreferenceKey.showTrails) private var showTrails = true
    @AppStorage(PreferenceKey.showSnippet) private var showSnippet = true

    @State private var showFullscreen = false
    @State private var showExport = false

    private var appearance: GraphAppearance {
        GraphAppearance(isLight: lightGraph, showGrid: showGrid, showPreview: showPreview, showCursorLine: showCursorLine)
    }

    private var synthOptions: SynthGraphOptions {
        SynthGraphOptions(showTrails: showTrails, showSnippet: showSnippet, showGrid: showGrid)
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscape
            } else {
                portrait
            }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            Group {
                if model.isSynthMode {
                    FullscreenSynthGraphView(appearance: appearance, options: synthOptions)
                } else {
                    FullscreenGraphView(appearance: appearance)
                }
            }
            .environment(model)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet()
                .environment(model)
        }
    }

    // MARK: Portrait

    private var portrait: some View {
        GeometryReader { geometry in
            ScrollView {
                portraitContent(plotHeight: min(320, max(200, geometry.size.height * 0.32)))
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func portraitContent(plotHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            DemonHeader()
            ModePicker()
            if model.isSynthMode {
                SynthGraphCard(appearance: appearance, options: synthOptions, plotHeight: synthPlotHeight(plotHeight),
                               onFullscreen: { showFullscreen = true })
                if model.mode == .pendulum {
                    PendulumStageView()
                }
                TransportControls()
                    .padding(.horizontal, 4)
                SynthGraphOptionsBar(showTrails: $showTrails, showSnippet: $showSnippet)
                SynthControlCards(onExport: { showExport = true })
            } else {
                FormulaEditorCard()
                GraphCard(appearance: appearance, plotHeight: plotHeight, onFullscreen: { showFullscreen = true })
                TransportControls()
                    .padding(.horizontal, 4)
                SoundModeCard(appearance: appearance)
                ParameterCard()
                PlaybackCard()
                AdvancedSettingsCard()
                ExportEntryCard(onExport: { showExport = true })
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 28)
    }

    /// More lanes need more height.
    private func synthPlotHeight(_ base: CGFloat) -> CGFloat {
        let lanes = max(model.synthGraph.lanes.count + (showSnippet ? 1 : 0), 1)
        return min(520, max(base, CGFloat(lanes) * 92))
    }

    // MARK: Landscape

    private var landscape: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 14) {
                // Left: the graph gets the full height.
                Group {
                    if model.isSynthMode {
                        VStack(spacing: 8) {
                            SynthGraphCard(appearance: appearance, options: synthOptions, plotHeight: nil, compact: true,
                                           onFullscreen: { showFullscreen = true })
                            if model.mode == .pendulum {
                                PendulumStageView()
                            }
                        }
                    } else {
                        GraphCard(appearance: appearance, plotHeight: nil, compact: true, onFullscreen: { showFullscreen = true })
                    }
                }
                .frame(maxHeight: .infinity)

                // Right: mode and transport always visible, the remaining controls scroll.
                VStack(spacing: 10) {
                    ModePicker(compact: true)
                    TransportControls(compact: true)
                    ScrollView {
                        VStack(spacing: 16) {
                            if model.isSynthMode {
                                SynthGraphOptionsBar(showTrails: $showTrails, showSnippet: $showSnippet)
                                SynthControlCards(onExport: { showExport = true })
                            } else {
                                FormulaEditorCard()
                                SoundModeCard(appearance: appearance)
                                ParameterCard()
                                PlaybackCard()
                                AdvancedSettingsCard()
                                ExportEntryCard(onExport: { showExport = true })
                            }
                            DemonHeader(compact: true)
                        }
                        .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(width: min(max(geometry.size.width * 0.44, 320), 460))
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }
}

/// Display options of the synthesizer graph (trails and audio snippet).
struct SynthGraphOptionsBar: View {
    @Binding var showTrails: Bool
    @Binding var showSnippet: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showTrails.toggle()
            } label: {
                Label("Spuren", systemImage: "scribble.variable")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle(isActive: showTrails))
            .accessibilityLabel("Leuchtspuren")
            .accessibilityValue(showTrails ? "ein" : "aus")
            .accessibilityIdentifier("toggleTrails")
            Button {
                showSnippet.toggle()
            } label: {
                Label("Audioausschnitt", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle(isActive: showSnippet))
            .accessibilityLabel("Audioausschnitt mit Millisekundenachse")
            .accessibilityValue(showSnippet ? "ein" : "aus")
            .accessibilityIdentifier("toggleSnippet")
        }
    }
}

/// Enlarged graph with compact transport. Uses the full screen, especially in landscape.
struct FullscreenGraphView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var appearance: GraphAppearance

    var body: some View {
        ZStack {
            DemonBackground()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("f(x) = \(model.formulaDisplayBody)")
                        .font(.headline.weight(.bold).monospaced())
                        .foregroundStyle(DemonTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if verticalSizeClass == .compact {
                        GraphToolbar(onFullscreen: nil, iconsOnly: true)
                    }
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(DemonRuneButtonStyle(minWidth: 52))
                    .accessibilityLabel("Vergrößerte Ansicht schließen")
                    .accessibilityIdentifier("closeFullscreen")
                }

                GraphView(appearance: appearance)
                    .clipShape(DemonPanelShape(cornerCut: 12, spike: 0))
                    .overlay(DemonPanelShape(cornerCut: 12, spike: 0).stroke(DemonTheme.metalStroke, lineWidth: 1.6))
                    .frame(maxHeight: .infinity)

                if verticalSizeClass == .compact {
                    HStack(alignment: .center, spacing: 12) {
                        PlaybackReadoutView(compact: true)
                            .frame(maxWidth: 320)
                        TransportControls(compact: true)
                    }
                } else {
                    PlaybackReadoutView()
                    TransportControls(compact: true)
                    GraphToolbar(onFullscreen: nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .preferredColorScheme(.dark)
    }
}
