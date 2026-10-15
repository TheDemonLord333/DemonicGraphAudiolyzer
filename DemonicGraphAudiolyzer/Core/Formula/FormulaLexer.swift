import Foundation

/// A name after resolution (see `FormulaParser.resolveWord`).
enum NameReference: Equatable, Sendable {
    /// Built-in function, by catalogue id.
    case function(String)
    case constant(FormulaConstant)
    case variable(FormulaVariable)
    /// User definition (value, list or helper function) of the program.
    case definition(String)
    /// Loop variable of sum/prod or parameter of a helper function.
    case local(String)
    /// Unknown name accepted as parameter (simple editor of the formula synthesizer).
    case autoParameter(String)
}

enum LogicKeyword: String, Sendable {
    case and, or, not
}

enum TokenKind: Equatable, Sendable {
    case number(Double)
    /// An unresolved run of letters, digits and underscores (Greek letters already spelled out).
    case word(String)
    /// A resolved name (produced by the parser from a word).
    case name(NameReference, spelling: String)
    case keyword(LogicKeyword)
    case plus, minus, star, slash, caret
    case less, lessEqual, greater, greaterEqual, equalEqual, notEqual
    case leftParen, rightParen, leftBracket, rightBracket, comma, equals
    case newline
    case end
    /// A word that could not be resolved; parsing it throws the stored error.
    /// Indirect so that tokens stay small (parser frames are copied a lot in debug builds).
    indirect case invalid(FormulaError)
}

/// Payload-free kind of a token for cheap checks in the recursive parser.
enum TokenTag: UInt8, Sendable {
    case number, word, name, and, or, not
    case plus, minus, star, slash, caret
    case less, lessEqual, greater, greaterEqual, equalEqual, notEqual
    case leftParen, rightParen, leftBracket, rightBracket, comma, equals
    case newline, end, invalid
}

extension TokenKind {
    var tag: TokenTag {
        switch self {
        case .number: return .number
        case .word: return .word
        case .name: return .name
        case .keyword(let keyword):
            switch keyword {
            case .and: return .and
            case .or: return .or
            case .not: return .not
            }
        case .plus: return .plus
        case .minus: return .minus
        case .star: return .star
        case .slash: return .slash
        case .caret: return .caret
        case .less: return .less
        case .lessEqual: return .lessEqual
        case .greater: return .greater
        case .greaterEqual: return .greaterEqual
        case .equalEqual: return .equalEqual
        case .notEqual: return .notEqual
        case .leftParen: return .leftParen
        case .rightParen: return .rightParen
        case .leftBracket: return .leftBracket
        case .rightBracket: return .rightBracket
        case .comma: return .comma
        case .equals: return .equals
        case .newline: return .newline
        case .end: return .end
        case .invalid: return .invalid
        }
    }
}

struct FormulaToken: Equatable, Sendable {
    var kind: TokenKind
    var range: SourceRange
    /// 1-based line.
    var line: Int = 1
    /// Words: source offset of each character of the spelled-out word.
    var offsets: [Int] = []
}

/// Converts formula text into tokens. Never executes anything; unknown input is rejected.
///
/// Identifiers are runs of letters, digits and underscores that start with a letter. Their
/// meaning (one name or several names multiplied implicitly, e.g. `2pix`) is decided by the
/// parser, which knows the definitions and local variables in scope.
struct FormulaLexer {
    /// Maximum length of one line (the classic single-line formula).
    static let maximumLineLength = 500
    /// Maximum length of a multi-line program.
    static let maximumLength = 4_000
    static let maximumLines = 80

    /// Greek input aliases. Σ and Π stand for sum and prod, √ for sqrt.
    static let greekAliases: [Character: String] = [
        "α": "alpha", "β": "beta", "γ": "gamma", "δ": "delta", "ε": "epsilon", "ζ": "zeta", "η": "eta",
        "θ": "theta", "κ": "kappa", "λ": "lambda", "μ": "mu", "ν": "nu", "ξ": "xi", "π": "pi", "ρ": "rho",
        "σ": "sigma", "ς": "sigma", "τ": "tau", "υ": "upsilon", "φ": "phi", "ϕ": "phi", "χ": "chi",
        "ψ": "psi", "ω": "omega",
        "Γ": "Gamma", "Δ": "Delta", "Θ": "Theta", "Λ": "Lambda", "Φ": "Phi", "Ψ": "Psi", "Ω": "Omega",
        "Σ": "sum", "Π": "prod", "√": "sqrt"
    ]

    let source: [Character]

    init(_ text: String) {
        self.source = Array(text)
    }

