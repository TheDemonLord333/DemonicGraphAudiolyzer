import Foundation

/// Recursive descent parser producing a `FormulaNode` AST.
///
/// Grammar (lowest to highest precedence):
/// ```
/// formula        := [ "y" "=" | "f" "(" "x" ")" "=" ] expression END
/// expression     := term { ("+" | "-") term }
/// term           := unary { ("*" | "/") unary | implicitFactor }
/// implicitFactor := power            // only if the next token is a name or "("
/// unary          := ("-" | "+") unary | power
/// power          := primary [ "^" unary ]   // right associative: 2^3^2 = 2^(3^2)
/// primary        := number | constant | variable | function "(" args ")" | "(" expression ")"
/// ```
/// Consequences: `-x^2 = -(x^2)`, `2^-1 = 0.5`, `2x^2 = 2·(x^2)`, `2sin(x) = 2·sin(x)`.
struct FormulaParser {
    static let maximumNesting = 64

    private let tokens: [FormulaToken]
    private var index = 0
    private var depth = 0

    init(tokens: [FormulaToken]) {
        self.tokens = tokens
    }

    static func parse(_ text: String) throws -> FormulaNode {
        let tokens = try FormulaLexer(text).tokenize()
        var parser = FormulaParser(tokens: tokens)
        return try parser.parseFormula()
    }

    private var current: FormulaToken { tokens[index] }

    private func peek(_ offset: Int) -> FormulaToken {
        tokens[min(index + offset, tokens.count - 1)]
    }

    private mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    // MARK: Formula

    mutating func parseFormula() throws -> FormulaNode {
        skipDefinitionPrefix()
        if case .end = current.kind {
            throw FormulaError(kind: .empty, message: "Bitte gib eine Formel ein.", range: nil, hint: "Zum Beispiel sin(x).")
        }
        let node = try parseExpression()
        guard case .end = current.kind else {
            throw unexpectedTokenError(current)
        }
        return node
    }

    /// Accepts `y = …` and `f(x) = …`.
    private mutating func skipDefinitionPrefix() {
        if case .name(.definitionName("y"), _) = current.kind, case .equals = peek(1).kind {
            index += 2
            return
        }
        if case .name(.definitionName("f"), _) = current.kind,
           case .leftParen = peek(1).kind,
           case .name(.variable(.x), _) = peek(2).kind,
           case .rightParen = peek(3).kind,
           case .equals = peek(4).kind {
            index += 5
        }
    }

    // MARK: Precedence levels

    private mutating func parseExpression() throws -> FormulaNode {
        depth += 1
        defer { depth -= 1 }
        if depth > Self.maximumNesting {
            throw FormulaError(kind: .nestingTooDeep, message: "Die Formel ist zu tief verschachtelt.", range: current.range, hint: nil)
        }
        var node = try parseTerm()
        while true {
            switch current.kind {
            case .plus:
                advance()
                node = .binary(.add, node, try parseTerm())
            case .minus:
                advance()
                node = .binary(.subtract, node, try parseTerm())
            default:
                return node
            }
        }
    }

    private mutating func parseTerm() throws -> FormulaNode {
        var node = try parseUnary()
        while true {
            switch current.kind {
            case .star:
                advance()
                node = .binary(.multiply, node, try parseUnary())
            case .slash:
                advance()
                node = .binary(.divide, node, try parseUnary())
            case .leftParen:
                node = .binary(.multiply, node, try parsePower())
            case .name(let name, _):
                if case .definitionName = name {
                    throw unexpectedTokenError(current)
                }
                node = .binary(.multiply, node, try parsePower())
            case .number:
                throw FormulaError(kind: .missingOperator,
                                   message: "Vor dieser Zahl fehlt ein Operator.",
                                   range: current.range,
                                   hint: "Schreibe z. B. x*2 oder 2*3.")
            default:
                return node
            }
        }
    }

    private mutating func parseUnary() throws -> FormulaNode {
        switch current.kind {
        case .minus:
            advance()
            return .negate(try parseUnary())
        case .plus:
            advance()
            return try parseUnary()
        default:
            return try parsePower()
        }
    }

    private mutating func parsePower() throws -> FormulaNode {
        let base = try parsePrimary()
        if case .caret = current.kind {
            advance()
            let exponent = try parseUnary()
            return .binary(.power, base, exponent)
        }
        return base
    }

