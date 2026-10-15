import Foundation

enum BinaryOperator: String, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case power = "^"
    case less = "<"
    case lessEqual = "<="
    case greater = ">"
    case greaterEqual = ">="
    case equal = "=="
    case notEqual = "!="
    case and = "and"
    case or = "or"

    var isComparison: Bool {
        switch self {
        case .less, .lessEqual, .greater, .greaterEqual, .equal, .notEqual: return true
        default: return false
        }
    }

    /// Printed symbol for the readable notation.
    var mathSymbol: String {
        switch self {
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "·"
        case .divide: return "/"
        case .power: return "^"
        case .less: return "<"
        case .lessEqual: return "≤"
        case .greater: return ">"
        case .greaterEqual: return "≥"
        case .equal: return "="
        case .notEqual: return "≠"
        case .and: return "und"
        case .or: return "oder"
        }
    }
}

/// Syntax tree as written by the user (names unresolved to slots, ranges kept).
/// Used for the readable mathematical notation and for the visual editors; the binder turns
/// it into the evaluable `FormulaNode`.
indirect enum SyntaxExpression: Equatable, Sendable {
    case number(Double, SourceRange)
    case name(NameReference, spelling: String, SourceRange)
    case negate(SyntaxExpression, SourceRange)
    case not(SyntaxExpression, SourceRange)
    /// `implicit` marks multiplication without `*` (2x, 2pix).
    case binary(BinaryOperator, SyntaxExpression, SyntaxExpression, implicit: Bool, SourceRange)
    /// Call of a built-in or user function. For sum/prod the first argument is the loop variable
    /// as `.name(.local(…))`. The range covers the name.
    case call(NameReference, spelling: String, arguments: [SyntaxExpression], SourceRange)
    case list([SyntaxExpression], SourceRange)
    case index(SyntaxExpression, SyntaxExpression, SourceRange)
    case group(SyntaxExpression, SourceRange)

    /// Range of the whole expression.
    var range: SourceRange {
        switch self {
        case .number(_, let range), .name(_, _, let range):
            return range
        case .negate(let operand, let range), .not(let operand, let range):
            return range.union(operand.range)
        case .binary(_, let lhs, let rhs, _, _):
            return lhs.range.union(rhs.range)
        case .call(_, _, let arguments, let range):
            return arguments.reduce(range) { $0.union($1.range) }
        case .list(_, let range), .group(_, let range):
            return range
        case .index(let base, _, let range):
            return base.range.union(range)
        }
    }
}

struct SyntaxStatement: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `name = expression` (a list if the expression is a list literal).
        case value(String)
        /// `name(p1, p2) = expression`
        case function(String, parameters: [String])
        /// A line without `=`: the output of the program.
        case output
    }

    var kind: Kind
    var nameRange: SourceRange?
    var expression: SyntaxExpression
    var line: Int

    var definedName: String? {
        switch kind {
        case .value(let name), .function(let name, _): return name
        case .output: return nil
        }
    }

    var isList: Bool {
        if case .value = kind, case .list = expression { return true }
        return false
    }
}

/// A parsed (multi-line) formula: definitions and at most one output line.
struct SyntaxProgram: Equatable, Sendable {
    var statements: [SyntaxStatement]
    var warnings: [FormulaWarning]
    /// Names that were accepted as automatic parameters (simple editor of the synthesizer).
    var autoParameters: [String]
    /// Number of source lines.
    var lineCount: Int

    /// The statement that produces the result: the output line, otherwise `y = …` or `f(x) = …`.
    var outputStatement: SyntaxStatement? {
        if let output = statements.first(where: { $0.kind == .output }) { return output }
        if let y = statements.first(where: { $0.definedName?.lowercased() == "y" && !$0.isList }) {
            if case .value = y.kind { return y }
        }
        return statements.first(where: {
            if case .function(let name, let parameters) = $0.kind { return name.lowercased() == "f" && parameters.count == 1 }
            return false
        })
    }

    var definitions: [SyntaxStatement] {
        statements.filter { $0.kind != .output }
    }
}