    /// 0-based offsets where each line starts.
    var lineStarts: [Int] {
        var starts = [0]
        for (index, character) in source.enumerated() where character == "\n" || character == "\r\n" {
            starts.append(index + 1)
        }
        return starts
    }

    func tokenize() throws -> [FormulaToken] {
        if source.count > Self.maximumLength {
            throw FormulaError(kind: .tooLong,
                               message: "Die Formel ist zu lang (höchstens \(Self.maximumLength) Zeichen).",
                               range: nil, hint: nil)
        }
        var tokens: [FormulaToken] = []
        var index = 0
        var line = 1
        var lineStart = 0

        func checkLineLength(endingAt end: Int) throws {
            if end - lineStart > Self.maximumLineLength {
                throw FormulaError(kind: .tooLong,
                                   message: "Die Zeile ist zu lang (höchstens \(Self.maximumLineLength) Zeichen).",
                                   range: nil, hint: "Teile lange Formeln im erweiterten Editor in Zwischenwerte auf.", line: line)
            }
        }

        while index < source.count {
            let character = source[index]
            if character == "\n" || character == "\r\n" || character == "\r" {
                try checkLineLength(endingAt: index)
                tokens.append(FormulaToken(kind: .newline, range: SourceRange(start: index, end: index + 1), line: line))
                line += 1
                if line > Self.maximumLines {
                    throw FormulaError(kind: .tooLong, message: "Zu viele Zeilen (höchstens \(Self.maximumLines)).",
                                       range: nil, hint: nil, line: line)
                }
                index += 1
                lineStart = index
                continue
            }
            if character.isWhitespace {
                index += 1
                continue
            }
            if character == "#" {
                // Comment until the end of the line.
                while index < source.count, !(source[index] == "\n" || source[index] == "\r\n" || source[index] == "\r") {
                    index += 1
                }
                continue
            }
            if character.isASCIIDigit || (character == "." && index + 1 < source.count && source[index + 1].isASCIIDigit) {
                var (token, next) = try readNumber(at: index)
                token.line = line
                tokens.append(token)
                index = next
                continue
            }
            if character.isASCIILetter || Self.greekAliases[character] != nil {
                var (token, next) = readWord(at: index)
                token.line = line
                if case .word(let spelling) = token.kind, let keyword = LogicKeyword(rawValue: spelling.lowercased()) {
                    token.kind = .keyword(keyword)
                }
                tokens.append(token)
                index = next
                continue
            }

            let range = SourceRange(start: index, end: index + 1)
            let next: Character? = index + 1 < source.count ? source[index + 1] : nil
            var kind: TokenKind?
            var length = 1
            switch character {
            case "+": kind = .plus
            case "-", "−", "–": kind = .minus
            case "*", "·", "×", "⋅", "∙": kind = .star
            case "/", "÷", "∕": kind = .slash
            case "^": kind = .caret
            case "²", "³":
                tokens.append(FormulaToken(kind: .caret, range: range, line: line))
                kind = .number(character == "²" ? 2 : 3)
            case "(": kind = .leftParen
            case ")": kind = .rightParen
            case "[": kind = .leftBracket
            case "]": kind = .rightBracket
            case ",", ";": kind = .comma
            case "=":
                if next == "=" { kind = .equalEqual; length = 2 } else { kind = .equals }
            case "<":
                if next == "=" { kind = .lessEqual; length = 2 } else { kind = .less }
            case ">":
                if next == "=" { kind = .greaterEqual; length = 2 } else { kind = .greater }
            case "≤": kind = .lessEqual
            case "≥": kind = .greaterEqual
            case "≠": kind = .notEqual
            case "!":
                if next == "=" {
                    kind = .notEqual
                    length = 2
                } else {
                    throw FormulaError(kind: .unexpectedCharacter, message: "„!“ wird nicht unterstützt.", range: range,
                                       hint: "Für „nicht“ schreibe not(…), für „ungleich“ !=. Fakultäten gibt es nicht.", line: line)
                }
            case "|":
                throw FormulaError(kind: .unexpectedCharacter, message: "Betragsstriche werden nicht als Eingabe akzeptiert.", range: range,
                                   hint: "Schreibe abs(x) – die Darstellung zeigt dann |x|.", line: line)
            case "{", "}":
                throw FormulaError(kind: .unexpectedCharacter, message: "Geschweifte Klammern gibt es nur in der Darstellung von Fallunterscheidungen.", range: range,
                                   hint: "Verwende piecewise(bedingung1, ausdruck1, …, sonstAusdruck) oder if(bedingung, dann, sonst).", line: line)
            case "&":
                throw FormulaError(kind: .unexpectedCharacter, message: "„&“ wird nicht unterstützt.", range: range,
                                   hint: "Bedingungen mit and verknüpfen.", line: line)
            default:
                break
            }
            guard let kind else {
                throw FormulaError(kind: .unexpectedCharacter,
                                   message: "Unerwartetes Zeichen „\(character)“.",
                                   range: range,
                                   hint: "Erlaubt sind Zahlen, Namen, Funktionen, + - * / ^, Vergleiche, Klammern ( ) und [ ].",
                                   line: line)
            }
            tokens.append(FormulaToken(kind: kind, range: SourceRange(start: index, end: index + length), line: line))
            index += length
        }
        try checkLineLength(endingAt: source.count)
        tokens.append(FormulaToken(kind: .end, range: SourceRange(start: source.count, end: source.count + 1), line: line))
        return tokens
    }

