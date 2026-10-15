import Foundation

/// Shape of a definition, known before the right-hand sides are parsed.
enum DefinitionShape: Equatable, Sendable {
    case value
    case list
    case function(arity: Int)
}

/// Everything the parser needs to know about the surroundings of a formula.
struct FormulaEnvironment: Equatable, Sendable {
    var context: FormulaContext
    /// Definitions from earlier sources (project and voice definitions, parameters).
    var externalDefinitions: [String: DefinitionShape] = [:]
    /// Unknown names become parameters instead of errors (simple editor of the synthesizer).
    var allowAutoParameters = false
    /// Role formulas need an output line; definition blocks must not have one.
    var requiresOutput = true
    /// Shown in error messages ("Projekt-Definitionen, Zeile 2: …").
    var sourceName: String?

    static let classic = FormulaEnvironment(context: .classic)
}

/// Recursive descent parser producing a `SyntaxProgram`.
///
/// Grammar of one expression (lowest to highest precedence):
/// ```
/// expression := or
/// or         := and { "or" and }
/// and        := not { "and" not }
/// not        := "not" not | comparison
/// comparison := additive [ ("<"|"<="|">"|">="|"=="|"!=") additive ]   // no chains
/// additive   := term { ("+"|"-") term }
/// term       := unary { ("*"|"/") unary | implicitFactor }
/// implicitFactor := power            // only before a name or "("
/// unary      := ("-"|"+") unary | power
/// power      := postfix [ "^" unary ] // right associative: 2^3^2 = 2^(3^2)
/// postfix    := primary { "[" expression "]" }
/// primary    := number | name | call | "(" expression ")" | "[" list "]"
/// ```
/// Consequences: `-x^2 = -(x^2)`, `2^-1 = 0.5`, `2x^2 = 2·(x^2)`, `2sin(x) = 2·sin(x)`.
///
/// A program consists of lines: definitions `name = …`, helper functions `name(p, q) = …`
/// and one output line without `=`. Newlines inside open brackets continue the line.
struct FormulaParser {
    static let maximumNesting = 64
    static let maximumListLength = 1_024

    private var tokens: [FormulaToken]
    private var index = 0
    private var depth = 0
    private let environment: FormulaEnvironment
    private var definitions: [String: DefinitionShape]
    private var localScopes: [[String]] = []
    private(set) var warnings: [FormulaWarning] = []
    private(set) var autoParameters: [String] = []

    private init(tokens: [FormulaToken], environment: FormulaEnvironment, definitions: [String: DefinitionShape]) {
        self.tokens = tokens
        self.environment = environment
        self.definitions = definitions
    }

    // MARK: - Entry points

    /// Parses a complete program. Errors carry line and column for multi-line sources.
    static func parseProgram(_ text: String, environment: FormulaEnvironment) throws -> SyntaxProgram {
        let lexer = FormulaLexer(text)
        do {
            return try parseProgram(lexer: lexer, environment: environment)
        } catch var error as FormulaError {
            locate(&error, lexer: lexer, environment: environment)
            throw error
        }
    }

    /// Classic convenience: the evaluable tree of a single formula in the classic context.
    static func parse(_ text: String) throws -> FormulaNode {
        let program = try parseProgram(text, environment: .classic)
        return try FormulaBinder.bind(program, environment: .classic).root
    }

    private static func locate(_ error: inout FormulaError, lexer: FormulaLexer, environment: FormulaEnvironment) {
        error.sourceName = error.sourceName ?? environment.sourceName
        let starts = lexer.lineStarts
        guard starts.count > 1 else {
            error.line = nil
            return
        }
        if let range = error.range {
            let line = starts.lastIndex(where: { $0 <= range.start }) ?? 0
            error.line = line + 1
            error.column = range.start - starts[line] + 1
        }
    }

