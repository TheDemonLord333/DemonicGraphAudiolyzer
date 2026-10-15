import SwiftUI

/// Formula input of the classic modes with math keyboard, readable notation, signature help,
/// validity status and error position.
struct FormulaEditorCard: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Formel", systemImage: "function")
            FormulaFieldEditor(text: $model.formulaText,
                               title: "Formel",
                               meaning: meaning,
                               meaningIcon: model.settings.mode == .graph ? "chart.xyaxis.line" : "waveform",
                               context: .classic,
                               error: model.formulaError,
                               warnings: model.parsedFormula?.warnings ?? [],
                               advanced: $model.classicAdvancedEditor,
                               outputLabel: "f(x)",
                               inlinePrefix: "f(x) =",
                               fieldIdentifier: "formulaField",
                               clearIdentifier: "clearFormula",
                               onHelp: { topic in model.showGuide(topic: topic) })
            if model.formulaError == nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(DemonTheme.green)
                    Text(validStatusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DemonTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("formulaStatus")
            }
        }
        .demonCard()
    }

    private var meaning: String {
        switch model.settings.mode {
        case .graph: return "Graph y = f(x) → Tonhöhe über den Klangbereich"
        case .waveform: return "Audiosignal: eine Periode über dem Abschnitt"
        default: return "Formel"
        }
    }

    private var validStatusText: String {
        let parameters = model.usedParameters.map(\.rawValue)
        if parameters.isEmpty {
            return model.parsedFormula?.usesX == false ? "Gültig – konstante Funktion" : "Formel gültig"
        }
        return "Formel gültig · Parameter: " + parameters.joined(separator: ", ")
    }
}