    private func readNumber(at start: Int) throws -> (FormulaToken, Int) {
        var index = start
        var text = ""
        var seenDot = false
        while index < source.count {
            let character = source[index]
            if character.isASCIIDigit {
                text.append(character)
            } else if character == "." {
                if seenDot {
                    throw FormulaError(kind: .invalidNumber,
                                       message: "Ungültige Zahl mit mehreren Dezimalpunkten.",
                                       range: SourceRange(start: start, end: index + 1),
                                       hint: nil)
                }
                seenDot = true
                text.append(character)
            } else {
                break
            }
            index += 1
        }
        if text.hasSuffix(".") {
            text.append("0")
        }
        if text.hasPrefix(".") {
            text = "0" + text
        }
        guard let value = Double(text), value.isFinite else {
            throw FormulaError(kind: .invalidNumber,
                               message: "Ungültige Zahl „\(text)“.",
                               range: SourceRange(start: start, end: index),
                               hint: nil)
        }
        // A decimal comma directly between digits ("0,5") is a common German typo –
        // unless the comma separates arguments of a call or elements of a list.
        if index + 1 < source.count, source[index] == ",", source[index + 1].isASCIIDigit, !isArgumentSeparator(before: start) {
            throw FormulaError(kind: .invalidNumber,
                               message: "Dezimalzahlen werden mit Punkt geschrieben.",
                               range: SourceRange(start: start, end: index + 2),
                               hint: "Schreibe z. B. 0.5 statt 0,5.")
        }
        return (FormulaToken(kind: .number(value), range: SourceRange(start: start, end: index)), index)
    }

    /// Is the position inside the parentheses of a call (`name(…)`) or a list (`[…]`)?
    /// Then a comma separates arguments and is not a decimal comma.
    private func isArgumentSeparator(before position: Int) -> Bool {
        var depth = 0
        var index = position - 1
        while index >= 0 {
            let character = source[index]
            if character == ")" || character == "]" { depth += 1 }
            if character == "(" || character == "[" {
                if depth == 0 {
                    if character == "[" { return true }
                    // Find the run before "(" – a call if it starts with a letter.
                    var runStart = index
                    while runStart > 0, source[runStart - 1].isWordCharacter {
                        runStart -= 1
                    }
                    guard runStart < index else { return false }
                    let first = source[runStart]
                    return first.isASCIILetter || Self.greekAliases[first] != nil
                }
                depth -= 1
            }
            if character == "\n" { return false }
            index -= 1
        }
        return false
    }

    private func readWord(at start: Int) -> (FormulaToken, Int) {
        var index = start
        var spelling = ""
        var offsets: [Int] = []
        while index < source.count {
            let character = source[index]
            if let alias = Self.greekAliases[character] {
                spelling += alias
                offsets += Array(repeating: index, count: alias.count)
            } else if character.isASCIILetter || character.isASCIIDigit || character == "_" {
                spelling.append(character)
                offsets.append(index)
            } else {
                break
            }
            index += 1
        }
        return (FormulaToken(kind: .word(spelling), range: SourceRange(start: start, end: index), offsets: offsets), index)
    }
}

extension Character {
    var isASCIIDigit: Bool {
        guard let ascii = asciiValue else { return false }
        return ascii >= 48 && ascii <= 57
    }

    var isASCIILetter: Bool {
        guard let ascii = asciiValue else { return false }
        return (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122)
    }

    /// Letter, digit, underscore or Greek alias.
    var isWordCharacter: Bool {
        isASCIILetter || isASCIIDigit || self == "_" || FormulaLexer.greekAliases[self] != nil
    }
}