    private static func parseProgram(lexer: FormulaLexer, environment: FormulaEnvironment) throws -> SyntaxProgram {
        let allTokens = try lexer.tokenize()
        let lines = splitStatements(allTokens)
        let lineCount = lexer.lineStarts.count

        // Pre-pass: collect definition names and shapes (order-independent definitions).
        var shapes = environment.externalDefinitions
        var headers: [(kind: SyntaxStatement.Kind, nameRange: SourceRange?, bodyStart: Int)] = []
        var ownNames: [String: SourceRange] = [:]
        for line in lines {
            let header = try definitionHeader(line, environment: environment)
            headers.append(header)
            if let name = definedName(of: header.kind), let range = header.nameRange {
                if ownNames[name] != nil || environment.externalDefinitions[name] != nil {
                    throw FormulaError(kind: .duplicateDefinition, message: "„\(name)“ ist bereits definiert.", range: range,
                                       hint: "Jeder Name darf nur einmal definiert werden.", line: line.first?.line)
                }
                ownNames[name] = range
                switch header.kind {
                case .function(_, let parameters): shapes[name] = .function(arity: parameters.count)
                default: shapes[name] = isListLiteral(line, from: header.bodyStart) ? .list : .value
                }
            }
        }

        var statements: [SyntaxStatement] = []
        var warnings: [FormulaWarning] = []
        var autoParameters: [String] = []
        for (line, header) in zip(lines, headers) {
            var parser = FormulaParser(tokens: Array(line[header.bodyStart...]), environment: environment, definitions: shapes)
            if case .function(_, let parameters) = header.kind {
                parser.localScopes = [parameters]
            }
            let isLegacyOutputDefinition: Bool = {
                switch header.kind {
                case .value(let name): return name.lowercased() == "y"
                case .function(let name, let parameters): return name.lowercased() == "f" && parameters.count == 1
                case .output: return false
                }
            }()
            if isLegacyOutputDefinition, case .end = parser.current.kind {
                throw FormulaError(kind: .empty, message: "Bitte gib eine Formel ein.", range: nil, hint: "Zum Beispiel sin(x).")
            }
            let expression = try parser.parseStatementExpression()
            warnings += parser.warnings
            for name in parser.autoParameters where !autoParameters.contains(name) {
                autoParameters.append(name)
            }
            statements.append(SyntaxStatement(kind: header.kind, nameRange: header.nameRange,
                                              expression: expression, line: line.first?.line ?? 1))
        }

        let outputs = statements.filter { $0.kind == .output }
        if environment.requiresOutput {
            if statements.isEmpty {
                throw FormulaError(kind: .empty, message: "Bitte gib eine Formel ein.", range: nil, hint: "Zum Beispiel sin(x).")
            }
            if outputs.count > 1 {
                throw FormulaError(kind: .multipleOutputs,
                                   message: "Es darf nur eine Ausgabezeile geben (Zeilen \(outputs.map { String($0.line) }.joined(separator: ", "))).",
                                   range: outputs[1].expression.range,
                                   hint: "Zwischenergebnisse als Definition schreiben, z. B. p = x + 8.")
            }
        } else if let output = outputs.first {
            throw FormulaError(kind: .multipleOutputs, message: "In Definitionen ist keine Ausgabezeile erlaubt.",
                               range: output.expression.range, hint: "Schreibe name = Ausdruck oder name(p) = Ausdruck.")
        }
        let program = SyntaxProgram(statements: statements, warnings: warnings, autoParameters: autoParameters, lineCount: lineCount)
        if environment.requiresOutput, program.outputStatement == nil {
            throw FormulaError(kind: .missingOutput, message: "Es fehlt die Ausgabezeile.",
                               range: nil, hint: "Die Ausgabe ist die Zeile ohne Gleichheitszeichen, z. B. sin(2*pi*x).")
        }
        return program
    }

    /// Splits the token stream at newlines outside brackets; drops empty statements.
    private static func splitStatements(_ tokens: [FormulaToken]) -> [[FormulaToken]] {
        var result: [[FormulaToken]] = []
        var current: [FormulaToken] = []
        var nesting = 0
        for token in tokens {
            switch token.kind {
            case .leftParen, .leftBracket:
                nesting += 1
                current.append(token)
            case .rightParen, .rightBracket:
                nesting = max(0, nesting - 1)
                current.append(token)
            case .newline:
                if nesting == 0, !current.isEmpty {
                    current.append(FormulaToken(kind: .end, range: SourceRange(start: token.range.start, end: token.range.start + 1), line: token.line))
                    result.append(current)
                    current = []
                }
            case .end:
                if !current.isEmpty {
                    current.append(token)
                    result.append(current)
                }
            default:
                current.append(token)
            }
        }
        return result
    }

    private static func definedName(of kind: SyntaxStatement.Kind) -> String? {
        switch kind {
        case .value(let name), .function(let name, _): return name
        case .output: return nil
        }
    }

    private static func isListLiteral(_ line: [FormulaToken], from start: Int) -> Bool {
        guard start < line.count, case .leftBracket = line[start].kind else { return false }
        var nesting = 0
        for position in start..<line.count {
            switch line[position].kind {
            case .leftBracket, .leftParen: nesting += 1
            case .rightBracket, .rightParen:
                nesting -= 1
                if nesting == 0 {
                    if case .end = line[position + 1].kind { return true }
                    return false
                }
            default: break
            }
        }
        return false
    }

