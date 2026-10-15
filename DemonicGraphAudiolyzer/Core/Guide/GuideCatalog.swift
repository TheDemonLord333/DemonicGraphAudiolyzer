import Foundation

enum GuideCategory: String, CaseIterable, Identifiable, Sendable {
    case basics
    case functions
    case sums
    case conditions
    case lists
    case time
    case sound
    case generators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basics: return "Grundzeichen"
        case .functions: return "Funktionen"
        case .sums: return "Summen und Produkte"
        case .conditions: return "Bedingungen und Fallunterscheidungen"
        case .lists: return "Listen und Definitionen"
        case .time: return "Zeit und Musik"
        case .sound: return "Klang und Formelrollen"
        case .generators: return "Generatoren und Presets"
        }
    }

    var icon: String {
        switch self {
        case .basics: return "plus.forwardslash.minus"
        case .functions: return "function"
        case .sums: return "sum"
        case .conditions: return "arrow.triangle.branch"
        case .lists: return "list.number"
        case .time: return "metronome"
        case .sound: return "waveform"
        case .generators: return "sparkles"
        }
    }
}

/// One row of the argument table.
struct GuideArgument: Equatable, Sendable {
    var position: Int
    var name: String
    var meaning: String
    var mathPosition: String?
    var isOptional: Bool
    var allowed: String?
}

/// Context in which an example is evaluated by the tests (and opened in the editor).
enum GuideExampleContext: Equatable, Sendable {
    case classic(x: Double)
    case synth(inputs: [String: Double])
    /// Not evaluated numerically (graph or sound example).
    case none
}

struct GuideExample: Equatable, Sendable {
    var input: String
    var result: String
    var note: String?
    var expectedValue: Double?
    var context: GuideExampleContext
    var payload: EditorPayload?
}

/// Labelled diagram that maps input positions to the printed notation.
enum GuideDiagram: Equatable, Sendable {
    case bigOperator(symbol: String, variable: String, start: String, end: String, body: String)
    case cases(conditions: [String], values: [String], otherwise: String)
    case fraction(numerator: String, denominator: String)
}

struct GuideEntry: Identifiable, Equatable, Sendable {
    var id: String
    var category: GuideCategory
    var title: String
    var symbol: String
    /// Input commands and spellings ("sum", "Σ").
    var commands: [String]
    /// Printed mathematical notation as text, e.g. "Σ von i = 1 bis 5 über i".
    var mathNotation: String?
    var explanation: String
    /// Exact input syntax (copyable).
    var syntax: String
    var arguments: [GuideArgument] = []
    var examples: [GuideExample] = []
    /// Example with x or t.
    var graphExample: GuideExample?
    var notes: [String] = []
    var keywords: [String] = []
    var diagram: GuideDiagram?
    /// Catalogue function this entry documents (consistency tests).
    var functionID: String?
    /// The entry describes a generator setting, not a freely typed formula.
    var isGeneratorSetting = false

    /// Text used by the search (lower case, folded).
    var searchText: String {
        ([title, symbol, syntax, explanation] + commands + keywords).joined(separator: " ").searchFolded
    }
}

extension String {
    /// Lower case without diacritics (ä → a) for tolerant search.
    var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE")).lowercased()
    }
}

/// The complete offline guide. Function, operator and variable entries are generated from the
/// same structured definitions the parser uses (`FormulaCatalog`, `FormulaOperators`,
/// `FormulaVariable`), topics are authored in `GuideTopics`.
enum GuideCatalog {
    static let entries: [GuideEntry] = operatorEntries + functionEntries + variableEntries + GuideTopics.entries

    static func entry(id: String) -> GuideEntry? {
        entries.first { $0.id == id }
    }

    static func entries(in category: GuideCategory) -> [GuideEntry] {
        entries.filter { $0.category == category }
    }

    /// Entry for a help request from the editor ("sum", "atan", "variable-beat").
    static func entry(forHelpTopic topic: String) -> GuideEntry? {
        if topic.hasPrefix("variable-") {
            return entry(id: topic)
        }
        if let spec = FormulaCatalog.function(named: topic) {
            return entry(id: "function-" + spec.id)
        }
        return entry(id: topic)
    }

