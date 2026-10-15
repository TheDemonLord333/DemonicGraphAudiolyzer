import Foundation

/// Signature shown while editing: the function around the cursor and the active argument.
struct SignatureContext: Equatable, Sendable {
    /// Catalogue id, or the name of a user function.
    var functionName: String
    var title: String
    var argumentNames: [String]
    /// Index into `argumentNames` of the argument being edited (variadic tails repeat).
    var activeArgument: Int
    /// Meaning of the active argument (from the catalogue).
    var activeMeaning: String?
    /// True for built-in functions (they have a guide entry).
    var isBuiltIn: Bool

    var syntax: String { "\(functionName)(\(argumentNames.joined(separator: ", ")))" }
}

/// Text analysis for the formula editors (signature help, call ranges, visual editors).
/// Works on plain text and tolerates incomplete input.
enum FormulaTextTools {
    /// The innermost function call whose parentheses contain `cursor` (character offset).
    static func signature(in text: String, cursor: Int) -> SignatureContext? {
        let characters = Array(text)
        let limit = min(max(cursor, 0), characters.count)
        struct Frame { var name: String?; var commas: Int; var isList: Bool }
        var stack: [Frame] = []
        var index = 0
        while index < limit {
            let character = characters[index]
            switch character {
            case "#":
                while index < limit, characters[index] != "\n" { index += 1 }
                continue
            case "(":
                stack.append(Frame(name: word(before: index, in: characters), commas: 0, isList: false))
            case "[":
                stack.append(Frame(name: nil, commas: 0, isList: true))
            case ")", "]":
                if !stack.isEmpty { stack.removeLast() }
            case ",", ";":
                if !stack.isEmpty { stack[stack.count - 1].commas += 1 }
            case "\n":
                if stack.isEmpty { break }
            default:
                break
            }
            index += 1
        }
        guard let frame = stack.last(where: { !$0.isList && $0.name != nil }), let name = frame.name else { return nil }
        // Commas of inner frames do not count: use the frame's own comma count.
        if let spec = FormulaCatalog.function(named: name) {
            let names = spec.signatureArguments
            var active = frame.commas
            if let specArgument = spec.argumentSpec(at: frame.commas), let position = spec.arguments.firstIndex(of: specArgument) {
                active = position
            }
            if spec.id == SpecialForm.piecewise.rawValue {
                // c1, e1, c2, e2, …, default – show which role the current position has.
                let roleNames = ["bedingung", "ausdruck"]
                let pairIndex = frame.commas / 2 + 1
                let role = roleNames[frame.commas % 2]
                return SignatureContext(functionName: spec.id, title: spec.title,
                                        argumentNames: ["bedingung1", "ausdruck1", "…", "sonstAusdruck"],
                                        activeArgument: frame.commas % 2,
                                        activeMeaning: "Argument \(frame.commas + 1): \(role)\(pairIndex) – oder der Sonst-Fall, wenn es das letzte Argument ist",
                                        isBuiltIn: true)
            }
            active = min(active, names.count - 1)
            return SignatureContext(functionName: spec.id, title: spec.title, argumentNames: names,
                                    activeArgument: active, activeMeaning: spec.argumentSpec(at: frame.commas)?.meaning,
                                    isBuiltIn: true)
        }
        if let parameters = userFunctions(in: text)[name] {
            return SignatureContext(functionName: name, title: "Hilfsfunktion", argumentNames: parameters,
                                    activeArgument: min(frame.commas, max(parameters.count - 1, 0)), activeMeaning: nil, isBuiltIn: false)
        }
        return nil
    }

    /// Built-in function name at or right before the cursor (for the help button), or the
    /// function of the call around the cursor.
    static func helpTopic(in text: String, cursor: Int) -> String? {
        let characters = Array(text)
        let limit = min(max(cursor, 0), characters.count)
        var start = limit
        while start > 0, characters[start - 1].isWordCharacter { start -= 1 }
        var end = limit
        while end < characters.count, characters[end].isWordCharacter { end += 1 }
        if start < end {
            let word = String(characters[start..<end])
            if let spec = FormulaCatalog.function(named: word) { return spec.id }
            if FormulaVariable(rawValue: word) != nil { return "variable-" + word }
        }
        return signature(in: text, cursor: cursor).flatMap { $0.isBuiltIn ? $0.functionName : nil }
    }