    /// Recognises `name = …` and `name(p, q) = …` at the start of a line.
    private static func definitionHeader(_ line: [FormulaToken], environment: FormulaEnvironment) throws
        -> (kind: SyntaxStatement.Kind, nameRange: SourceRange?, bodyStart: Int) {
        guard case .word(let name) = line[0].kind else { return (.output, nil, 0) }
        if line.count > 1, case .equals = line[1].kind {
            try checkDefinableName(name, range: line[0].range, line: line[0].line, environment: environment, isFunction: false)
            return (.value(name), line[0].range, 2)
        }
        guard line.count > 2, case .leftParen = line[1].kind else { return (.output, nil, 0) }
        // name ( word {, word} ) =
        var parameters: [String] = []
        var position = 2
        var parameterRanges: [SourceRange] = []
        while position < line.count {
            guard case .word(let parameter) = line[position].kind else { return (.output, nil, 0) }
            parameters.append(parameter)
            parameterRanges.append(line[position].range)
            position += 1
            if case .comma = line[position].kind {
                position += 1
                continue
            }
            break
        }
        guard position + 1 < line.count, case .rightParen = line[position].kind, case .equals = line[position + 1].kind else {
            return (.output, nil, 0)
        }
        try checkDefinableName(name, range: line[0].range, line: line[0].line, environment: environment, isFunction: true)
        for (parameter, range) in zip(parameters, parameterRanges) {
            if FormulaConstant(rawValue: parameter.lowercased()) != nil || FormulaCatalog.function(named: parameter) != nil
                || LogicKeyword(rawValue: parameter.lowercased()) != nil || !(parameter.first?.isASCIILetter ?? false) {
                throw FormulaError(kind: .invalidDefinition, message: "„\(parameter)“ ist als Parametername nicht erlaubt.", range: range,
                                   hint: "Parameter einer Hilfsfunktion sind einfache Namen wie x, k oder p.", line: line[0].line)
            }
        }
        if Set(parameters).count != parameters.count {
            throw FormulaError(kind: .invalidDefinition, message: "Ein Parametername kommt doppelt vor.", range: line[0].range,
                               hint: nil, line: line[0].line)
        }
        return (.function(name, parameters: parameters), line[0].range, position + 2)
    }

    private static func checkDefinableName(_ name: String, range: SourceRange, line: Int, environment: FormulaEnvironment, isFunction: Bool) throws {
        if let variable = FormulaVariable(rawValue: name) ?? FormulaVariable.allCases.first(where: { $0.isCaseInsensitive && $0.rawValue == name.lowercased() }),
           environment.context.variables.contains(variable) {
            throw FormulaError(kind: .misplacedEquals,
                               message: "„\(name)“ ist eine eingebaute Variable und kann nicht definiert werden.",
                               range: range, hint: "Für einen Vergleich schreibe ==, z. B. \(name) == 2.", line: line)
        }
        if FormulaConstant(rawValue: name.lowercased()) != nil {
            throw FormulaError(kind: .invalidDefinition, message: "„\(name)“ ist eine Konstante und kann nicht definiert werden.",
                               range: range, hint: nil, line: line)
        }
        if FormulaCatalog.function(named: name) != nil {
            throw FormulaError(kind: .invalidDefinition, message: "„\(name)“ ist eine eingebaute Funktion und kann nicht neu definiert werden.",
                               range: range, hint: "Wähle einen anderen Namen.", line: line)
        }
        if LogicKeyword(rawValue: name.lowercased()) != nil {
            throw FormulaError(kind: .invalidDefinition, message: "„\(name)“ ist ein reserviertes Wort.", range: range, hint: nil, line: line)
        }
    }

    // MARK: - Token access

    private var current: FormulaToken {
        mutating get {
            expandWord(at: index)
            return tokens[index]
        }
    }

    private mutating func peekKind(_ offset: Int) -> TokenKind {
        let position = min(index + offset, tokens.count - 1)
        expandWord(at: position)
        return tokens[position].kind
    }

    private mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    // MARK: - Name resolution

    /// Replaces an unresolved word at `position` by one or more name tokens (or an error token).
    private mutating func expandWord(at position: Int) {
        guard case .word = tokens[position].kind else { return }
        let followedByParenthesis = position + 1 < tokens.count && tokens[position + 1].kind == .leftParen
        do {
            let resolved = try resolveWord(tokens[position], followedByParenthesis: followedByParenthesis)
            tokens.replaceSubrange(position...position, with: resolved)
        } catch let error as FormulaError {
            tokens[position].kind = .invalid(error)
        } catch {
            tokens[position].kind = .invalid(FormulaError(kind: .unknownName, message: "Unbekannter Name.", range: tokens[position].range, hint: nil))
        }
    }