    /// Search by symbol (Σ, Π, π), German name (Summe, Betrag) or command (sum, abs).
    static func search(_ query: String) -> [GuideEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.searchFolded
        guard !folded.isEmpty else { return entries }
        func score(_ entry: GuideEntry) -> Int {
            // Exact spelling first: Π (product) is not π (pi).
            if entry.commands.contains(trimmed) || entry.symbol == trimmed { return 110 }
            if entry.commands.contains(where: { $0.searchFolded == folded }) { return 100 }
            if entry.symbol.searchFolded == folded || entry.symbol.searchFolded.hasPrefix(folded + " ") { return 90 }
            if entry.title.searchFolded == folded { return 85 }
            if entry.title.searchFolded.hasPrefix(folded) { return 70 }
            if entry.keywords.contains(where: { $0.searchFolded == folded }) { return 60 }
            if entry.commands.contains(where: { $0.searchFolded.hasPrefix(folded) }) { return 55 }
            if entry.symbol.searchFolded.contains(folded) { return 50 }
            if entry.title.searchFolded.contains(folded) { return 45 }
            if entry.keywords.contains(where: { $0.searchFolded.contains(folded) }) { return 40 }
            if entry.searchText.contains(folded) { return 10 }
            return 0
        }
        return entries.map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: Generated entries

    static let functionEntries: [GuideEntry] = FormulaCatalog.functions.map { spec in
        let category: GuideCategory
        switch spec.implementation {
        case .special(.sum), .special(.prod): category = .sums
        case .special(.ifElse), .special(.piecewise): category = .conditions
        case .special(.len): category = .lists
        default: category = .functions
        }
        var arguments: [GuideArgument] = []
        for (index, argument) in spec.arguments.enumerated() {
            let optional = argument.isRepeatable && index >= spec.minimumArguments
            var meaning = argument.meaning
            if argument.kind == .lazyExpression {
                meaning += " (wird nur ausgewertet, wenn er gebraucht wird)"
            }
            arguments.append(GuideArgument(position: index + 1, name: argument.name, meaning: meaning,
                                           mathPosition: argument.mathPosition, isOptional: optional, allowed: argument.allowed))
        }
        let examples = spec.examples.map { example in
            GuideExample(input: example.input, result: example.result, note: example.note, expectedValue: example.value,
                         context: .classic(x: example.x), payload: .classic("\(spec.title): \(example.input)", example.input))
        }
        let graph = spec.graphExample.map { example in
            GuideExample(input: example.input, result: example.result, note: nil, expectedValue: nil, context: .none,
                         payload: .classic("\(spec.title) als Graph", example.input))
        }
        var commands = [spec.id] + spec.aliases
        if spec.id == "sum" { commands.append("Σ") }
        if spec.id == "prod" { commands.append("Π") }
        if spec.id == "sqrt" { commands.append("√") }
        var notes = spec.notes
        if spec.aliases.count > 0 {
            notes.append("Gleichwertige Namen: \(([spec.id] + spec.aliases).joined(separator: ", ")).")
        }
        var diagram: GuideDiagram?
        var mathNotation: String?
        switch spec.id {
        case "sum":
            diagram = .bigOperator(symbol: "Σ", variable: "i", start: "1", end: "5", body: "i")
            mathNotation = "Σ von i = 1 bis 5 über i"
        case "prod":
            diagram = .bigOperator(symbol: "Π", variable: "i", start: "1", end: "4", body: "i")
            mathNotation = "Π von i = 1 bis 4 über i"
        case "piecewise":
            diagram = .cases(conditions: ["x < −2", "x < 2"], values: ["−1", "x/2"], otherwise: "1")
            mathNotation = "f(x) = { −1 falls x < −2; x/2 falls x < 2; 1 sonst }"
        case "if":
            diagram = .cases(conditions: ["x > 0"], values: ["√x"], otherwise: "−1")
        default:
            break
        }
        return GuideEntry(id: "function-" + spec.id, category: category, title: spec.title, symbol: spec.symbol,
                          commands: commands, mathNotation: mathNotation, explanation: spec.summary, syntax: spec.syntax,
                          arguments: arguments, examples: examples, graphExample: graph, notes: notes,
                          keywords: spec.keywords, diagram: diagram, functionID: spec.id)
    }

    static let operatorEntries: [GuideEntry] = FormulaOperators.all.map { spec in
        let category: GuideCategory
        switch spec.id {
        case "comparison", "logic": category = .conditions
        case "list", "definition": category = .lists
        default: category = .basics
        }
        let examples = spec.examples.map { example in
            GuideExample(input: example.input, result: example.result, note: example.note, expectedValue: example.value,
                         context: .classic(x: example.x), payload: .classic("\(spec.title): \(example.input.replacingOccurrences(of: "\n", with: "; "))", example.input))
        }
        var diagram: GuideDiagram?
        if spec.id == "divide" { diagram = .fraction(numerator: "1 + 2", denominator: "3 + 3") }
        return GuideEntry(id: "operator-" + spec.id, category: category, title: spec.title, symbol: spec.symbol,
                          commands: spec.spellings, explanation: spec.summary,
                          syntax: spec.examples.first?.input ?? spec.spellings.joined(separator: " "),
                          examples: examples, notes: ["Rangfolge: \(spec.precedenceNote)."] + spec.notes,
                          keywords: spec.keywords, diagram: diagram)
    }

    static let variableEntries: [GuideEntry] = FormulaVariable.allCases.filter { !$0.isLegacyParameter || $0 == .a }.map { variable in
        let isClassic = variable == .x || variable.isLegacyParameter
        let name = variable.isLegacyParameter ? "a, b, c" : variable.rawValue
        let example = GuideTopics.variableExample(variable)
        var notes: [String] = []
        if !isClassic {
            notes.append("Nur im Formel-Synthesizer (und Pendel-Modus) verfügbar. In „Graph vertonen“ heißt die Variable x.")
        }
        if !variable.unit.isEmpty {
            notes.append("Einheit: \(variable.unit).")
        }
        notes.append("Groß- und Kleinschreibung zählt\(variable.isCaseInsensitive ? " nicht (aus Kompatibilität mit älteren Formeln)" : ""): \(name).")
        return GuideEntry(id: "variable-" + variable.rawValue, category: isClassic ? .basics : .time,
                          title: variable.isLegacyParameter ? "Parameter a, b, c" : "\(variable.title) (\(variable.rawValue))",
                          symbol: name, commands: variable.isLegacyParameter ? ["a", "b", "c"] : [variable.rawValue],
                          explanation: variable.summary, syntax: name, examples: [example], notes: notes,
                          keywords: [variable.title, variable.rawValue, "variable"])
    }
}
