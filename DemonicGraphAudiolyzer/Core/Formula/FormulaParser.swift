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

    /// Kind of the current token without copying its payload (keeps recursive frames small).
    private mutating func currentTag() -> TokenTag {
        expandWord(at: index)
        return tokens[index].kind.tag
    }

    private mutating func currentRange() -> SourceRange {
        expandWord(at: index)
        return tokens[index].range
    }

    /// Enters one level of recursion (brackets, calls, unary chains, powers).
    private mutating func enterLevel() throws {
        depth += 1
        if depth > Self.maximumNesting {
            throw nestingError()
        }
    }

    @inline(never)
    private mutating func nestingError() -> FormulaError {
        FormulaError(kind: .nestingTooDeep, message: "Die Formel ist zu tief verschachtelt.", range: currentRange(),
                     hint: "Höchstens \(Self.maximumNesting) Ebenen aus Klammern, Funktionsaufrufen, Vorzeichen und Potenzen.")
    }

    @inline(never)
    private mutating func currentUnexpectedTokenError() -> FormulaError {
        unexpectedTokenError(current)
    }

    @inline(never)
    private mutating func currentMissingOperandError() -> FormulaError {
        missingOperandError(at: current)
    }

    @inline(never)
    private static func comparisonChainError(_ range: SourceRange) -> FormulaError {
        FormulaError(kind: .comparisonChain,
                     message: "Vergleichsketten wie a < x < b werden nicht erraten.",
                     range: range,
                     hint: "Schreibe (a < x) and (x < b).")
    }

    @inline(never)
    private static func missingOperatorBeforeNumberError(_ range: SourceRange) -> FormulaError {
        FormulaError(kind: .missingOperator,
                     message: "Vor dieser Zahl fehlt ein Operator.",
                     range: range,
                     hint: "Schreibe z. B. x*2 oder 2*3.")
    }

    @inline(never)
    private static func indexTargetError(_ range: SourceRange) -> FormulaError {
        FormulaError(kind: .typeMismatch, message: "Nur Listen können mit [ ] indiziert werden.", range: range,
                     hint: "Beispiel: notes[2] oder [0, 3, 7][i].")
    }

    @inline(never)
    private static func unclosedError(_ range: SourceRange, bracket: Bool) -> FormulaError {
        bracket
            ? FormulaError(kind: .missingClosingParenthesis, message: "Die eckige Klammer wird nicht geschlossen.",
                           range: range, hint: "Ergänze „]“.")
            : FormulaError(kind: .missingClosingParenthesis, message: "Die Klammer wird nicht geschlossen.",
                           range: range, hint: "Ergänze „)“.")
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
        guard currentTag() == .end else {
            throw currentUnexpectedTokenError()
        }
        return expression
    }

    // MARK: - Precedence levels
    //
    // These functions recurse once per bracket level. They only look at payload-free token tags
    // and build errors out of line, so that every frame stays small – iOS runs background work
    // on threads with 512 KB of stack, and debug builds do not share stack slots.

    private mutating func parseExpression() throws -> SyntaxExpression {
        try enterLevel()
        defer { depth -= 1 }
        return try parseOr()
    }

    private mutating func parseOr() throws -> SyntaxExpression {
        var node = try parseAnd()
        while currentTag() == .or {
            let range = currentRange()
            advance()
            node = .binary(.or, node, try parseAnd(), implicit: false, range)
        }
        return node
    }

    private mutating func parseAnd() throws -> SyntaxExpression {
        var node = try parseNot()
        while currentTag() == .and {
            let range = currentRange()
            advance()
            node = .binary(.and, node, try parseNot(), implicit: false, range)
        }
        return node
    }

    private mutating func parseNot() throws -> SyntaxExpression {
        guard currentTag() == .not else {
            return try parseComparison()
        }
        let range = currentRange()
        advance()
        try enterLevel()
        defer { depth -= 1 }
        return .not(try parseNot(), range)
    }

    private static func comparisonOperator(_ tag: TokenTag) -> BinaryOperator? {
        switch tag {
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
        guard let op = Self.comparisonOperator(currentTag()) else { return left }
        let range = currentRange()
        advance()
        let right = try parseAdditive()
        if Self.comparisonOperator(currentTag()) != nil {
            throw Self.comparisonChainError(currentRange())
        }
        return .binary(op, left, right, implicit: false, range)
    }

    private mutating func parseAdditive() throws -> SyntaxExpression {
        var node = try parseTerm()
        while true {
            let tag = currentTag()
            guard tag == .plus || tag == .minus else { return node }
            let range = currentRange()
            advance()
            node = .binary(tag == .plus ? .add : .subtract, node, try parseTerm(), implicit: false, range)
        }
    }

    private mutating func parseTerm() throws -> SyntaxExpression {
        var node = try parseUnary()
        while true {
            let tag = currentTag()
            let range = currentRange()
            switch tag {
            case .star, .slash:
                advance()
                node = .binary(tag == .star ? .multiply : .divide, node, try parseUnary(), implicit: false, range)
            case .leftParen, .name, .invalid:
                node = .binary(.multiply, node, try parsePower(), implicit: true, range)
            case .number:
                throw Self.missingOperatorBeforeNumberError(range)
            default:
                return node
            }
        }
    }

    private mutating func parseUnary() throws -> SyntaxExpression {
        let tag = currentTag()
        guard tag == .minus || tag == .plus else {
            return try parsePower()
        }
        let range = currentRange()
        advance()
        try enterLevel()
        defer { depth -= 1 }
        let operand = try parseUnary()
        return tag == .minus ? .negate(operand, range) : operand
    }

    private mutating func parsePower() throws -> SyntaxExpression {
        let base = try parsePostfix()
        guard currentTag() == .caret else { return base }
        let range = currentRange()
        advance()
        try enterLevel()
        defer { depth -= 1 }
        let exponent = try parseUnary()
        return .binary(.power, base, exponent, implicit: false, range)
    }

    private mutating func parsePostfix() throws -> SyntaxExpression {
        var node = try parsePrimary()
        while currentTag() == .leftBracket {
            switch node {
            case .name, .list, .index: break
            default: throw Self.indexTargetError(currentRange())
            }
            node = try parseIndex(of: node)
        }
        return node
    }

    private mutating func parseIndex(of node: SyntaxExpression) throws -> SyntaxExpression {
        let open = currentRange()
        advance()
        let indexExpression = try parseExpression()
        guard currentTag() == .rightBracket else {
            throw Self.unclosedError(open, bracket: true)
        }
        let close = currentRange()
        advance()
        return .index(node, indexExpression, open.union(close))
    }

    private mutating func parsePrimary() throws -> SyntaxExpression {
        switch currentTag() {
        case .number, .name, .invalid:
            return try parseOperand()
        case .leftParen:
            return try parseGroup()
        case .leftBracket:
            return try parseList()
        default:
            throw currentMissingOperandError()
        }
    }

    private mutating func parseGroup() throws -> SyntaxExpression {
        let open = currentRange()
        advance()
        let inner = try parseExpression()
        guard currentTag() == .rightParen else {
            throw Self.unclosedError(open, bracket: false)
        }
        let close = currentRange()
        advance()
        return .group(inner, open.union(close))
    }

    private enum OperandStart {
        case done(SyntaxExpression)
        case call(id: String, spelling: String, nameToken: FormulaToken)
        case userCall(name: String, arity: Int, nameToken: FormulaToken)
    }

    /// Number, name, function call or invalid word.
    private mutating func parseOperand() throws -> SyntaxExpression {
        switch try operandStart() {
        case .done(let expression):
            return expression
        case .call(let id, let spelling, let nameToken):
            return try parseCall(id: id, spelling: spelling, nameToken: nameToken)
        case .userCall(let name, let arity, let nameToken):
            return try parseUserCall(name: name, arity: arity, nameToken: nameToken)
        }
    }

    /// The non-recursive part of an operand (the only place that copies a token).
    @inline(never)
    private mutating func operandStart() throws -> OperandStart {
        let token = current
        switch token.kind {
        case .invalid(let error):
            throw error
        case .number(let value):
            advance()
            return .done(.number(value, token.range))
        case .name(let reference, let spelling):
            advance()
            switch reference {
            case .function(let id):
                return .call(id: id, spelling: spelling, nameToken: token)
            case .definition(let name):
                if case .function(let arity) = definitions[name] {
                    return .userCall(name: name, arity: arity, nameToken: token)
                }
                return .done(.name(reference, spelling: spelling, token.range))
            default:
                return .done(.name(reference, spelling: spelling, token.range))
            }
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
        let call = try beginCall(id: id, spelling: spelling, nameRange: nameToken.range)
        if call.isAggregate {
            return try parseAggregate(id: call.id, spelling: spelling, nameRange: nameToken.range, open: call.open)
        }
        let arguments = try parseArguments()
        return try finishCall(id: call.id, spelling: spelling, arguments: arguments, nameRange: nameToken.range, open: call.open)
    }

    /// Checks the function name and the opening parenthesis (non-recursive part).
    @inline(never)
    private mutating func beginCall(id: String, spelling: String, nameRange: SourceRange) throws -> (id: String, isAggregate: Bool, open: SourceRange) {
        guard let call = Self.callInfo(id) else {
            throw unknownNameError(spelling, range: nameRange, isCall: true)
        }
        guard currentTag() == .leftParen else {
            throw Self.callError(.needsParenthesis, spelling: spelling, syntax: Self.syntax(of: call.id), range: nameRange)
        }
        let open = currentRange()
        advance()
        return (call.id, call.isAggregate, open)
    }

    /// Checks the closing parenthesis and the number of arguments (non-recursive part).
    @inline(never)
    private mutating func finishCall(id: String, spelling: String, arguments: [SyntaxExpression], nameRange: SourceRange,
                                     open: SourceRange) throws -> SyntaxExpression {
        guard currentTag() == .rightParen else {
            if currentTag() == .end {
                throw Self.callError(.unclosed, spelling: spelling, syntax: "", range: open)
            }
            throw currentUnexpectedTokenError()
        }
        advance()
        if let error = argumentCountProblem(id: id, spelling: spelling, found: arguments.count, range: nameRange) {
            throw error
        }
        return .call(.function(id), spelling: spelling, arguments: arguments, nameRange)
    }

    /// Canonical id of a catalogue function and whether it is sum/prod (no large spec copies in
    /// the recursive frames).
    @inline(never)
    private static func callInfo(_ id: String) -> (id: String, isAggregate: Bool)? {
        guard let spec = FormulaCatalog.function(named: id) else { return nil }
        return (spec.id, spec.implementation == .special(.sum) || spec.implementation == .special(.prod))
    }

    @inline(never)
    private static func syntax(of id: String) -> String {
        FormulaCatalog.function(named: id)?.syntax ?? id + "(…)"
    }

    @inline(never)
    private func argumentCountProblem(id: String, spelling: String, found: Int, range: SourceRange) -> FormulaError? {
        guard let spec = FormulaCatalog.function(named: id), !spec.accepts(found) else { return nil }
        return argumentCountError(spec: spec, spelling: spelling, found: found, range: range)
    }

    @inline(never)
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

    /// Comma separated arguments up to (not including) the closing parenthesis.
    private mutating func parseArguments() throws -> [SyntaxExpression] {
        var arguments: [SyntaxExpression] = []
        if currentTag() == .rightParen { return arguments }
        arguments.append(try parseExpression())
        while currentTag() == .comma {
            advance()
            arguments.append(try parseExpression())
        }
        return arguments
    }

    private enum CallProblem {
        case needsParenthesis, unclosed, userNeedsParenthesis, aggregateVariable, aggregateArgumentCount
    }

    @inline(never)
    private static func callError(_ problem: CallProblem, spelling: String, syntax: String, range: SourceRange,
                                  missing: String = "", id: String = "") -> FormulaError {
        switch problem {
        case .needsParenthesis:
            return FormulaError(kind: .functionNeedsParenthesis, message: "Nach „\(spelling)“ wird eine Klammer erwartet.",
                                range: range, hint: "Schreibe z. B. \(syntax).")
        case .unclosed:
            return FormulaError(kind: .missingClosingParenthesis, message: "Die Klammer von „\(spelling)“ wird nicht geschlossen.",
                                range: range, hint: "Ergänze „)“.")
        case .userNeedsParenthesis:
            return FormulaError(kind: .functionNeedsParenthesis, message: "Die Hilfsfunktion „\(spelling)“ braucht Argumente in Klammern.",
                                range: range, hint: "Schreibe z. B. \(spelling)(x).")
        case .aggregateVariable:
            return FormulaError(kind: .invalidArgument,
                                message: "Das erste Argument von „\(spelling)“ muss der Name der Laufvariable sein.",
                                range: range, hint: "Syntax: \(syntax), z. B. \(id)(i, 1, 5, i).")
        case .aggregateArgumentCount:
            if missing.isEmpty {
                return FormulaError(kind: .wrongArgumentCount, message: "„\(spelling)“ erwartet genau 4 Argumente: \(syntax).",
                                    range: range, hint: nil)
            }
            return FormulaError(kind: .wrongArgumentCount,
                                message: "„\(spelling)“ erwartet 4 Argumente: \(syntax). Es fehlt \(missing).",
                                range: range, hint: "Beispiel: \(id)(i, 1, 5, i).")
        }
    }

    @inline(never)
    private static func userArityError(_ name: String, arity: Int, found: Int, range: SourceRange) -> FormulaError {
        FormulaError(kind: .wrongArgumentCount,
                     message: "„\(name)“ erwartet \(arity == 1 ? "1 Argument" : "\(arity) Argumente"), gefunden: \(found).",
                     range: range, hint: nil)
    }

    /// The first argument of sum/prod: a new name, taken literally (no segmentation).
    private func loopVariable() -> (name: String, range: SourceRange)? {
        let token = tokens[index]
        guard case .word(let variable) = token.kind,
              variable.first?.isASCIILetter == true,
              FormulaConstant(rawValue: variable.lowercased()) == nil,
              FormulaCatalog.function(named: variable) == nil,
              LogicKeyword(rawValue: variable.lowercased()) == nil else {
            return nil
        }
        return (variable, token.range)
    }

    private mutating func expectAggregateComma(id: String, spelling: String, nameRange: SourceRange, missing: String) throws {
        guard currentTag() == .comma else {
            if case .invalid(let error) = tokens[index].kind { throw error }
            throw Self.callError(.aggregateArgumentCount, spelling: spelling, syntax: Self.syntax(of: id), range: nameRange,
                                 missing: missing, id: id)
        }
        advance()
    }

    private mutating func parseAggregate(id: String, spelling: String, nameRange: SourceRange, open: SourceRange) throws -> SyntaxExpression {
        // 1. Loop variable.
        guard let variable = loopVariable() else {
            throw Self.callError(.aggregateVariable, spelling: spelling, syntax: Self.syntax(of: id), range: tokens[index].range, id: id)
        }
        advance()
        try expectAggregateComma(id: id, spelling: spelling, nameRange: nameRange, missing: "der Start")
        // 2./3. Start and end are evaluated outside the scope of the loop variable.
        let start = try parseExpression()
        try expectAggregateComma(id: id, spelling: spelling, nameRange: nameRange, missing: "das Ende")
        let end = try parseExpression()
        try expectAggregateComma(id: id, spelling: spelling, nameRange: nameRange, missing: "der Ausdruck")
        // 4. The body sees the loop variable (it shadows outer names).
        localScopes.append([variable.name])
        let body = try parseExpression()
        localScopes.removeLast()
        guard currentTag() == .rightParen else {
            if currentTag() == .comma {
                throw Self.callError(.aggregateArgumentCount, spelling: spelling, syntax: Self.syntax(of: id), range: nameRange)
            }
            throw Self.callError(.unclosed, spelling: spelling, syntax: "", range: open)
        }
        advance()
        let variableName = SyntaxExpression.name(.local(variable.name), spelling: variable.name, variable.range)
        return .call(.function(id), spelling: spelling, arguments: [variableName, start, end, body], nameRange)
    }

    private mutating func parseUserCall(name: String, arity: Int, nameToken: FormulaToken) throws -> SyntaxExpression {
        guard currentTag() == .leftParen else {
            throw Self.callError(.userNeedsParenthesis, spelling: name, syntax: "", range: nameToken.range)
        }
        let open = currentRange()
        advance()
        let arguments = try parseArguments()
        guard currentTag() == .rightParen else {
            throw Self.callError(.unclosed, spelling: name, syntax: "", range: open)
        }
        advance()
        guard arguments.count == arity else {
            throw Self.userArityError(name, arity: arity, found: arguments.count, range: nameToken.range)
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