    /// Single name lookup (exact for user names and new variables, case-insensitive for
    /// built-in functions, constants and the classic names x, a, b, c).
    private func lookup(_ spelling: String) -> NameReference? {
        for scope in localScopes.reversed() where scope.contains(spelling) {
            return .local(spelling)
        }
        if definitions[spelling] != nil {
            return .definition(spelling)
        }
        if let variable = FormulaVariable(rawValue: spelling), environment.context.variables.contains(variable) {
            return .variable(variable)
        }
        let lower = spelling.lowercased()
        if let variable = FormulaVariable(rawValue: lower), variable.isCaseInsensitive, environment.context.variables.contains(variable) {
            return .variable(variable)
        }
        if let constant = FormulaConstant(rawValue: lower) {
            return .constant(constant)
        }
        if let function = FormulaCatalog.function(named: lower) {
            return .function(function.id)
        }
        return nil
    }

    private mutating func resolveWord(_ token: FormulaToken, followedByParenthesis: Bool) throws -> [FormulaToken] {
        guard case .word(let word) = token.kind else { return [token] }
        if let reference = lookup(word) {
            return [FormulaToken(kind: .name(reference, spelling: word), range: token.range, line: token.line)]
        }
        let characters = Array(word)
        var segmentations: [[(String, NameReference)]] = []
        segment(characters, from: 0, current: [], into: &segmentations, functionMustBeLast: true)
        if let chosen = segmentations.first {
            if segmentations.count > 1 {
                let read = chosen.map(\.0).joined(separator: "·")
                let alternative = segmentations[1].map(\.0).joined(separator: "·")
                warnings.append(FormulaWarning(message: "„\(word)“ ist mehrdeutig und wurde als \(read) gelesen (möglich wäre auch \(alternative)). Schreibe * zur Verdeutlichung.",
                                               range: token.range, line: token.line))
            }
            var result: [FormulaToken] = []
            var offset = 0
            for (spelling, reference) in chosen {
                let length = spelling.count
                let start = token.offsets.indices.contains(offset) ? token.offsets[offset] : token.range.start
                let endIndex = offset + length - 1
                let end = token.offsets.indices.contains(endIndex) ? token.offsets[endIndex] + 1 : token.range.end
                result.append(FormulaToken(kind: .name(reference, spelling: spelling), range: SourceRange(start: start, end: end), line: token.line))
                offset += length
            }
            return result
        }
        // A function inside the run ("sinx"): the parenthesis is missing.
        var withFunctionInside: [[(String, NameReference)]] = []
        segment(characters, from: 0, current: [], into: &withFunctionInside, functionMustBeLast: false)
        if let pieces = withFunctionInside.first, let functionIndex = pieces.firstIndex(where: { if case .function = $0.1 { return true } else { return false } }) {
            let before = pieces[..<functionIndex].reduce(0) { $0 + $1.0.count }
            let name = pieces[functionIndex].0
            let start = token.offsets.indices.contains(before) ? token.offsets[before] : token.range.start
            let end = token.offsets.indices.contains(before + name.count - 1) ? token.offsets[before + name.count - 1] + 1 : token.range.end
            throw FormulaError(kind: .functionNeedsParenthesis,
                               message: "Nach „\(name)“ wird eine Klammer erwartet.",
                               range: SourceRange(start: start, end: end),
                               hint: "Schreibe z. B. \(name)(x).")
        }
        if environment.allowAutoParameters, !followedByParenthesis, word.first?.isASCIILetter == true {
            if !autoParameters.contains(word) { autoParameters.append(word) }
            return [FormulaToken(kind: .name(.autoParameter(word), spelling: word), range: token.range, line: token.line)]
        }
        throw unknownNameError(word, range: token.range, isCall: followedByParenthesis)
    }

    /// All segmentations of `letters` into known names, longest match first (legacy order).
    /// Stops after three results (enough to detect ambiguity).
    private func segment(_ letters: [Character], from position: Int, current: [(String, NameReference)],
                         into results: inout [[(String, NameReference)]], functionMustBeLast: Bool) {
        if results.count >= 3 { return }
        if position == letters.count {
            results.append(current)
            return
        }
        if let last = current.last, case .function = last.1, functionMustBeLast {
            return
        }
        var length = letters.count - position
        while length >= 1 {
            let piece = String(letters[position..<position + length])
            if let reference = lookup(piece), piece.first?.isASCIILetter == true {
                segment(letters, from: position + length, current: current + [(piece, reference)],
                        into: &results, functionMustBeLast: functionMustBeLast)
            }
            length -= 1
        }
    }

