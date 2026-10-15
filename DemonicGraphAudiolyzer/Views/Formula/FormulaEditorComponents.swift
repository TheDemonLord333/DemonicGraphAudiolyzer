import SwiftUI
import UIKit

/// Editor for one formula: simple (single line) or advanced (multi-line) input, readable
/// notation, signature help with the active argument, help button, visual editors for case
/// distinctions and sums/products, errors with line and position.
struct FormulaFieldEditor: View {
    @Binding var text: String
    var title: String
    /// Meaning of the output, always visible ("Tonhöhe · Halbtöne relativ zur Grundfrequenz").
    var meaning: String?
    var meaningIcon: String?
    var context: FormulaContext
    /// Other definition sources (project, voice) for the readable notation.
    var definitions: [String] = []
    var error: FormulaError?
    var warnings: [FormulaWarning] = []
    @Binding var advanced: Bool
    var outputLabel = "y"
    var inlinePrefix: String?
    var activeCase: Int?
    /// Active case while playing (highlighted live in the readable notation).
    var liveCase: (() -> Int?)?
    var requiresOutput = true
    var fieldIdentifier = "formulaField"
    var clearIdentifier: String?
    var onHelp: (String?) -> Void

    @State private var cursor = 0
    @State private var piecewiseItem: PiecewiseItem?
    @State private var aggregateItem: AggregateItem?
    @State private var replaceRange: Range<Int>?

