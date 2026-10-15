import Foundation

/// The main areas in the order of the bottom navigation:
/// Graph & Klang, Presets, Anleitungen, Einstellungen.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case graph
    case presets
    case guides
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graph: return "Graph & Klang"
        case .presets: return "Presets"
        case .guides: return "Anleitungen"
        case .settings: return "Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .graph: return "waveform.path.ecg"
        case .presets: return "square.stack.3d.up.fill"
        case .guides: return "book.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
