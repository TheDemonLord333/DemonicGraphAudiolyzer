import SwiftUI
import UIKit

/// "Anleitungen": offline reference of all symbols, functions, variables, formula roles,
/// generators and presets. Search by symbol (Σ), German name (Summe) or command (sum).
struct GuidesView: View {
    @Environment(AudiolyzerModel.self) private var model
    @State private var query = ""
    @State private var category: GuideCategory?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DemonBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        DemonHeader(compact: true)
                            .padding(.top, 4)
                        searchField
                        categoryChips
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                if let entry = GuideCatalog.entry(id: id) {
                    GuideEntryView(entry: entry)
                } else {
                    ZStack {
                        DemonBackground()
                        DemonCaption("Diese Anleitung gibt es nicht.")
                    }
                }
            }
        }
        .onAppear(perform: consumeRequest)
        .onChange(of: model.requestedGuideEntry) { _, _ in consumeRequest() }
    }

    private func consumeRequest() {
        guard let id = model.requestedGuideEntry else { return }
        model.requestedGuideEntry = nil
        path = [id]
    }

    private var results: [GuideEntry] {
        let found = GuideCatalog.search(query)
        guard let category else { return found }
        return found.filter { $0.category == category }
    }

    @ViewBuilder
    private var content: some View {
        let entries = results
        if entries.isEmpty {
            DemonCaption("Keine Anleitung zu „\(query)“ gefunden. Versuche ein Symbol (Σ, π, √), einen deutschen Namen (Summe, Betrag) oder einen Befehl (sum, abs).")
                .padding(.top, 8)
        } else if query.trimmed.isEmpty {
            ForEach(GuideCategory.allCases.filter { category == nil || $0 == category }) { group in
                let items = entries.filter { $0.category == group }
                if !items.isEmpty {
                    DemonSectionHeader(title: group.title, systemImage: group.icon)
                        .padding(.top, 8)
                    ForEach(items) { entry in
                        GuideRow(entry: entry)
                    }
                }
            }
        } else {
            Text("\(entries.count) Treffer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.textTertiary)
                .accessibilityIdentifier("guideResultCount")
            ForEach(entries) { entry in
                GuideRow(entry: entry)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DemonTheme.green)
            TextField("Suchen: Σ, Summe, sum, Betrag …", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .foregroundStyle(DemonTheme.textPrimary)
                .accessibilityLabel("Anleitungen durchsuchen")
                .accessibilityIdentifier("guideSearch")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DemonTheme.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(DemonPanelShape(cornerCut: 10, spike: 0).fill(Color.black.opacity(0.55)))
        .overlay(DemonPanelShape(cornerCut: 10, spike: 0).stroke(DemonTheme.green.opacity(0.7), lineWidth: 1.3))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    category = nil
                } label: {
                    Text("Alle")
                }
                .buttonStyle(DemonChipButtonStyle(isActive: category == nil))
                .accessibilityIdentifier("guideCategory-all")
                ForEach(GuideCategory.allCases) { item in
                    Button {
                        category = category == item ? nil : item
                    } label: {
                        Label(item.title, systemImage: item.icon)
                    }
                    .buttonStyle(DemonChipButtonStyle(isActive: category == item))
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                    .accessibilityIdentifier("guideCategory-\(item.rawValue)")
                }
            }
        }
    }
}

/// One entry in the list: symbol, title, short explanation.
struct GuideRow: View {
    let entry: GuideEntry