    private func unknownNameError(_ word: String, range: SourceRange, isCall: Bool) -> FormulaError {
        let lower = word.lowercased()
        var hint: String
        if lower == "log" {
            hint = "„log“ wird nicht erraten: ln(x) für den natürlichen, log10(x) für den Zehnerlogarithmus."
        } else if let variable = FormulaVariable.allCases.first(where: { $0.rawValue.lowercased() == lower }),
                  !environment.context.variables.contains(variable) {
            if environment.context == .classic {
                hint = "„\(variable.rawValue)“ gibt es nur im Formel-Synthesizer. Hier heißt die Variable x."
            } else {
                hint = "„\(variable.rawValue)“ ist hier nicht verfügbar."
            }
        } else if let match = knownNames.first(where: { $0.lowercased() == lower && $0 != word }) {
            hint = "Meintest du „\(match)“? Groß- und Kleinschreibung zählt."
        } else if isCall {
            hint = "Bekannte Funktionen stehen in den Anleitungen; eigene Funktionen werden mit name(x) = … definiert."
        } else if environment.context == .classic {
            hint = "Bekannt sind x, a, b, c, pi, e, Funktionen und eigene Definitionen. Für Produkte * schreiben."
        } else {
            hint = "Lege „\(word)“ als Parameter oder Definition an (z. B. \(word) = 1) oder schreibe * zwischen Namen."
        }
        return FormulaError(kind: .unknownName,
                            message: isCall ? "Unbekannte Funktion „\(word)“." : "Unbekannter Name „\(word)“.",
                            range: range, hint: hint)
    }

    private var knownNames: [String] {
        var names = environment.context.variables.map(\.rawValue)
        names += definitions.keys
        names += localScopes.flatMap { $0 }
        return names
    }

    // MARK: - Statements

    private mutating func parseStatementExpression() throws -> SyntaxExpression {
        let expression = try parseExpression()
        guard case .end = current.kind else {
            throw unexpectedTokenError(current)
        }
        return expression
    }

    // MARK: - Precedence levels

    private mutating func parseExpression() throws -> SyntaxExpression {
        depth += 1
        defer { depth -= 1 }
        if depth > Self.maximumNesting {
            throw FormulaError(kind: .nestingTooDeep, message: "Die Formel ist zu tief verschachtelt.", range: current.range, hint: nil)
        }
        return try parseOr()
    }

    private mutating func parseOr() throws -> SyntaxExpression {
        var node = try parseAnd()
        while case .keyword(.or) = current.kind {
            let range = current.range
            advance()
            node = .binary(.or, node, try parseAnd(), implicit: false, range)
        }
        return node
    }

    private mutating func parseAnd() throws -> SyntaxExpression {
        var node = try parseNot()
        while case .keyword(.and) = current.kind {
            let range = current.range
            advance()
            node = .binary(.and, node, try parseNot(), implicit: false, range)
        }
        return node
    }

    private mutating func parseNot() throws -> SyntaxExpression {
        if case .keyword(.not) = current.kind {
            let range = current.range
            advance()
            return .not(try parseNot(), range)
        }
        return try parseComparison()
    }

    private mutating func comparisonOperator(_ kind: TokenKind) -> BinaryOperator? {
        switch kind {
        case .less: return .less
        case .lessEqual: return .lessEqual
        case .greater: return .greater
        case .greaterEqual: return .greaterEqual
        case .equalEqual: return .equal
        case .notEqual: return .notEqual
        default: return nil
        }
    }

    private mutating func parseComparison() throws -> SyntaxExpression {
        let left = try parseAdditive()
        guard let op = comparisonOperator(current.kind) else { return left }
        let range = current.range
        advance()
        let right = try parseAdditive()
        if comparisonOperator(current.kind) != nil {
            throw FormulaError(kind: .comparisonChain,
                               message: "Vergleichsketten wie a < x < b werden nicht erraten.",
                               range: current.range,
                               hint: "Schreibe (a < x) and (x < b).")
        }
        return .binary(op, left, right, implicit: false, range)
    }

    private mutating func parseAdditive() throws -> SyntaxExpression {
        var node = try parseTerm()
        while true {
            switch current.kind {
            case .plus:
                let range = current.range
                advance()
                node = .binary(.add, node, try parseTerm(), implicit: false, range)
            case .minus:
                let range = current.range
                advance()
                node = .binary(.subtract, node, try parseTerm(), implicit: false, range)
            default:
                return node
            }
        }
    }

    private mutating func parseTerm() throws -> SyntaxExpression {
        var node = try parseUnary()
        while true {
            let token = current
            switch token.kind {
            case .star:
                advance()
                node = .binary(.multiply, node, try parseUnary(), implicit: false, token.range)
            case .slash:
                advance()
                node = .binary(.divide, node, try parseUnary(), implicit: false, token.range)
            case .leftParen, .name, .invalid:
                node = .binary(.multiply, node, try parsePower(), implicit: true, token.range)
            case .number:
                throw FormulaError(kind: .missingOperator,
                                   message: "Vor dieser Zahl fehlt ein Operator.",
                                   range: token.range,
                                   hint: "Schreibe z. B. x*2 oder 2*3.")
            default:
                return node
            }
        }
    }

