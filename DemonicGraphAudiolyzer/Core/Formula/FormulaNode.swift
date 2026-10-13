import Foundation

/// Built-in functions. Trigonometric functions use radians.
enum MathFunction: String, CaseIterable, Sendable {
    case sin, cos, tan, asin, acos, atan
    case abs, sqrt, ln, log10, exp
    case floor, ceil, round
    case min, max, mod

    var arity: Int {
        switch self {
        case .min, .max, .mod: return 2
        default: return 1
        }
    }

    /// Text inserted by the math keyboard.
    var template: String {
        arity == 2 ? "\(rawValue)(,)" : "\(rawValue)()"
    }
}

/// Values of the optional formula parameters a, b and c.
struct FormulaParameters: Codable, Equatable, Hashable, Sendable {
    var a: Double = 1
    var b: Double = 1
    var c: Double = 0

    subscript(variable: FormulaVariable) -> Double {
        get {
            switch variable {
            case .a: return a
            case .b: return b
            case .c: return c
            case .x: return .nan
            }
        }
        set {
            switch variable {
            case .a: a = newValue
            case .b: b = newValue
            case .c: c = newValue
            case .x: break
            }
        }
    }
}

enum BinaryOperator: String, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case power = "^"
}

/// Abstract syntax tree of a formula.
indirect enum FormulaNode: Equatable, Sendable {
    case number(Double)
    case variable(FormulaVariable)
    case negate(FormulaNode)
    case binary(BinaryOperator, FormulaNode, FormulaNode)
    case call(MathFunction, [FormulaNode])

    // MARK: Evaluation (reference interpreter)

    /// Evaluates the tree. Undefined results are `NaN` or ±infinity – never a crash.
    func evaluate(x: Double, parameters: FormulaParameters) -> Double {
        switch self {
        case .number(let value):
            return value
        case .variable(let variable):
            return variable == .x ? x : parameters[variable]
        case .negate(let operand):
            return -operand.evaluate(x: x, parameters: parameters)
        case .binary(let op, let lhs, let rhs):
            return MathSemantics.apply(op, lhs.evaluate(x: x, parameters: parameters), rhs.evaluate(x: x, parameters: parameters))
        case .call(let function, let arguments):
            let first = arguments[0].evaluate(x: x, parameters: parameters)
            let second = arguments.count > 1 ? arguments[1].evaluate(x: x, parameters: parameters) : 0
            return MathSemantics.apply(function, first, second)
        }
    }

    // MARK: Compilation

    /// Compiles the tree into a closure chain with parameters and constant
    /// sub-expressions folded in. The result is immutable and thread-safe.
    func compile(parameters: FormulaParameters) -> @Sendable (Double) -> Double {
        if !containsX {
            let constant = evaluate(x: 0, parameters: parameters)
            return { _ in constant }
        }
        switch self {
        case .number(let value):
            return { _ in value }
        case .variable(let variable):
            if variable == .x {
                return { x in x }
            }
            let value = parameters[variable]
            return { _ in value }
        case .negate(let operand):
            let inner = operand.compile(parameters: parameters)
            return { x in -inner(x) }
        case .binary(let op, let lhs, let rhs):
            let left = lhs.compile(parameters: parameters)
            let right = rhs.compile(parameters: parameters)
            switch op {
            case .add: return { x in left(x) + right(x) }
            case .subtract: return { x in left(x) - right(x) }
            case .multiply: return { x in left(x) * right(x) }
            case .divide: return { x in left(x) / right(x) }
            case .power: return { x in MathSemantics.power(left(x), right(x)) }
            }
        case .call(let function, let arguments):
            let first = arguments[0].compile(parameters: parameters)
            if function.arity == 2 {
                let second = arguments[1].compile(parameters: parameters)
                return { x in MathSemantics.apply(function, first(x), second(x)) }
            }
            switch function {
            case .sin: return { x in Foundation.sin(first(x)) }
            case .cos: return { x in Foundation.cos(first(x)) }
            case .abs: return { x in Swift.abs(first(x)) }
            case .exp: return { x in Foundation.exp(first(x)) }
            default: return { x in MathSemantics.apply(function, first(x), 0) }
            }
        }
    }

    // MARK: Inspection

    var containsX: Bool {
        switch self {
        case .number: return false
        case .variable(let variable): return variable == .x
        case .negate(let operand): return operand.containsX
        case .binary(_, let lhs, let rhs): return lhs.containsX || rhs.containsX
        case .call(_, let arguments): return arguments.contains { $0.containsX }
        }
    }

    var usedParameters: Set<FormulaVariable> {
        switch self {
        case .number: return []
        case .variable(let variable): return variable == .x ? [] : [variable]
        case .negate(let operand): return operand.usedParameters
        case .binary(_, let lhs, let rhs): return lhs.usedParameters.union(rhs.usedParameters)
        case .call(_, let arguments): return arguments.reduce(into: Set<FormulaVariable>()) { $0.formUnion($1.usedParameters) }
        }
    }

    /// Fully parenthesised form, used for tests and debugging (e.g. `(-(x^2))`).
    var canonicalDescription: String {
        switch self {
        case .number(let value):
            if value == value.rounded(), Swift.abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        case .variable(let variable):
            return variable.rawValue
        case .negate(let operand):
            return "(-\(operand.canonicalDescription))"
        case .binary(let op, let lhs, let rhs):
            return "(\(lhs.canonicalDescription)\(op.rawValue)\(rhs.canonicalDescription))"
        case .call(let function, let arguments):
            return "\(function.rawValue)(\(arguments.map(\.canonicalDescription).joined(separator: ",")))"
        }
    }
}