    /// Helper functions defined in a program text: name → parameter names.
    static func userFunctions(in text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let open = trimmed.firstIndex(of: "("), let close = trimmed.firstIndex(of: ")"), open < close else { continue }
            let afterClose = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard afterClose.hasPrefix("="), !afterClose.hasPrefix("==") else { continue }
            let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
            guard let first = name.first, first.isASCIILetter, name.allSatisfy(\.isWordCharacter) else { continue }
            let parameters = trimmed[trimmed.index(after: open)..<close].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            result[name] = parameters
        }
        return result
    }

    private static func word(before position: Int, in characters: [Character]) -> String? {
        var end = position
        while end > 0, characters[end - 1] == " " { end -= 1 }
        var start = end
        while start > 0, characters[start - 1].isWordCharacter { start -= 1 }
        guard start < end, characters[start].isASCIILetter || FormulaLexer.greekAliases[characters[start]] != nil else { return nil }
        var spelled = ""
        for character in characters[start..<end] {
            spelled += FormulaLexer.greekAliases[character] ?? String(character)
        }
        return spelled
    }

    // MARK: Calls

    /// A call `name( … )` located in a text.
    struct LocatedCall: Equatable, Sendable {
        var name: String
        /// Range of the whole call including the name (character offsets).
        var range: Range<Int>
        var arguments: [String]
    }

    /// The innermost call of one of `names` that contains the cursor.
    static func enclosingCall(in text: String, cursor: Int, names: Set<String>) -> LocatedCall? {
        let calls = allCalls(in: text).filter { names.contains($0.name.lowercased()) && $0.range.lowerBound <= cursor && cursor <= $0.range.upperBound }
        return calls.min(by: { $0.range.count < $1.range.count })
    }

    /// All calls with their top-level arguments.
    static func allCalls(in text: String) -> [LocatedCall] {
        let characters = Array(text)
        var result: [LocatedCall] = []
        var index = 0
        while index < characters.count {
            if characters[index] == "(", let name = word(before: index, in: characters),
               let close = matchingClose(from: index, in: characters) {
                var start = index
                while start > 0, characters[start - 1] == " " { start -= 1 }
                while start > 0, characters[start - 1].isWordCharacter { start -= 1 }
                let inner = String(characters[(index + 1)..<close])
                result.append(LocatedCall(name: name, range: start..<(close + 1), arguments: splitArguments(inner)))
            }
            index += 1
        }
        return result
    }

    static func matchingClose(from open: Int, in characters: [Character]) -> Int? {
        var depth = 0
        var index = open
        while index < characters.count {
            switch characters[index] {
            case "(", "[": depth += 1
            case ")", "]":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index += 1
        }
        return nil
    }

    /// Splits at top-level commas/semicolons (not inside parentheses or brackets).
    static func splitArguments(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "[":
                depth += 1
                current.append(character)
            case ")", "]":
                depth -= 1
                current.append(character)
            case ",", ";":
                if depth == 0 {
                    parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
        }
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty || !parts.isEmpty { parts.append(last) }
        return parts
    }

    /// Replaces the characters in `range` of `text`.
    static func replacing(_ range: Range<Int>, in text: String, with replacement: String) -> String {
        var characters = Array(text)
        let lower = max(0, min(range.lowerBound, characters.count))
        let upper = max(lower, min(range.upperBound, characters.count))
        characters.replaceSubrange(lower..<upper, with: Array(replacement))
        return String(characters)
    }
}

/// Model of the visual case-distinction editor ("Fallunterscheidung").
struct PiecewiseDraft: Equatable, Sendable {
    struct Case: Equatable, Sendable, Identifiable {
        var id = UUID()
        var condition: String
        var expression: String

        static func == (lhs: Case, rhs: Case) -> Bool {
            lhs.condition == rhs.condition && lhs.expression == rhs.expression
        }
    }

    var cases: [Case]
    var otherwise: String

    static let empty = PiecewiseDraft(cases: [Case(condition: "x < 0", expression: "-1")], otherwise: "1")

    init(cases: [Case], otherwise: String) {
        self.cases = cases
        self.otherwise = otherwise
    }

