import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case graph
    case presets
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graph: return "Graph & Klang"
        case .presets: return "Presets"
        case .settings: return "Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .graph: return "waveform.path.ecg"
        case .presets: return "square.stack.3d.up.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Root: dark background, the three main areas and the custom demonic tab bar.
struct RootView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.selectedTab) private var selectedTabRaw = AppTab.graph.rawValue

    private var selectedTab: Binding<AppTab> {
        Binding(get: { AppTab(rawValue: selectedTabRaw) ?? .graph },
                set: { selectedTabRaw = $0.rawValue })
    }

    var body: some View {
        ZStack {
            DemonBackground()
            Group {
                switch selectedTab.wrappedValue {
                case .graph:
                    GraphSoundView()
                case .presets:
                    PresetsView(onLoad: { selectedTab.wrappedValue = .graph })
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DemonTabBar(selection: selectedTab)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
    }
}

struct DemonTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: verticalSizeClass == .compact ? 17 : 20, weight: .semibold))
                        if verticalSizeClass != .compact {
                            Text(tab.title)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        DiamondShape()
                            .fill(isSelected ? DemonTheme.neonGreen : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(isSelected ? DemonTheme.green : DemonTheme.textTertiary)
                    .shadow(color: isSelected ? DemonTheme.green.opacity(0.7) : .clear, radius: 6)
                    .frame(maxWidth: .infinity, minHeight: verticalSizeClass == .compact ? 40 : 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            DemonPanelShape(cornerCut: 16, spike: 6)
                .fill(DemonTheme.cardFill)
                .shadow(color: .black.opacity(0.7), radius: 12, y: -2)
        }
        .overlay {
            DemonPanelShape(cornerCut: 16, spike: 6)
                .stroke(DemonTheme.metalStroke, lineWidth: 1.5)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }
}