    private var layout: MathKeyboardLayout { context == .classic ? .classic : .synth }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let meaning {
                DemonBadge(text: meaning, icon: meaningIcon, tint: DemonTheme.green)
                    .accessibilityLabel("Bedeutung der Ausgabe: \(meaning)")
            }
            input
            if let signature = FormulaTextTools.signature(in: text, cursor: cursor) {
                SignatureHintView(signature: signature) {
                    onHelp(signature.isBuiltIn ? signature.functionName : nil)
                }
            }
            if let error {
                FormulaErrorView(error: error, source: text)
            }
            ForEach(warnings.indices, id: \.self) { index in
                Label(warnings[index].message, systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xFFC857))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let program = FormulaDisplay.program(text, context: context, definitions: definitions, requiresOutput: requiresOutput),
               !program.statements.isEmpty, error == nil {
                Group {
                    if let liveCase {
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                            MathProgramView(program: program, outputLabel: outputLabel, size: 17, activeCase: liveCase())
                        }
                    } else {
                        MathProgramView(program: program, outputLabel: outputLabel, size: 17, activeCase: activeCase)
                    }
                }
                .demonInset(tint: DemonTheme.blurple.opacity(0.6), padding: 8)
            }
            toolbar
        }
        .sheet(item: $piecewiseItem) { item in
            PiecewiseEditorSheet(draft: item.draft, context: context) { result in
                insert(result.formulaText)
                piecewiseItem = nil
            } onCancel: {
                piecewiseItem = nil
            }
        }
        .sheet(item: $aggregateItem) { item in
            AggregateEditorSheet(draft: item.draft, context: context) { result in
                insert(result.formulaText)
                aggregateItem = nil
            } onCancel: {
                aggregateItem = nil
            }
        }
    }

    private var input: some View {
        HStack(alignment: advanced ? .top : .center, spacing: 8) {
            if let inlinePrefix, !advanced {
                Text(inlinePrefix)
                    .font(.headline.weight(.heavy).monospaced())
                    .foregroundStyle(DemonTheme.blurpleText)
                    .accessibilityHidden(true)
            }
            if advanced {
                FormulaTextView(text: $text, isInvalid: error != nil, cursor: $cursor, layout: layout,
                                identifier: fieldIdentifier, accessibilityName: title)
                    .frame(minHeight: 88)
            } else {
                FormulaTextField(text: $text, isInvalid: error != nil, cursor: $cursor, layout: layout,
                                 placeholder: context == .classic ? "z. B. sin(x) oder y = 2x^2" : "Formel eingeben",
                                 identifier: fieldIdentifier, accessibilityName: title)
                    .frame(minHeight: 50)
            }
            if !text.isEmpty, let clearIdentifier {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DemonTheme.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) löschen")
                .accessibilityIdentifier(clearIdentifier)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .background(DemonPanelShape(cornerCut: 10, spike: 0).fill(Color.black.opacity(0.55)))
        .overlay(DemonPanelShape(cornerCut: 10, spike: 0)
            .stroke(error == nil ? DemonTheme.green.opacity(0.75) : DemonTheme.danger, lineWidth: 1.4))
        .shadow(color: (error == nil ? DemonTheme.green : DemonTheme.danger).opacity(0.25), radius: 6)
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    advanced.toggle()
                } label: {
                    Label(advanced ? "Einfach" : "Erweitert", systemImage: advanced ? "text.line.first.and.arrowtriangle.forward" : "text.alignleft")
                }
                .buttonStyle(DemonChipButtonStyle(isActive: advanced))
                .accessibilityHint(advanced ? "Eine Formel in einer Zeile" : "Mehrere Zeilen mit Definitionen, Listen und Hilfsfunktionen")
                .accessibilityIdentifier("\(fieldIdentifier)-advanced")

                Button {
                    openPiecewiseEditor()
                } label: {
                    Label("Fälle", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(DemonChipButtonStyle())
                .accessibilityLabel("Fallunterscheidung bearbeiten")

                Button {
                    openAggregateEditor()
                } label: {
                    Label("Σ / Π", systemImage: "sum")
                }
                .buttonStyle(DemonChipButtonStyle())
                .accessibilityLabel("Summe oder Produkt bearbeiten")

                Button {
                    onHelp(FormulaTextTools.helpTopic(in: text, cursor: cursor))
                } label: {
                    Label("Hilfe", systemImage: "questionmark.circle")
                }
                .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
                .accessibilityLabel("Anleitung zur Funktion am Cursor öffnen")
                .accessibilityIdentifier("\(fieldIdentifier)-help")
            }
            .padding(.vertical, 1)
        }
    }

    private func openPiecewiseEditor() {
        if let call = FormulaTextTools.enclosingCall(in: text, cursor: cursor, names: ["piecewise", "if"]),
           let draft = PiecewiseDraft(call: call) {
            replaceRange = call.range
            piecewiseItem = PiecewiseItem(draft: draft)
        } else {
            replaceRange = nil
            piecewiseItem = PiecewiseItem(draft: .empty)
        }
    }

    private func openAggregateEditor() {
        if let call = FormulaTextTools.enclosingCall(in: text, cursor: cursor, names: ["sum", "prod"]),
           let draft = AggregateDraft(call: call) {
            replaceRange = call.range
            aggregateItem = AggregateItem(draft: draft)
        } else {
            replaceRange = nil
            aggregateItem = AggregateItem(draft: .sumExample)
        }
    }

    /// Replaces the edited call or inserts at the cursor (the whole formula if it was empty).
    private func insert(_ snippet: String) {
        if let replaceRange {
            text = FormulaTextTools.replacing(replaceRange, in: text, with: snippet)
        } else if text.trimmed.isEmpty {
            text = snippet
        } else {
            let position = min(max(cursor, 0), text.count)
            text = FormulaTextTools.replacing(position..<position, in: text, with: snippet)
        }
        replaceRange = nil
    }
}

/// Drafts with a stable identity for `.sheet(item:)`.
private struct PiecewiseItem: Identifiable {
    let id = UUID()
    var draft: PiecewiseDraft
}

private struct AggregateItem: Identifiable {
    let id = UUID()
    var draft: AggregateDraft
}