    private mutating func parseUnary() throws -> SyntaxExpression {
        switch current.kind {
        case .minus:
            let range = current.range
            advance()
            return .negate(try parseUnary(), range)
        case .plus:
            advance()
            return try parseUnary()
        default:
            return try parsePower()
        }
    }

    private mutating func parsePower() throws -> SyntaxExpression {
        let base = try parsePostfix()
        if case .caret = current.kind {
            let range = current.range
            advance()
            let exponent = try parseUnary()
            return .binary(.power, base, exponent, implicit: false, range)
        }
        return base
    }

    private mutating func parsePostfix() throws -> SyntaxExpression {
        var node = try parsePrimary()
        while case .leftBracket = current.kind {
            switch node {
            case .name, .list, .index: break
            default:
                throw FormulaError(kind: .typeMismatch, message: "Nur Listen können mit [ ] indiziert werden.", range: current.range,
                                   hint: "Beispiel: notes[2] oder [0, 3, 7][i].")
            }
            let open = current
            advance()
            let indexExpression = try parseExpression()
            guard case .rightBracket = current.kind else {
                throw FormulaError(kind: .missingClosingParenthesis, message: "Die eckige Klammer wird nicht geschlossen.",
                                   range: open.range, hint: "Ergänze „]“.")
            }
            let close = current.range
            advance()
            node = .index(node, indexExpression, open.range.union(close))
        }
        return node
    }

    private mutating func parsePrimary() throws -> SyntaxExpression {
        let token = current
        switch token.kind {
        case .invalid(let error):
            throw error
        case .number(let value):
            advance()
            return .number(value, token.range)
        case .name(let reference, let spelling):
            switch reference {
            case .function(let id):
                advance()
                return try parseCall(id: id, spelling: spelling, nameToken: token)
            case .definition(let name):
                if case .function(let arity) = definitions[name] {
                    advance()
                    return try parseUserCall(name: name, arity: arity, nameToken: token)
                }
                advance()
                return .name(reference, spelling: spelling, token.range)
            default:
                advance()
                return .name(reference, spelling: spelling, token.range)
            }
        case .leftParen:
            advance()
            let inner = try parseExpression()
            guard case .rightParen = current.kind else {
                throw FormulaError(kind: .missingClosingParenthesis,
                                   message: "Die Klammer wird nicht geschlossen.",
                                   range: token.range,
                                   hint: "Ergänze „)“.")
            }
            let close = current.range
            advance()
            return .group(inner, token.range.union(close))
        case .leftBracket:
            return try parseList()
        default:
            throw missingOperandError(at: token)
        }
    }

    private mutating func parseList() throws -> SyntaxExpression {
        let open = current
        advance()
        var elements: [SyntaxExpression] = []
        if case .rightBracket = current.kind {
            throw FormulaError(kind: .invalidArgument, message: "Eine Liste braucht mindestens ein Element.", range: open.range,
                               hint: "Beispiel: [0, 3, 7, 10].")
        }
        while true {
            let element = try parseExpression()
            if case .list = element {
                throw FormulaError(kind: .typeMismatch, message: "Verschachtelte Listen werden nicht unterstützt.", range: element.range, hint: nil)
            }
            elements.append(element)
            if elements.count > Self.maximumListLength {
                throw FormulaError(kind: .tooComplex, message: "Die Liste ist zu lang (höchstens \(Self.maximumListLength) Elemente).",
                                   range: open.range, hint: nil)
            }
            if case .comma = current.kind {
                advance()
                continue
            }
            break
        }
        guard case .rightBracket = current.kind else {
            throw FormulaError(kind: .missingClosingParenthesis, message: "Die eckige Klammer der Liste wird nicht geschlossen.",
                               range: open.range, hint: "Ergänze „]“.")
        }
        let close = current.range
        advance()
        return .list(elements, open.range.union(close))
    }

