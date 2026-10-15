import Foundation

/// Character range inside a formula source (0-based, end exclusive, counted in `Character`s).
struct SourceRange: Equatable, Hashable, Sendable {
    var start: Int
    var end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = max(end, start + 1)
    }

    var length: Int { end - start }

    /// Smallest range containing both.
    func union(_ other: SourceRange) -> SourceRange {
        SourceRange(start: min(start, other.start), end: max(end, other.end))
    }
}

/// A user-facing formula error with an optional position.
struct FormulaError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case empty
        case tooLong
        case unexpectedCharacter
        case invalidNumber
        case unknownName
        case missingOperator
        case missingOperand
        case missingClosingParenthesis
        case unexpectedClosingParenthesis
        case functionNeedsParenthesis
        case wrongArgumentCount
        case misplacedComma
        case misplacedEquals
        case nestingTooDeep
        // Language version 2
        case invalidDefinition
        case duplicateDefinition
        case cyclicDefinition
        case typeMismatch
        case invalidArgument
        case comparisonChain
        case missingOutput
        case multipleOutputs
        case tooComplex
    }

    var kind: Kind
    var message: String
    var range: SourceRange?
    var hint: String?
    /// 1-based line inside the source (multi-line programs).
    var line: Int?
    /// 1-based column inside `line` (multi-line programs).
    var column: Int?
    /// Name of the source the error belongs to (e.g. "Projekt-Definitionen"); nil = the edited formula.
    var sourceName: String?

    init(kind: Kind, message: String, range: SourceRange?, hint: String?,
         line: Int? = nil, column: Int? = nil, sourceName: String? = nil) {
        self.kind = kind
        self.message = message
        self.range = range
        self.hint = hint
        self.line = line
        self.column = column
        self.sourceName = sourceName
    }

    /// Single line description used in UI and accessibility.
    /// Names the source, the line (for multi-line programs) and the position.
    var localizedSummary: String {
        var prefix: [String] = []
        if let sourceName { prefix.append(sourceName) }
        if let line { prefix.append("Zeile \(line)") }
        if let column {
            prefix.append("Position \(column)")
        } else if let range {
            prefix.append("Position \(range.start + 1)")
        }
        var text = message
        if !prefix.isEmpty {
            text = prefix.joined(separator: ", ") + ": " + text
        }
        if let hint {
            text += " " + hint
        }
        return text
    }
}

/// A non-fatal remark of the parser, e.g. an ambiguous run of letters that was read in one of
/// several possible ways. Warnings are shown in the editor – nothing is guessed silently.
struct FormulaWarning: Equatable, Sendable {
    var message: String
    var range: SourceRange?
    var line: Int?
}