    private mutating func parsePrimary() throws -> FormulaNode {
        let token = current
        switch token.kind {
        case .number(let value):
            advance()
            return .number(value)
        case .name(let name, let spelling):
            switch name {
            case .variable(let variable):
                advance()
                return .variable(variable)
            case .constant(let constant):
                advance()
                return .number(constant.value)
            case .function(let function):
                advance()
                return try parseCall(function, spelling: spelling, nameToken: token)
            case .definitionName(let definition):
                throw FormulaError(kind: .unknownName,
                                   message: "„\(definition)“ ist hier nicht erlaubt.",
                                   range: token.range,
                                   hint: "Die Variable heißt x. Am Anfang sind „y =“ oder „f(x) =“ erlaubt.")
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
            advance()
            return inner
        default:
            throw missingOperandError(at: token)
        }
    }

    private mutating func parseCall(_ function: MathFunction, spelling: String, nameToken: FormulaToken) throws -> FormulaNode {
        guard case .leftParen = current.kind else {
            throw FormulaError(kind: .functionNeedsParenthesis,
                               message: "Nach „\(spelling)“ wird eine Klammer erwartet.",
                               range: nameToken.range,
                               hint: "Schreibe z. B. \(function.rawValue)(x).")
        }
        let openToken = current
        advance()
        var arguments: [FormulaNode] = []
        if case .rightParen = current.kind {
            // Empty argument list – handled by the arity check below.
        } else {
            arguments.append(try parseExpression())
            while case .comma = current.kind {
                advance()
                arguments.append(try parseExpression())
            }
        }
        guard case .rightParen = current.kind else {
            throw FormulaError(kind: .missingClosingParenthesis,
                               message: "Die Klammer von „\(spelling)“ wird nicht geschlossen.",
                               range: openToken.range,
                               hint: "Ergänze „)“.")
        }
        advance()
        guard arguments.count == function.arity else {
            let expected = function.arity == 1 ? "1 Argument" : "\(function.arity) Argumente"
            let example = function.arity == 1 ? "\(function.rawValue)(x)" : "\(function.rawValue)(x, 2)"
            throw FormulaError(kind: .wrongArgumentCount,
                               message: "„\(spelling)“ erwartet \(expected), gefunden: \(arguments.count).",
                               range: nameToken.range,
                               hint: "Beispiel: \(example).")
        }
        return .call(function, arguments)
    }

    // MARK: Errors

    private func missingOperandError(at token: FormulaToken) -> FormulaError {
        switch token.kind {
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
                                message: "Ein Komma ist nur zwischen Funktionsargumenten erlaubt.",
                                range: token.range,
                                hint: "Dezimalzahlen mit Punkt schreiben, z. B. 0.5.")
        case .equals:
            return FormulaError(kind: .misplacedEquals,
                                message: "Ein Gleichheitszeichen ist nur am Anfang erlaubt.",
                                range: token.range,
                                hint: "Zum Beispiel y = sin(x).")
        default:
            return FormulaError(kind: .missingOperand,
                                message: "Vor „\(describe(token))“ fehlt ein Wert.",
                                range: token.range,
                                hint: nil)
        }
    }

    private func unexpectedTokenError(_ token: FormulaToken) -> FormulaError {
        switch token.kind {
        case .rightParen:
            return FormulaError(kind: .unexpectedClosingParenthesis,
                                message: "Zu dieser schließenden Klammer gibt es keine öffnende.",
                                range: token.range,
                                hint: nil)
        case .comma:
            return FormulaError(kind: .misplacedComma,
                                message: "Ein Komma ist nur zwischen Funktionsargumenten erlaubt.",
                                range: token.range,
                                hint: "Dezimalzahlen mit Punkt schreiben, z. B. 0.5.")
        case .equals:
            return FormulaError(kind: .misplacedEquals,
                                message: "Ein Gleichheitszeichen ist nur am Anfang erlaubt.",
                                range: token.range,
                                hint: "Zum Beispiel y = sin(x).")
        case .name(.definitionName(let name), _):
            return FormulaError(kind: .unknownName,
                                message: "„\(name)“ ist hier nicht erlaubt.",
                                range: token.range,
                                hint: "Die Variable heißt x.")
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
        case .name(_, let spelling): return spelling
        case .plus: return "+"
        case .minus: return "-"
        case .star: return "*"
        case .slash: return "/"
        case .caret: return "^"
        case .leftParen: return "("
        case .rightParen: return ")"
        case .comma: return ","
        case .equals: return "="
        case .end: return "Ende"
        }
    }
}
