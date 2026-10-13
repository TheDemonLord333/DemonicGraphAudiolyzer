import Foundation

/// Names that the formula language knows.
enum FormulaName: Equatable, Sendable {
    case variable(FormulaVariable)
    case constant(FormulaConstant)
    case function(MathFunction)
    /// `y` or `f` – only allowed in the prefix `y =` / `f(x) =`.
    case definitionName(String)
}

enum FormulaVariable: String, CaseIterable, Sendable {
    case x, a, b, c
}

enum FormulaConstant: String, CaseIterable, Sendable {
    case pi, e

    var value: Double {
        switch self {
        case .pi: return Double.pi
        case .e: return M_E
        }
    }
}

enum TokenKind: Equatable, Sendable {
    case number(Double)
    case name(FormulaName, spelling: String)
    case plus, minus, star, slash, caret
    case leftParen, rightParen, comma, equals
    case end
}

struct FormulaToken: Equatable, Sendable {
    var kind: TokenKind
    var range: SourceRange
}

/// Converts formula text into tokens. Never executes anything; unknown input is rejected.
///
/// Letter sequences are split into known names with longest-match-first backtracking,
/// which makes implicit multiplication such as `bx` (= b·x) or `2pi` possible while
/// function names keep priority (`asin` is the function, not a·sin).
struct FormulaLexer {
    static let maximumLength = 500

    /// All known spellings, longest first (important for the segmentation).
    private static let vocabulary: [(String, FormulaName)] = {
        var entries: [(String, FormulaName)] = []
        for function in MathFunction.allCases {
            entries.append((function.rawValue, .function(function)))
        }
        for constant in FormulaConstant.allCases {
            entries.append((constant.rawValue, .constant(constant)))
        }
        for variable in FormulaVariable.allCases {
            entries.append((variable.rawValue, .variable(variable)))
        }
        entries.append(("y", .definitionName("y")))
        entries.append(("f", .definitionName("f")))
        return entries.sorted { $0.0.count > $1.0.count }
    }()

    let source: [Character]

    init(_ text: String) {
        self.source = Array(text)
    }

    func tokenize() throws -> [FormulaToken] {
        if source.count > Self.maximumLength {
            throw FormulaError(kind: .tooLong,
                               message: "Die Formel ist zu lang (höchstens \(Self.maximumLength) Zeichen).",
                               range: nil, hint: nil)
        }
        var tokens: [FormulaToken] = []
        var index = 0
        while index < source.count {
            let character = source[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isASCIIDigit || (character == "." && index + 1 < source.count && source[index + 1].isASCIIDigit) {
                let (token, next) = try readNumber(at: index)
                tokens.append(token)
                index = next
                continue
            }
            if character == "π" {
                tokens.append(FormulaToken(kind: .name(.constant(.pi), spelling: "π"), range: SourceRange(start: index, end: index + 1)))
                index += 1
                continue
            }
            if character.isASCIILetter {
                let (nameTokens, next) = try readNames(at: index)
                tokens.append(contentsOf: nameTokens)
                index = next
                continue
            }
            let range = SourceRange(start: index, end: index + 1)
            switch character {
            case "+":
                tokens.append(FormulaToken(kind: .plus, range: range))
            case "-", "−", "–":
                tokens.append(FormulaToken(kind: .minus, range: range))
            case "*", "·", "×", "⋅", "∙":
                tokens.append(FormulaToken(kind: .star, range: range))
            case "/", "÷", "∕":
                tokens.append(FormulaToken(kind: .slash, range: range))
            case "^":
                tokens.append(FormulaToken(kind: .caret, range: range))
            case "²", "³":
                tokens.append(FormulaToken(kind: .caret, range: range))
                tokens.append(FormulaToken(kind: .number(character == "²" ? 2 : 3), range: range))
            case "(":
                tokens.append(FormulaToken(kind: .leftParen, range: range))
            case ")":
                tokens.append(FormulaToken(kind: .rightParen, range: range))
            case ",", ";":
                tokens.append(FormulaToken(kind: .comma, range: range))
            case "=":
                tokens.append(FormulaToken(kind: .equals, range: range))
            case "√":
                tokens.append(FormulaToken(kind: .name(.function(.sqrt), spelling: "√"), range: range))
            default:
                throw FormulaError(kind: .unexpectedCharacter,
                                   message: "Unerwartetes Zeichen „\(character)“.",
                                   range: range,
                                   hint: "Erlaubt sind Zahlen, x, a, b, c, pi, e, Funktionen, + - * / ^ und Klammern.")
            }
            index += 1
        }
        tokens.append(FormulaToken(kind: .end, range: SourceRange(start: source.count, end: source.count + 1)))
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
        // A decimal comma directly between digits ("0,5") is a common German typo.
        if index + 1 < source.count, source[index] == ",", source[index + 1].isASCIIDigit, !isInsideFunctionCall(before: start) {
            throw FormulaError(kind: .invalidNumber,
                               message: "Dezimalzahlen werden mit Punkt geschrieben.",
                               range: SourceRange(start: start, end: index + 2),
                               hint: "Schreibe z. B. 0.5 statt 0,5.")
        }
        return (FormulaToken(kind: .number(value), range: SourceRange(start: start, end: index)), index)
    }

    /// Rough check whether the position is inside parentheses that belong to a function call
    /// (then a comma is an argument separator, not a decimal comma).
    private func isInsideFunctionCall(before position: Int) -> Bool {
        var depth = 0
        var index = position - 1
        while index >= 0 {
            let character = source[index]
            if character == ")" { depth += 1 }
            if character == "(" {
                if depth == 0 {
                    return index > 0 && source[index - 1].isASCIILetter
                }
                depth -= 1
            }
            index -= 1
        }
        return false
    }

    private func readNames(at start: Int) throws -> ([FormulaToken], Int) {
        var index = start
        while index < source.count, source[index].isASCIILetter {
            index += 1
        }
        var word = String(source[start..<index]).lowercased()
        // log10 is the only name containing digits.
        if word.hasSuffix("log"), index + 1 < source.count, source[index] == "1", source[index + 1] == "0" {
            word += "10"
            index += 2
        }
        let letters = Array(word)
        guard let parts = Self.segment(letters, from: 0) else {
            let hint: String
            if word == "log" {
                hint = "Verwende ln(x) für den natürlichen oder log10(x) für den Zehnerlogarithmus."
            } else if word == "t" {
                hint = "Die Variable heißt x."
            } else {
                hint = "Bekannt sind x, a, b, c, pi, e und die Funktionen der Zusatztastatur."
            }
            throw FormulaError(kind: .unknownName,
                               message: "Unbekannter Name „\(word)“.",
                               range: SourceRange(start: start, end: index),
                               hint: hint)
        }
        var tokens: [FormulaToken] = []
        var offset = start
        for (spelling, name) in parts {
            let length = spelling.count
            tokens.append(FormulaToken(kind: .name(name, spelling: spelling),
                                       range: SourceRange(start: offset, end: offset + length)))
            offset += length
        }
        return (tokens, index)
    }

    /// Longest-match-first segmentation with backtracking.
    private static func segment(_ letters: [Character], from position: Int) -> [(String, FormulaName)]? {
        if position == letters.count { return [] }
        for (spelling, name) in vocabulary {
            let candidate = Array(spelling)
            guard position + candidate.count <= letters.count else { continue }
            if Array(letters[position..<position + candidate.count]) == candidate,
               let rest = segment(letters, from: position + candidate.count) {
                return [(spelling, name)] + rest
            }
        }
        return nil
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
}