    private mutating func parseCall(id: String, spelling: String, nameToken: FormulaToken) throws -> SyntaxExpression {
        guard let spec = FormulaCatalog.function(named: id) else {
            throw unknownNameError(spelling, range: nameToken.range, isCall: true)
        }
        guard case .leftParen = current.kind else {
            throw FormulaError(kind: .functionNeedsParenthesis,
                               message: "Nach „\(spelling)“ wird eine Klammer erwartet.",
                               range: nameToken.range,
                               hint: "Schreibe z. B. \(spec.syntax).")
        }
        let openToken = current
        advance()
        if spec.implementation == .special(.sum) || spec.implementation == .special(.prod) {
            return try parseAggregate(spec: spec, spelling: spelling, nameToken: nameToken, openToken: openToken)
        }
        var arguments: [SyntaxExpression] = []
        if case .rightParen = current.kind {
            // Empty argument list – handled by the count check below.
        } else {
            arguments.append(try parseExpression())
            while case .comma = current.kind {
                advance()
                arguments.append(try parseExpression())
            }
        }
        guard case .rightParen = current.kind else {
            if case .end = current.kind {
                throw FormulaError(kind: .missingClosingParenthesis,
                                   message: "Die Klammer von „\(spelling)“ wird nicht geschlossen.",
                                   range: openToken.range,
                                   hint: "Ergänze „)“.")
            }
            throw unexpectedTokenError(current)
        }
        advance()
        guard spec.accepts(arguments.count) else {
            throw argumentCountError(spec: spec, spelling: spelling, found: arguments.count, range: nameToken.range)
        }
        return .call(.function(spec.id), spelling: spelling, arguments: arguments, nameToken.range)
    }

    private func argumentCountError(spec: FunctionSpec, spelling: String, found: Int, range: SourceRange) -> FormulaError {
        let expected: String
        if spec.implementation == .special(.piecewise) {
            return FormulaError(kind: .wrongArgumentCount,
                                message: "„piecewise“ braucht eine ungerade Anzahl von Argumenten (mindestens 3), gefunden: \(found).",
                                range: range,
                                hint: "Aufbau: piecewise(bedingung1, ausdruck1, …, sonstAusdruck) – der Sonst-Fall steht zuletzt.")
        }
        if let maximum = spec.maximumArguments, maximum == spec.minimumArguments {
            expected = maximum == 1 ? "1 Argument" : "\(maximum) Argumente"
        } else {
            expected = "mindestens \(spec.minimumArguments) Argumente"
        }
        return FormulaError(kind: .wrongArgumentCount,
                            message: "„\(spelling)“ erwartet \(expected), gefunden: \(found).",
                            range: range,
                            hint: "Syntax: \(spec.syntax).")
    }

    private mutating func parseAggregate(spec: FunctionSpec, spelling: String, nameToken: FormulaToken, openToken: FormulaToken) throws -> SyntaxExpression {
        // 1. Loop variable: a new name, taken literally (no segmentation).
        let variableToken = tokens[index]
        guard case .word(let variable) = variableToken.kind,
              variable.first?.isASCIILetter == true,
              FormulaConstant(rawValue: variable.lowercased()) == nil,
              FormulaCatalog.function(named: variable) == nil,
              LogicKeyword(rawValue: variable.lowercased()) == nil else {
            throw FormulaError(kind: .invalidArgument,
                               message: "Das erste Argument von „\(spelling)“ muss der Name der Laufvariable sein.",
                               range: variableToken.range,
                               hint: "Syntax: \(spec.syntax), z. B. \(spec.id)(i, 1, 5, i).")
        }
        advance()
        func expectComma(_ position: String) throws {
            guard case .comma = current.kind else {
                if case .invalid(let error) = current.kind { throw error }
                throw FormulaError(kind: .wrongArgumentCount,
                                   message: "„\(spelling)“ erwartet 4 Argumente: \(spec.syntax). Es fehlt \(position).",
                                   range: nameToken.range,
                                   hint: "Beispiel: \(spec.id)(i, 1, 5, i).")
            }
            advance()
        }
        try expectComma("der Start")
        // 2./3. Start and end are evaluated outside the scope of the loop variable.
        let start = try parseExpression()
        try expectComma("das Ende")
        let end = try parseExpression()
        try expectComma("der Ausdruck")
        // 4. The body sees the loop variable (it shadows outer names).
        localScopes.append([variable])
        let body = try parseExpression()
        localScopes.removeLast()
        guard case .rightParen = current.kind else {
            if case .comma = current.kind {
                throw FormulaError(kind: .wrongArgumentCount,
                                   message: "„\(spelling)“ erwartet genau 4 Argumente: \(spec.syntax).",
                                   range: nameToken.range, hint: nil)
            }
            throw FormulaError(kind: .missingClosingParenthesis,
                               message: "Die Klammer von „\(spelling)“ wird nicht geschlossen.",
                               range: openToken.range, hint: "Ergänze „)“.")
        }
        advance()
        let variableName = SyntaxExpression.name(.local(variable), spelling: variable, variableToken.range)
        return .call(.function(spec.id), spelling: spelling, arguments: [variableName, start, end, body], nameToken.range)
    }

