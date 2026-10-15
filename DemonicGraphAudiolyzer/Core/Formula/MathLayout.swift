import Foundation

/// Typographic role of a text piece in the readable notation.
enum MathTextStyle: Equatable, Sendable {
    case number
    /// Single-letter variable (italic).
    case variable
    /// Multi-letter name or function name (upright).
    case name
    case operatorSymbol
    case punctuation
}

/// One row of a case distinction: value and condition (nil = "sonst").
struct MathCase: Equatable, Sendable {
    var value: MathBox
    var condition: MathBox?
}

/// Layout tree of the readable mathematical notation (fractions, powers, Σ/Π, cases …).
/// Platform independent; the SwiftUI view `MathFormulaView` renders it.
indirect enum MathBox: Equatable, Sendable {
    case text(String, MathTextStyle)
    case row([MathBox])
    case fraction(MathBox, MathBox)
    case power(MathBox, MathBox)
    case radical(MathBox)
    case delimited(String, MathBox, String)
    case bigOperator(symbol: String, lower: MathBox, upper: MathBox, body: MathBox)
    case cases([MathCase])

    /// Plain text rendering (accessibility, tests).
    var plainText: String {
        switch self {
        case .text(let text, _): return text
        case .row(let items): return items.map(\.plainText).joined()
        case .fraction(let numerator, let denominator): return "(\(numerator.plainText))/(\(denominator.plainText))"
        case .power(let base, let exponent): return "\(base.plainText)^(\(exponent.plainText))"
        case .radical(let inner): return "√(\(inner.plainText))"
        case .delimited(let open, let inner, let close): return open + inner.plainText + close
        case .bigOperator(let symbol, let lower, let upper, let body):
            return "\(symbol)[\(lower.plainText)…\(upper.plainText)](\(body.plainText))"
        case .cases(let rows):
            return "{ " + rows.map { row in
                if let condition = row.condition { return "\(row.value.plainText) falls \(condition.plainText)" }
                return "\(row.value.plainText) sonst"
            }.joined(separator: "; ") + " }"
        }
    }

    /// Spoken description for VoiceOver.
    var spokenText: String {
        switch self {
        case .text(let text, _):
            switch text {
            case "·": return " mal "
            case "−": return " minus "
            case "+": return " plus "
            case "=": return " gleich "
            case "≤": return " kleiner gleich "
            case "≥": return " größer gleich "
            case "<": return " kleiner als "
            case ">": return " größer als "
            case "≠": return " ungleich "
            default: return text
            }
        case .row(let items): return items.map(\.spokenText).joined()
        case .fraction(let numerator, let denominator): return "Bruch: \(numerator.spokenText) geteilt durch \(denominator.spokenText), Ende Bruch"
        case .power(let base, let exponent): return "\(base.spokenText) hoch \(exponent.spokenText)"
        case .radical(let inner): return "Wurzel aus \(inner.spokenText)"
        case .delimited(let open, let inner, _):
            switch open {
            case "|": return "Betrag von \(inner.spokenText)"
            case "⌊": return "abgerundet \(inner.spokenText)"
            case "⌈": return "aufgerundet \(inner.spokenText)"
            default: return "Klammer \(inner.spokenText) Klammer zu"
            }
        case .bigOperator(let symbol, let lower, let upper, let body):
            let name = symbol == "Σ" ? "Summe" : "Produkt"
            return "\(name) von \(lower.spokenText) bis \(upper.spokenText) über \(body.spokenText)"
        case .cases(let rows):
            return "Fallunterscheidung: " + rows.map { row in
                if let condition = row.condition { return "\(row.value.spokenText) falls \(condition.spokenText)" }
                return "sonst \(row.value.spokenText)"
            }.joined(separator: "; ")
        }
    }
}

/// One rendered line of a program: left side ("p", "r(x)", "y") and right side.
struct MathLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case definition
        case function
        case output
    }

    var kind: Kind
    var label: MathBox
    var body: MathBox
    var line: Int
}

/// Converts syntax trees into `MathBox` layouts.
enum MathLayout {
    static let greekDisplay: [String: String] = [
        "pi": "π", "tau": "τ", "omega": "ω", "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
        "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ", "phi": "φ", "sigma": "σ", "rho": "ρ",
        "Delta": "Δ", "Omega": "Ω", "Phi": "Φ", "Gamma": "Γ", "Theta": "Θ", "Lambda": "Λ", "Psi": "Ψ"
    ]

    /// Lines of a program, output last.
    static func lines(of program: SyntaxProgram, outputLabel: String = "y") -> [MathLine] {
        var result: [MathLine] = []
        let output = program.outputStatement
        for statement in program.statements {
            let isOutput = statement == output
            switch statement.kind {
            case .value(let name):
                let label = isOutput ? MathBox.text(outputLabel, .variable) : nameBox(name)
                result.append(MathLine(kind: isOutput ? .output : .definition, label: label, body: box(statement.expression), line: statement.line))
            case .function(let name, let parameters):
                let arguments = MathBox.row(parameters.enumerated().flatMap { index, parameter in
                    index == 0 ? [nameBox(parameter)] : [.text(", ", .punctuation), nameBox(parameter)]
                })
                let label = MathBox.row([nameBox(name), .delimited("(", arguments, ")")])
                result.append(MathLine(kind: isOutput ? .output : .function, label: label, body: box(statement.expression), line: statement.line))
            case .output:
                result.append(MathLine(kind: .output, label: .text(outputLabel, .variable), body: box(statement.expression), line: statement.line))
            }
        }
        // Output at the end, definitions in source order.
        return result.filter { $0.kind != .output } + result.filter { $0.kind == .output }
    }