    var body: some View {
        NavigationLink(value: entry.id) {
            HStack(spacing: 12) {
                Text(entry.symbol)
                    .font(.system(size: entry.symbol.count > 3 ? 13 : 20, weight: .bold, design: .serif))
                    .foregroundStyle(DemonTheme.neonGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 56, height: 48)
                    .background(DemonRuneShape().fill(DemonTheme.green.opacity(0.12)))
                    .overlay(DemonRuneShape().stroke(DemonTheme.metalStroke, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DemonTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(entry.explanation)
                        .font(.caption)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !entry.commands.isEmpty {
                        Text(entry.commands.prefix(4).joined(separator: " · "))
                            .font(.caption2.monospaced())
                            .foregroundStyle(DemonTheme.blurpleText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DemonTheme.textTertiary)
            }
            .padding(10)
            .background(DemonPanelShape(cornerCut: 9, spike: 0).fill(DemonTheme.cardFill))
            .overlay(DemonPanelShape(cornerCut: 9, spike: 0).stroke(DemonTheme.metalMid.opacity(0.7), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(entry.symbol)")
        .accessibilityIdentifier("guideEntry-\(entry.id)")
    }
}

/// Complete guide entry: symbol, readable notation, diagram, explanation, exact syntax,
/// argument table, examples (copy and open in editor), graph example, notes.
struct GuideEntryView: View {
    @Environment(AudiolyzerModel.self) private var model
    let entry: GuideEntry
    @State private var pendingPayload: EditorPayload?
    @State private var copiedText: String?

    var body: some View {
        ZStack {
            DemonBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if let diagram = entry.diagram {
                        VStack(alignment: .leading, spacing: 10) {
                            DemonSectionHeader(title: "Eingabe und Darstellung", systemImage: "arrow.left.arrow.right")
                            GuideDiagramView(diagram: diagram)
                        }
                        .demonCard()
                    }
                    syntaxCard
                    if !entry.arguments.isEmpty {
                        argumentsCard
                    }
                    if !entry.examples.isEmpty {
                        examplesCard
                    }
                    if let graph = entry.graphExample {
                        graphCard(graph)
                    }
                    if !entry.notes.isEmpty {
                        notesCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DemonTheme.void, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog("Aktuelle Änderungen ersetzen?",
                            isPresented: Binding(get: { pendingPayload != nil }, set: { if !$0 { pendingPayload = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingPayload) { payload in
            Button("Ersetzen und öffnen", role: .destructive) {
                model.openInEditor(payload)
                pendingPayload = nil
            }
            .accessibilityIdentifier("confirmReplace")
            Button("Abbrechen", role: .cancel) { pendingPayload = nil }
        } message: { _ in
            Text("Im Editor gibt es ungespeicherte Änderungen. Das Beispiel ersetzt die aktuelle Formel bzw. das aktuelle Projekt. Speichere vorher ein Preset, wenn du den Stand behalten möchtest.")
        }
        .accessibilityIdentifier("guideDetail-\(entry.id)")
    }

    // MARK: Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Text(entry.symbol)
                    .font(.system(size: entry.symbol.count > 3 ? 22 : 42, weight: .bold, design: .serif))
                    .foregroundStyle(DemonTheme.neonGreen)
                    .shadow(color: DemonTheme.green.opacity(0.7), radius: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(minWidth: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(DemonTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    DemonBadge(text: entry.category.title, icon: entry.category.icon)
                }
            }
            if let notation = entry.mathNotation {
                Text(notation)
                    .font(.callout.italic())
                    .foregroundStyle(DemonTheme.blurpleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if entry.isGeneratorSetting {
                DemonBadge(text: "Generator-Einstellung – keine frei eingegebene Formel", icon: "slider.horizontal.3",
                           tint: Color(hex: 0xFFC857))
            }
            Text(entry.explanation)
                .font(.subheadline)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if entry.commands.count > 0 {
                Text("Schreibweisen: " + entry.commands.joined(separator: "  ·  "))
                    .font(.caption.monospaced())
                    .foregroundStyle(DemonTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .demonCard(crest: true)
    }

    private var syntaxCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Exakte Eingabe", systemImage: "keyboard")
            HStack(alignment: .top, spacing: 8) {
                Text(entry.syntax)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(DemonTheme.green)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("guideSyntax")
                Spacer(minLength: 4)
                copyButton(entry.syntax, identifier: "copySyntax")
            }
            if let program = readableProgram(entry.syntax) {
                MathProgramView(program: program, outputLabel: "y", size: 17)
                    .demonInset(tint: DemonTheme.blurple.opacity(0.6), padding: 8)
            }
        }
        .demonCard()
    }

    private var argumentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Argumente", systemImage: "list.number")
            ForEach(entry.arguments.indices, id: \.self) { index in
                let argument = entry.arguments[index]
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(argument.position)")
                            .font(.caption.weight(.black).monospacedDigit())
                            .foregroundStyle(DemonTheme.void)
                            .frame(width: 22, height: 22)
                            .background(DiamondShape().fill(argumentColor(index)))
                        Text(argument.name)
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(argumentColor(index))
                        if argument.isOptional {
                            DemonBadge(text: "optional", tint: DemonTheme.textTertiary)
                        }
                    }
                    Text(argument.meaning)
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let position = argument.mathPosition {
                        Text("In der Darstellung: \(position)")
                            .font(.caption)
                            .foregroundStyle(DemonTheme.blurpleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let allowed = argument.allowed {
                        Text("Erlaubt: \(allowed)")
                            .font(.caption)
                            .foregroundStyle(DemonTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .demonCard()
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Beispiele", systemImage: "text.badge.checkmark")
            ForEach(entry.examples.indices, id: \.self) { index in
                exampleView(entry.examples[index], index: index)
            }
        }
        .demonCard()
    }

    private func exampleView(_ example: GuideExample, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(example.input)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundStyle(DemonTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let program = readableProgram(example.input) {
                MathProgramView(program: program, outputLabel: "y", size: 15)
            }
            Text("→ " + example.result)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DemonTheme.green)
                .fixedSize(horizontal: false, vertical: true)
            if let note = example.note {
                DemonCaption(note)
            }
            HStack(spacing: 8) {
                copyButton(example.input, identifier: "copyExample-\(index)")
                if let payload = example.payload {
                    openButton(payload, identifier: "openExample-\(index)")
                }
            }
        }
        .demonInset(tint: DemonTheme.metalMid)
    }

    private func graphCard(_ example: GuideExample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DemonSectionHeader(title: "Als Graph", systemImage: "chart.xyaxis.line")
            MiniGraphView(formula: example.input, parameters: FormulaParameters(), xRange: -6.3...6.3,
                          appearance: GraphAppearance(isLight: false))
                .frame(height: 110)
            Text(example.input)
                .font(.callout.monospaced())
                .foregroundStyle(DemonTheme.green)
                .textSelection(.enabled)
            Text(example.result)
                .font(.footnote)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                copyButton(example.input, identifier: "copyGraphExample")
                if let payload = example.payload {
                    openButton(payload, identifier: "openGraphExample")
                }
            }
        }
        .demonCard()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DemonSectionHeader(title: "Hinweise", systemImage: "exclamationmark.bubble")
            ForEach(entry.notes, id: \.self) { note in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    DiamondShape()
                        .fill(DemonTheme.blurple)
                        .frame(width: 6, height: 6)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .demonCard()
    }

    // MARK: Actions

    private func copyButton(_ text: String, identifier: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            copiedText = text
        } label: {
            Label(copiedText == text ? "Kopiert" : "Kopieren", systemImage: copiedText == text ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(DemonChipButtonStyle(isActive: copiedText == text))
        .accessibilityIdentifier(identifier)
    }

    private func openButton(_ payload: EditorPayload, identifier: String) -> some View {
        Button {
            if model.hasUnsavedChanges {
                pendingPayload = payload
            } else {
                model.openInEditor(payload)
            }
        } label: {
            Label("Im Editor öffnen", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
        .accessibilityIdentifier(identifier)
    }

    private func readableProgram(_ text: String) -> SyntaxProgram? {
        guard !entry.isGeneratorSetting else { return nil }
        let program = FormulaDisplay.program(text, context: .synth, requiresOutput: false)
            ?? FormulaDisplay.program(text, context: .classic, requiresOutput: false)
        guard let program, !program.statements.isEmpty else { return nil }
        return program
    }

    private func argumentColor(_ index: Int) -> Color {
        GuideDiagramView.palette[index % GuideDiagramView.palette.count]
    }
}

/// Labelled diagram: which input position appears where in the printed notation.
struct GuideDiagramView: View {
    let diagram: GuideDiagram

    /// Colours of the argument positions (same in input and notation).
    static let palette: [Color] = [Color(hex: 0x34D8FF), Color(hex: 0xFFB23F), Color(hex: 0xFF4FD8), Color(hex: 0xB8FF3C),
                                   Color(hex: 0xB57CFF), Color(hex: 0xFF5470)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch diagram {
            case .bigOperator(let symbol, let variable, let start, let end, let body):
                bigOperator(symbol: symbol, variable: variable, start: start, end: end, body: body)
            case .cases(let conditions, let values, let otherwise):
                cases(conditions: conditions, values: values, otherwise: otherwise)
            case .fraction(let numerator, let denominator):
                fraction(numerator: numerator, denominator: denominator)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .demonInset(tint: DemonTheme.blurple.opacity(0.6), padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guideDiagram")
    }

    private func color(_ index: Int) -> Color { Self.palette[index % Self.palette.count] }

    // MARK: Σ / Π

    private func bigOperator(symbol: String, variable: String, start: String, end: String, body: String) -> some View {
        let command = symbol == "Π" ? "prod" : "sum"
        return VStack(alignment: .leading, spacing: 12) {
            DemonSubheader("Eingabe")
            inputLine(command, [variable, start, end, body])
            DemonSubheader("Darstellung")
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 0) {
                    Text(end)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(color(2))
                    Text(symbol)
                        .font(.system(size: 50, weight: .regular, design: .serif))
                        .foregroundStyle(DemonTheme.textPrimary)
                    HStack(spacing: 2) {
                        Text(variable).italic().foregroundStyle(color(0))
                        Text("=").foregroundStyle(DemonTheme.textTertiary)
                        Text(start).foregroundStyle(color(1))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                }
                Text(body)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(color(3))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
            .padding(.leading, 8)
            VStack(alignment: .leading, spacing: 4) {
                legend(0, "Laufvariable", variable, "unter dem Zeichen, links vom Gleichheitszeichen")
                legend(1, "Start", start, "unter dem Zeichen, rechts vom Gleichheitszeichen")
                legend(2, "Ende (einschließlich)", end, "über dem Zeichen")
                legend(3, "Ausdruck", body, "rechts neben dem Zeichen")
            }
            Text(symbol == "Π"
                 ? "Π multipliziert den Ausdruck für jeden ganzzahligen Wert der Laufvariablen von Start bis Ende."
                 : "Σ addiert den Ausdruck für jeden ganzzahligen Wert der Laufvariablen von Start bis Ende.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cases

    private func cases(conditions: [String], values: [String], otherwise: String) -> some View {
        var arguments: [String] = []
        for (condition, value) in zip(conditions, values) {
            arguments.append(condition)
            arguments.append(value)
        }
        arguments.append(otherwise)
        return VStack(alignment: .leading, spacing: 12) {
            DemonSubheader("Eingabe")
            inputLine(conditions.count == 1 ? "if" : "piecewise", arguments)
            DemonSubheader("Darstellung")
            HStack(alignment: .center, spacing: 6) {
                Text("{")
                    .font(.system(size: CGFloat(28 + 18 * conditions.count), weight: .ultraLight, design: .serif))
                    .foregroundStyle(DemonTheme.blurpleText)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(conditions.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text(values[index]).foregroundStyle(color(2 * index + 1))
                            Text("falls").foregroundStyle(DemonTheme.textTertiary)
                            Text(conditions[index]).foregroundStyle(color(2 * index))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(otherwise).foregroundStyle(color(arguments.count - 1))
                        Text("sonst").foregroundStyle(DemonTheme.textTertiary)
                    }
                }
                .font(.system(size: 17, weight: .semibold, design: .serif))
            }
            Text("Die Bedingungen werden von oben nach unten geprüft; die erste wahre wählt ihren Wert. Nur dieser Zweig wird berechnet.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Fraction

    private func fraction(numerator: String, denominator: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSubheader("Eingabe")
            HStack(spacing: 0) {
                Text("(").foregroundStyle(DemonTheme.textTertiary)
                Text(numerator.replacingOccurrences(of: " ", with: "")).foregroundStyle(color(0))
                Text(")/(").foregroundStyle(DemonTheme.textTertiary)
                Text(denominator.replacingOccurrences(of: " ", with: "")).foregroundStyle(color(1))
                Text(")").foregroundStyle(DemonTheme.textTertiary)
            }
            .font(.body.monospaced().weight(.semibold))
            DemonSubheader("Darstellung")
            VStack(spacing: 4) {
                Text(numerator).foregroundStyle(color(0))
                Rectangle()
                    .fill(DemonTheme.textPrimary)
                    .frame(width: 110, height: 1.5)
                Text(denominator).foregroundStyle(color(1))
            }
            .font(.system(size: 20, design: .serif))
            .padding(.leading, 12)
            Text("Die Klammern legen fest, was zum Zähler und was zum Nenner gehört; in der Darstellung übernimmt der Bruchstrich ihre Aufgabe.")
                .font(.caption)
                .foregroundStyle(DemonTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Parts

    private func inputLine(_ command: String, _ arguments: [String]) -> some View {
        var text = Text(command + "(").foregroundColor(DemonTheme.neonGreen)
        for (index, argument) in arguments.enumerated() {
            if index > 0 { text = text + Text(", ").foregroundColor(DemonTheme.textTertiary) }
            text = text + Text(argument).foregroundColor(color(index))
        }
        text = text + Text(")").foregroundColor(DemonTheme.neonGreen)
        return text
            .font(.body.monospaced().weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func legend(_ index: Int, _ title: String, _ value: String, _ place: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(index + 1)")
                .font(.caption2.weight(.black))
                .foregroundStyle(DemonTheme.void)
                .frame(width: 18, height: 18)
                .background(DiamondShape().fill(color(index)))
            Text("\(title): ").font(.caption.weight(.bold)).foregroundColor(color(index))
                + Text(value).font(.caption.monospaced()).foregroundColor(DemonTheme.textPrimary)
                + Text(" – \(place)").font(.caption).foregroundColor(DemonTheme.textTertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
