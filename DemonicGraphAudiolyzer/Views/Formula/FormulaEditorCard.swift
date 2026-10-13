import SwiftUI

/// Formula input with math keyboard, validity status and error position.
struct FormulaEditorCard: View {
    @Environment(AudiolyzerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Formel", systemImage: "function")
            HStack(spacing: 8) {
                Text("f(x) =")
                    .font(.headline.weight(.heavy).monospaced())
                    .foregroundStyle(DemonTheme.blurpleText)
                    .accessibilityHidden(true)
                FormulaTextField(text: $model.formulaText, isInvalid: model.formulaError != nil)
                    .frame(minHeight: 50)
                if !model.formulaText.isEmpty {
                    Button {
                        model.formulaText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DemonTheme.textTertiary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Formel löschen")
                    .accessibilityIdentifier("clearFormula")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .background(DemonPanelShape(cornerCut: 10, spike: 0).fill(Color.black.opacity(0.55)))
            .overlay(DemonPanelShape(cornerCut: 10, spike: 0)
                .stroke(model.formulaError == nil ? DemonTheme.green.opacity(0.75) : DemonTheme.danger, lineWidth: 1.4))
            .shadow(color: (model.formulaError == nil ? DemonTheme.green : DemonTheme.danger).opacity(0.25), radius: 6)

            if let error = model.formulaError {
                FormulaErrorView(error: error, source: model.formulaText)
            } else {
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

    private var validStatusText: String {
        let parameters = model.usedParameters.map(\.rawValue)
        if parameters.isEmpty {
            return model.parsedFormula?.usesX == false ? "Gültig – konstante Funktion" : "Formel gültig"
        }
        return "Formel gültig · Parameter: " + parameters.joined(separator: ", ")
    }
}

/// Error message with the faulty part of the formula highlighted.
struct FormulaErrorView: View {
    let error: FormulaError
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(error.message)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DemonTheme.danger)

            if let range = error.range, !source.isEmpty {
                Text(highlighted(source, range: range))
                    .font(.body.monospaced())
                    .accessibilityLabel("Fehler an Position \(range.start + 1)")
            }
            if let hint = error.hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(DemonTheme.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DemonPanelShape(cornerCut: 8, spike: 0).fill(DemonTheme.danger.opacity(0.10)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("formulaError")
    }

    private func highlighted(_ text: String, range: SourceRange) -> AttributedString {
        var result = AttributedString()
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            var piece = AttributedString(String(character))
            if index >= range.start && index < range.end {
                piece.foregroundColor = DemonTheme.danger
                piece.backgroundColor = DemonTheme.danger.opacity(0.22)
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: DemonTheme.danger)
            } else {
                piece.foregroundColor = DemonTheme.textSecondary
            }
            result += piece
        }
        if range.start >= characters.count {
            var marker = AttributedString(" ␣")
            marker.foregroundColor = DemonTheme.danger
            marker.backgroundColor = DemonTheme.danger.opacity(0.22)
            result += marker
        }
        return result
    }
}