    static func nameBox(_ spelling: String) -> MathBox {
        if let greek = greekDisplay[spelling] { return .text(greek, .variable) }
        if spelling.count == 1 { return .text(spelling, .variable) }
        // Underscore as subscript: N_k → N with subscript k (shown as Nₖ-like row).
        if let underscore = spelling.firstIndex(of: "_"), underscore != spelling.startIndex {
            let base = String(spelling[..<underscore])
            let sub = String(spelling[spelling.index(after: underscore)...])
            return .row([nameBox(base), .text("_" + sub, .name)])
        }
        return .text(spelling, .name)
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let text = String(value)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    private static func stripGroup(_ expression: SyntaxExpression) -> SyntaxExpression {
        if case .group(let inner, _) = expression { return stripGroup(inner) }
        return expression
    }

    private static func isSimpleFactor(_ expression: SyntaxExpression) -> Bool {
        switch expression {
        case .name, .call, .group: return true
        case .binary(.power, let base, _, _, _): return isSimpleFactor(base)
        default: return false
        }
    }

    static func box(_ expression: SyntaxExpression) -> MathBox {
        switch expression {
        case .number(let value, _):
            return .text(number(value), .number)
        case .name(let reference, let spelling, _):
            if case .constant(.pi) = reference { return .text("π", .variable) }
            if case .constant(.e) = reference { return .text("e", .variable) }
            return nameBox(spelling)
        case .negate(let operand, _):
            return .row([.text("−", .operatorSymbol), box(operand)])
        case .not(let operand, _):
            return .row([.text("nicht ", .operatorSymbol), box(operand)])
        case .group(let inner, _):
            return .delimited("(", box(inner), ")")
        case .list(let elements, _):
            return .delimited("[", .row(elements.enumerated().flatMap { index, element in
                index == 0 ? [box(element)] : [.text("; ", .punctuation), box(element)]
            }), "]")
        case .index(let base, let index, _):
            return .row([box(base), .delimited("[", box(index), "]")])
        case .binary(let op, let lhs, let rhs, let implicit, _):
            switch op {
            case .divide:
                return .fraction(box(stripGroup(lhs)), box(stripGroup(rhs)))
            case .power:
                return .power(box(lhs), box(stripGroup(rhs)))
            case .multiply:
                if implicit, case .number = lhs, isSimpleFactor(rhs) {
                    return .row([box(lhs), box(rhs)])
                }
                return .row([box(lhs), .text("·", .operatorSymbol), box(rhs)])
            case .and:
                return .row([box(lhs), .text(" und ", .operatorSymbol), box(rhs)])
            case .or:
                return .row([box(lhs), .text(" oder ", .operatorSymbol), box(rhs)])
            default:
                return .row([box(lhs), .text(" \(op.mathSymbol) ", .operatorSymbol), box(rhs)])
            }
        case .call(let reference, let spelling, let arguments, _):
            return callBox(reference, spelling: spelling, arguments: arguments)
        }
    }

    private static func callBox(_ reference: NameReference, spelling: String, arguments: [SyntaxExpression]) -> MathBox {
        let id: String
        switch reference {
        case .function(let functionID): id = functionID
        default:
            return functionNotation(spelling, arguments)
        }
        switch id {
        case "sqrt":
            return .radical(box(stripGroup(arguments[0])))
        case "abs":
            return .delimited("|", box(stripGroup(arguments[0])), "|")
        case "floor":
            return .delimited("⌊", box(stripGroup(arguments[0])), "⌋")
        case "ceil":
            return .delimited("⌈", box(stripGroup(arguments[0])), "⌉")
        case "exp":
            return .power(.text("e", .variable), box(stripGroup(arguments[0])))
        case "log10":
            return .row([.text("log₁₀", .name), .delimited("(", box(stripGroup(arguments[0])), ")")])
        case "mod":
            return .row([.delimited("(", box(arguments[0]), ""), .text(" mod ", .operatorSymbol), .delimited("", box(arguments[1]), ")")])
        case "sum", "prod":
            let variable = arguments[0]
            let lower = MathBox.row([box(variable), .text("=", .operatorSymbol), box(arguments[1])])
            return .bigOperator(symbol: id == "sum" ? "Σ" : "Π", lower: lower, upper: box(arguments[2]), body: box(arguments[3]))
        case "if":
            return .cases([MathCase(value: box(arguments[1]), condition: box(arguments[0])),
                           MathCase(value: box(arguments[2]), condition: nil)])
        case "piecewise":
            var rows: [MathCase] = []
            var position = 0
            while position + 1 < arguments.count {
                rows.append(MathCase(value: box(arguments[position + 1]), condition: box(arguments[position])))
                position += 2
            }
            rows.append(MathCase(value: box(arguments[arguments.count - 1]), condition: nil))
            return .cases(rows)
        case "len":
            return .delimited("|", box(arguments[0]), "|")
        default:
            let shown: String
            switch id {
            case "asin": shown = spelling.lowercased() == "arcsin" ? "arcsin" : "arcsin"
            case "acos": shown = "arccos"
            case "atan": shown = "arctan"
            case "sign": shown = "sgn"
            default: shown = spelling.lowercased() == "clamp" ? "clamp" : id
            }
            return functionNotation(shown, arguments)
        }
    }

    private static func functionNotation(_ name: String, _ arguments: [SyntaxExpression]) -> MathBox {
        let inner = MathBox.row(arguments.enumerated().flatMap { index, argument in
            index == 0 ? [box(stripGroup(argument))] : [.text("; ", .punctuation), box(stripGroup(argument))]
        })
        return .row([.text(name, .name), .delimited("(", inner, ")")])
    }
}
