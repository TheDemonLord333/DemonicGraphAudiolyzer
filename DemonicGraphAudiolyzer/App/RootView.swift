import SwiftUI

/// Root: dark background, the four main areas and the custom demonic tab bar.
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
                case .guides:
                    GuidesView()
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DemonTabBar(selection: selectedTab)
                    .background(alignment: .bottom) {
                        // Hides scrolled content below and behind the floating tab bar.
                        LinearGradient(colors: [DemonTheme.void.opacity(0), DemonTheme.void.opacity(0.94), DemonTheme.void],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.top, -28)
                            .ignoresSafeArea(edges: .bottom)
                            .allowsHitTesting(false)
                    }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
        .onChange(of: model.requestedTab) { _, tab in
            // Help buttons open "Anleitungen", "Im Editor öffnen" returns to "Graph & Klang".
            guard let tab else { return }
            selectedTab.wrappedValue = tab
            model.requestedTab = nil
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
