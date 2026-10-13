import Foundation

/// Character range inside the formula source (0-based, end exclusive, counted in `Character`s).
struct SourceRange: Equatable, Hashable, Sendable {
    var start: Int
    var end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = max(end, start + 1)
    }

    var length: Int { end - start }
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
    }

    var kind: Kind
    var message: String
    var range: SourceRange?
    var hint: String?

    /// Single line description used in UI and accessibility.
    var localizedSummary: String {
        var text = message
        if let range {
            text = "Position \(range.start + 1): " + text
        }
        if let hint {
            text += " " + hint
        }
        return text
    }
}