    private mutating func parseUserCall(name: String, arity: Int, nameToken: FormulaToken) throws -> SyntaxExpression {
        guard case .leftParen = current.kind else {
            throw FormulaError(kind: .functionNeedsParenthesis,
                               message: "Die Hilfsfunktion „\(name)“ braucht Argumente in Klammern.",
                               range: nameToken.range, hint: "Schreibe z. B. \(name)(x).")
        }
        let openToken = current
        advance()
        var arguments: [SyntaxExpression] = []
        if case .rightParen = current.kind {
        } else {
            arguments.append(try parseExpression())
            while case .comma = current.kind {
                advance()
                arguments.append(try parseExpression())
            }
        }
        guard case .rightParen = current.kind else {
            throw FormulaError(kind: .missingClosingParenthesis, message: "Die Klammer von „\(name)“ wird nicht geschlossen.",
                               range: openToken.range, hint: "Ergänze „)“.")
        }
        advance()
        guard arguments.count == arity else {
            throw FormulaError(kind: .wrongArgumentCount,
                               message: "„\(name)“ erwartet \(arity == 1 ? "1 Argument" : "\(arity) Argumente"), gefunden: \(arguments.count).",
                               range: nameToken.range, hint: nil)
        }
        return .call(.definition(name), spelling: name, arguments: arguments, nameToken.range)
    }

    // MARK: - Errors

    private mutating func missingOperandError(at token: FormulaToken) -> FormulaError {
        switch token.kind {
        case .invalid(let error):
            return error
        case .end:
            let previous = index > 0 ? tokens[index - 1] : nil
            let after = previous.map { " nach „\(describe($0))“" } ?? ""
            return FormulaError(kind: .missingOperand,
                                message: "Die Formel endet unerwartet – es fehlt ein Wert\(after).",
                                range: previous?.range ?? token.range,
                                hint: nil)
        case .rightParen:
            return FormulaError(kind: .missingOperand,
                                message: "Vor „)“ fehlt ein Wert.",
                                range: token.range,
                                hint: nil)
        case .comma:
            return FormulaError(kind: .misplacedComma,
                                message: "Ein Komma ist nur zwischen Funktionsargumenten und Listenelementen erlaubt.",
                                range: token.range,
                                hint: "Dezimalzahlen mit Punkt schreiben, z. B. 0.5.")
        case .equals:
            return FormulaError(kind: .misplacedEquals,
                                message: "Ein einzelnes = ist nur in Definitionen am Zeilenanfang erlaubt.",
                                range: token.range,
                                hint: "Für Vergleiche == verwenden.")
        default:
            return FormulaError(kind: .missingOperand,
                                message: "Vor „\(describe(token))“ fehlt ein Wert.",
                                range: token.range,
                                hint: nil)
        }
    }

    private func unexpectedTokenError(_ token: FormulaToken) -> FormulaError {
        switch token.kind {
        case .invalid(let error):
            return error
        case .rightParen:
            return FormulaError(kind: .unexpectedClosingParenthesis,
                                message: "Zu dieser schließenden Klammer gibt es keine öffnende.",
                                range: token.range,
                                hint: nil)
        case .rightBracket:
            return FormulaError(kind: .unexpectedClosingParenthesis,
                                message: "Zu dieser eckigen Klammer gibt es keine öffnende.",
                                range: token.range,
                                hint: nil)
        case .comma:
            return FormulaError(kind: .misplacedComma,
                                message: "Ein Komma ist nur zwischen Funktionsargumenten und Listenelementen erlaubt.",
                                range: token.range,
                                hint: "Dezimalzahlen mit Punkt schreiben, z. B. 0.5.")
        case .equals:
            return FormulaError(kind: .misplacedEquals,
                                message: "Ein einzelnes = ist nur in Definitionen am Zeilenanfang erlaubt.",
                                range: token.range,
                                hint: "Für Vergleiche == verwenden, z. B. bar == 2.")
        case .leftBracket:
            return FormulaError(kind: .missingOperator,
                                message: "Unerwartete eckige Klammer.",
                                range: token.range,
                                hint: "Listen stehen allein oder werden mit name[i] indiziert.")
        default:
            return FormulaError(kind: .missingOperator,
                                message: "Unerwartetes „\(describe(token))“.",
                                range: token.range,
                                hint: nil)
        }
    }

    private func describe(_ token: FormulaToken) -> String {
        switch token.kind {
        case .number(let value): return value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .word(let spelling), .name(_, let spelling): return spelling
        case .keyword(let keyword): return keyword.rawValue
        case .plus: return "+"
        case .minus: return "-"
        case .star: return "*"
        case .slash: return "/"
        case .caret: return "^"
        case .less: return "<"
        case .lessEqual: return "<="
        case .greater: return ">"
        case .greaterEqual: return ">="
        case .equalEqual: return "=="
        case .notEqual: return "!="
        case .leftParen: return "("
        case .rightParen: return ")"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .comma: return ","
        case .equals: return "="
        case .newline: return "Zeilenende"
        case .end: return "Ende"
        case .invalid: return "?"
        }
    }
}