/// The numeric semantics of the formula language, shared by interpreter and compiler.
enum MathSemantics {
    static func apply(_ op: BinaryOperator, _ lhs: Double, _ rhs: Double) -> Double {
        switch op {
        case .add: return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide: return lhs / rhs        // ±inf or NaN for division by zero
        case .power: return power(lhs, rhs)
        }
    }

    static func power(_ base: Double, _ exponent: Double) -> Double {
        Foundation.pow(base, exponent)
    }

    static func apply(_ function: MathFunction, _ first: Double, _ second: Double) -> Double {
        switch function {
        case .sin: return Foundation.sin(first)
        case .cos: return Foundation.cos(first)
        case .tan: return Foundation.tan(first)
        case .asin: return (first >= -1 && first <= 1) ? Foundation.asin(first) : .nan
        case .acos: return (first >= -1 && first <= 1) ? Foundation.acos(first) : .nan
        case .atan: return Foundation.atan(first)
        case .abs: return Swift.abs(first)
        case .sqrt: return first >= 0 ? Foundation.sqrt(first) : .nan
        case .ln: return first > 0 ? Foundation.log(first) : .nan
        case .log10: return first > 0 ? Foundation.log10(first) : .nan
        case .exp: return Foundation.exp(first)
        case .floor: return Foundation.floor(first)
        case .ceil: return Foundation.ceil(first)
        case .round: return Foundation.round(first)   // halves away from zero
        case .min:
            if first.isNaN || second.isNaN { return .nan }
            return Swift.min(first, second)
        case .max:
            if first.isNaN || second.isNaN { return .nan }
            return Swift.max(first, second)
        case .mod:
            return modulo(first, second)
        }
    }

    /// mod(a, b) = a − b·floor(a / b), defined only for finite a and finite b > 0.
    /// For b ≤ 0 the function is undefined (NaN → gap in the graph, muted sound).
    static func modulo(_ a: Double, _ b: Double) -> Double {
        guard a.isFinite, b.isFinite, b > 0 else { return .nan }
        let result = a - b * Foundation.floor(a / b)
        // Guard against floating point results like 2.0000000000000004 for b = 2.
        if result >= b || result < 0 { return 0 }
        return result
    }
}