/// Signature with named argument positions; the argument at the cursor is highlighted.
struct SignatureHintView: View {
    let signature: SignatureContext
    var onHelp: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                signatureText
                    .font(.callout.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                if let meaning = signature.activeMeaning {
                    Text(meaning)
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if signature.isBuiltIn {
                Button(action: onHelp) {
                    Image(systemName: "book.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DemonTheme.neonGreen)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anleitung zu \(signature.functionName) öffnen")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DemonPanelShape(cornerCut: 8, spike: 0).fill(DemonTheme.blurple.opacity(0.14)))
        .overlay(DemonPanelShape(cornerCut: 8, spike: 0).stroke(DemonTheme.blurple.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signatur \(signature.syntax), aktuelles Argument \(currentName)")
        .accessibilityIdentifier("signatureHint")
    }

    private var currentName: String {
        signature.argumentNames.indices.contains(signature.activeArgument) ? signature.argumentNames[signature.activeArgument] : ""
    }

    private var signatureText: Text {
        var result = Text(signature.functionName + "(").foregroundColor(DemonTheme.neonGreen)
        for (index, name) in signature.argumentNames.enumerated() {
            if index > 0 { result = result + Text(", ").foregroundColor(DemonTheme.textTertiary) }
            if index == signature.activeArgument {
                result = result + Text(name).bold().underline().foregroundColor(DemonTheme.greenCore)
            } else {
                result = result + Text(name).foregroundColor(DemonTheme.textSecondary)
            }
        }
        return result + Text(")").foregroundColor(DemonTheme.neonGreen)
    }
}

/// Error message with the faulty part highlighted (only the affected line for programs).
struct FormulaErrorView: View {
    let error: FormulaError
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DemonTheme.danger)

            if let range = error.range, !source.isEmpty {
                Text(highlighted(range: range))
                    .font(.body.monospaced())
                    .accessibilityLabel("Fehler an Position \(error.column ?? range.start + 1)")
            }
            if let hint = error.hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(DemonTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DemonPanelShape(cornerCut: 8, spike: 0).fill(DemonTheme.danger.opacity(0.10)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("formulaError")
    }

    private var headline: String {
        var parts: [String] = []
        if let source = error.sourceName { parts.append(source) }
        if let line = error.line { parts.append("Zeile \(line)") }
        if let column = error.column { parts.append("Position \(column)") }
        return parts.isEmpty ? error.message : parts.joined(separator: ", ") + ": " + error.message
    }

    /// The line containing the error with the faulty characters marked.
    private func highlighted(range: SourceRange) -> AttributedString {
        let characters = Array(source)
        var lineStart = min(range.start, characters.count)
        while lineStart > 0, characters[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = min(range.start, characters.count)
        while lineEnd < characters.count, characters[lineEnd] != "\n" { lineEnd += 1 }
        var result = AttributedString()
        for index in lineStart..<lineEnd {
            var piece = AttributedString(String(characters[index]))
            if index >= range.start && index < range.end {
                piece.foregroundColor = DemonTheme.danger
                piece.backgroundColor = DemonTheme.danger.opacity(0.22)
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: DemonTheme.danger)
            } else {
                piece.foregroundColor = DemonTheme.textSecondary
            }
            result += piece
        }
        if range.start >= lineEnd {
            var marker = AttributedString(" ␣")
            marker.foregroundColor = DemonTheme.danger
            marker.backgroundColor = DemonTheme.danger.opacity(0.22)
            result += marker
        }
        return result
    }
}

// MARK: - Visual editors

/// Visual editor for case distinctions: condition and expression per case, "weiterer Fall",
/// "Sonst-Fall". Produces piecewise(c1, e1, …, default).
struct PiecewiseEditorSheet: View {
    @State var draft: PiecewiseDraft
    let context: FormulaContext
    var onApply: (PiecewiseDraft) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DemonBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        DemonCaption("Die Bedingungen werden von oben nach unten geprüft; die erste wahre wählt ihren Ausdruck. Trifft keine zu, gilt der Sonst-Fall. Nur der gewählte Ausdruck wird berechnet.")
                        ForEach($draft.cases) { $item in
                            caseCard(item: $item, index: draft.cases.firstIndex(where: { $0.id == item.id }) ?? 0)
                        }
                        Button {
                            draft.cases.append(PiecewiseDraft.Case(condition: "", expression: ""))
                        } label: {
                            Label("Weiteren Fall hinzufügen", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
                        .accessibilityIdentifier("addCase")

                        VStack(alignment: .leading, spacing: 8) {
                            DemonSectionHeader(title: "Sonst-Fall", systemImage: "arrow.uturn.down")
                            editorField("Ausdruck, wenn keine Bedingung zutrifft", text: $draft.otherwise)
                        }
                        .demonCard(padding: 12)

                        VStack(alignment: .leading, spacing: 6) {
                            DemonSubheader("Ergebnis")
                            Text(draft.formulaText)
                                .font(.callout.monospaced())
                                .foregroundStyle(DemonTheme.green)
                                .textSelection(.enabled)
                            if let program = FormulaDisplay.program(draft.formulaText, context: context) {
                                MathProgramView(program: program, size: 16)
                            }
                        }
                        .demonCard(padding: 12)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Fallunterscheidung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DemonTheme.void, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { onApply(draft) }
                        .disabled(!draft.missingParts.isEmpty)
                        .accessibilityIdentifier("applyPiecewise")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func caseCard(item: Binding<PiecewiseDraft.Case>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DemonSectionHeader(title: "Fall \(index + 1)", systemImage: "arrow.triangle.branch")
                if draft.cases.count > 1 {
                    Button(role: .destructive) {
                        draft.cases.removeAll { $0.id == item.wrappedValue.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(DemonTheme.danger)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fall \(index + 1) entfernen")
                }
            }
            editorField("Bedingung (z. B. x < 0)", text: item.condition)
            editorField("Ausdruck, falls die Bedingung zutrifft", text: item.expression)
        }
        .demonCard(padding: 12)
    }

    private func editorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.textTertiary)
            TextField(title, text: text)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(DemonTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(DemonPanelShape(cornerCut: 7, spike: 0).fill(Color.black.opacity(0.45)))
                .overlay(DemonPanelShape(cornerCut: 7, spike: 0).stroke(DemonTheme.metalMid.opacity(0.85), lineWidth: 1))
        }
    }
}

/// Visual editor for sums and products: loop variable, start, end, expression.
struct AggregateEditorSheet: View {
    @State var draft: AggregateDraft
    let context: FormulaContext
    var onApply: (AggregateDraft) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DemonBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        DemonSegmentedPicker(title: "Art", selection: $draft.kind,
                                             options: [(value: AggregateKind.sum, title: "Summe Σ"), (value: AggregateKind.prod, title: "Produkt Π")])
                        GuideDiagramView(diagram: .bigOperator(symbol: draft.kind == .sum ? "Σ" : "Π",
                                                               variable: draft.variable.isEmpty ? "i" : draft.variable,
                                                               start: draft.start.isEmpty ? "start" : draft.start,
                                                               end: draft.end.isEmpty ? "ende" : draft.end,
                                                               body: draft.body.isEmpty ? "ausdruck" : draft.body))
                        VStack(alignment: .leading, spacing: 10) {
                            field("1 · Laufvariable (Name, z. B. i)", text: $draft.variable)
                            if !draft.variable.isEmpty && !draft.variableIsValid {
                                DemonCaption("Die Laufvariable muss ein einfacher Name sein (Buchstabe, dann Buchstaben, Ziffern oder _).", warning: true)
                            }
                            field("2 · Start (erster ganzzahliger Wert)", text: $draft.start)
                            field("3 · Ende (letzter Wert, einschließlich)", text: $draft.end)
                            field("4 · Ausdruck für jeden Wert", text: $draft.body)
                        }
                        .demonCard(padding: 12)
                        DemonCaption("Die Laufvariable gilt nur im Ausdruck. Ist das Ende kleiner als der Start, ergibt die Summe 0 und das Produkt 1.")
                        VStack(alignment: .leading, spacing: 6) {
                            DemonSubheader("Ergebnis")
                            Text(draft.formulaText)
                                .font(.callout.monospaced())
                                .foregroundStyle(DemonTheme.green)
                                .textSelection(.enabled)
                        }
                        .demonCard(padding: 12)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(draft.kind == .sum ? "Summe" : "Produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DemonTheme.void, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { onApply(draft) }
                        .disabled(!draft.missingParts.isEmpty || !draft.variableIsValid)
                        .accessibilityIdentifier("applyAggregate")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.textTertiary)
            TextField(title, text: text)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(DemonTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(DemonPanelShape(cornerCut: 7, spike: 0).fill(Color.black.opacity(0.45)))
                .overlay(DemonPanelShape(cornerCut: 7, spike: 0).stroke(DemonTheme.metalMid.opacity(0.85), lineWidth: 1))
        }
    }
}