    /// Reads `piecewise(c1, e1, …, default)` or `if(c, a, b)`.
    init?(call: FormulaTextTools.LocatedCall) {
        let name = call.name.lowercased()
        let arguments = call.arguments
        if name == "if", arguments.count == 3 {
            self.init(cases: [Case(condition: arguments[0], expression: arguments[1])], otherwise: arguments[2])
            return
        }
        guard name == "piecewise", arguments.count >= 3, arguments.count % 2 == 1 else { return nil }
        var cases: [Case] = []
        var position = 0
        while position + 1 < arguments.count {
            cases.append(Case(condition: arguments[position], expression: arguments[position + 1]))
            position += 2
        }
        self.init(cases: cases, otherwise: arguments[arguments.count - 1])
    }

    var formulaText: String {
        let parts = cases.flatMap { [$0.condition.trimmed, $0.expression.trimmed] } + [otherwise.trimmed]
        return "piecewise(\(parts.joined(separator: ", ")))"
    }

    /// Empty fields (the editor disables "Übernehmen").
    var missingParts: [String] {
        var missing: [String] = []
        for (index, item) in cases.enumerated() {
            if item.condition.trimmed.isEmpty { missing.append("Bedingung \(index + 1)") }
            if item.expression.trimmed.isEmpty { missing.append("Ausdruck \(index + 1)") }
        }
        if otherwise.trimmed.isEmpty { missing.append("Sonst-Fall") }
        return missing
    }
}

/// Model of the visual sum/product editor.
struct AggregateDraft: Equatable, Sendable {
    var kind: AggregateKind
    var variable: String
    var start: String
    var end: String
    var body: String

    static let sumExample = AggregateDraft(kind: .sum, variable: "i", start: "1", end: "5", body: "sin(i*x)/i")

    init(kind: AggregateKind, variable: String, start: String, end: String, body: String) {
        self.kind = kind
        self.variable = variable
        self.start = start
        self.end = end
        self.body = body
    }

    init?(call: FormulaTextTools.LocatedCall) {
        let name = call.name.lowercased()
        guard let kind = AggregateKind(rawValue: name == "Σ".lowercased() ? "sum" : name), call.arguments.count == 4 else { return nil }
        self.init(kind: kind, variable: call.arguments[0], start: call.arguments[1], end: call.arguments[2], body: call.arguments[3])
    }

    var formulaText: String {
        "\(kind.rawValue)(\(variable.trimmed), \(start.trimmed), \(end.trimmed), \(body.trimmed))"
    }

    var missingParts: [String] {
        var missing: [String] = []
        if variable.trimmed.isEmpty { missing.append("Laufvariable") }
        if start.trimmed.isEmpty { missing.append("Start") }
        if end.trimmed.isEmpty { missing.append("Ende") }
        if body.trimmed.isEmpty { missing.append("Ausdruck") }
        return missing
    }

    /// The loop variable must be a simple name.
    var variableIsValid: Bool {
        let name = variable.trimmed
        guard let first = name.first, first.isASCIILetter else { return false }
        return name.allSatisfy { $0.isASCIILetter || $0.isASCIIDigit || $0 == "_" }
            && FormulaCatalog.function(named: name) == nil && FormulaConstant(rawValue: name.lowercased()) == nil
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Parsing for the readable notation of an editor: unknown names are tolerated (they are
/// reported separately by the compiler), definitions of other sources are taken into account.
enum FormulaDisplay {
    static func program(_ text: String, context: FormulaContext, definitions: [String] = [], requiresOutput: Bool = true) -> SyntaxProgram? {
        var shapes: [String: DefinitionShape] = [:]
        for source in definitions where !source.trimmed.isEmpty {
            var environment = FormulaEnvironment(context: context)
            environment.externalDefinitions = shapes
            environment.requiresOutput = false
            environment.allowAutoParameters = true
            guard let program = try? FormulaParser.parseProgram(source, environment: environment) else { continue }
            for statement in program.definitions {
                guard let name = statement.definedName else { continue }
                if case .function(_, let parameters) = statement.kind {
                    shapes[name] = .function(arity: parameters.count)
                } else {
                    shapes[name] = statement.isList ? .list : .value
                }
            }
        }
        var environment = FormulaEnvironment(context: context)
        environment.externalDefinitions = shapes
        environment.requiresOutput = requiresOutput
        environment.allowAutoParameters = true
        return try? FormulaParser.parseProgram(text, environment: environment)
    }
}
