import SwiftUI

/// Main screen "Graph & Klang". Portrait: one scrolling column. Landscape: the graph takes
/// the left side at full height, the controls scroll on the right.
struct GraphSoundView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @AppStorage(PreferenceKey.lightGraph) private var lightGraph = false
    @AppStorage(PreferenceKey.showGrid) private var showGrid = true
    @AppStorage(PreferenceKey.showPreview) private var showPreview = true
    @AppStorage(PreferenceKey.showCursorLine) private var showCursorLine = true

    @State private var showFullscreen = false
    @State private var showExport = false

    private var appearance: GraphAppearance {
        GraphAppearance(isLight: lightGraph, showGrid: showGrid, showPreview: showPreview, showCursorLine: showCursorLine)
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
            FullscreenGraphView(appearance: appearance)
                .environment(model)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet()
                .environment(model)
        }
    }

    private var portrait: some View {
        ScrollView {
            VStack(spacing: 18) {
                DemonHeader()
                FormulaEditorCard()
                GraphCard(appearance: appearance, plotHeight: 300, onFullscreen: { showFullscreen = true })
                TransportControls()
                    .padding(.horizontal, 4)
                SoundModeCard(appearance: appearance)
                ParameterCard()
                PlaybackCard()
                AdvancedSettingsCard()
                ExportEntryCard(onExport: { showExport = true })
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var landscape: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    GraphCard(appearance: appearance, plotHeight: nil, onFullscreen: { showFullscreen = true })
                    TransportControls(compact: true)
                }
                .frame(maxHeight: .infinity)

                ScrollView {
                    VStack(spacing: 16) {
                        DemonHeader(compact: true)
                        FormulaEditorCard()
                        SoundModeCard(appearance: appearance)
                        ParameterCard()
                        PlaybackCard()
                        AdvancedSettingsCard()
                        ExportEntryCard(onExport: { showExport = true })
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(width: min(max(geometry.size.width * 0.4, 300), 440))
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
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
                    HStack(alignment: .center, spacing: 16) {
                        PlaybackReadoutView()
                            .frame(maxWidth: 360)
                        TransportControls(compact: true)
                        GraphToolbar(onFullscreen: nil)
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
