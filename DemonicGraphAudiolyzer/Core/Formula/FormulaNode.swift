import Foundation

/// Strict built-in functions (all arguments are evaluated). Names, aliases, argument counts
/// and help texts live in `FormulaCatalog`; trigonometric functions use radians.
enum MathFunction: String, CaseIterable, Sendable {
    case sin, cos, tan, asin, acos, atan
    case abs, sqrt, ln, log10, exp
    case floor, ceil, round, frac, sign
    case min, max, mod, clip

    var spec: FunctionSpec { FormulaCatalog.function(named: rawValue)! }

    /// Text inserted by the math keyboard.
    var template: String { spec.template }
}

enum AggregateKind: String, Sendable {
    case sum, prod
}

/// Resource limits of the evaluation (documented in the guide and README).
enum FormulaLimits {
    /// Iterations of one sum/prod.
    static let iterationsPerLoop = 10_000
    /// All loop iterations of one evaluation together (nested loops multiply).
    static let iterationsPerEvaluation = 200_000
    /// Nodes of the evaluable tree after inlining helper functions.
    static let maximumNodes = 20_000
}

/// Evaluable tree of a formula: names are resolved, helper functions inlined, definitions
/// bound to local slots. Produced by `FormulaBinder`.
indirect enum FormulaNode: Equatable, Sendable {
    case number(Double)
    case variable(FormulaVariable)
    /// Local slot: loop variable, helper function parameter or bound definition.
    case local(Int)
    case negate(FormulaNode)
    case not(FormulaNode)
    case binary(BinaryOperator, FormulaNode, FormulaNode)
    case call(MathFunction, [FormulaNode])
    /// if(condition, then, else) – only the selected branch is evaluated.
    case conditional(FormulaNode, FormulaNode, FormulaNode)
    /// piecewise(c1, e1, c2, e2, …, default) – first true condition wins.
    case piecewise([FormulaNode])
    case aggregate(AggregateKind, local: Int, start: FormulaNode, end: FormulaNode, body: FormulaNode)
    /// list[index] (zero-based); only the selected element is evaluated.
    case element([FormulaNode], index: FormulaNode)
    /// Evaluates `value` once into a local slot, then `body`.
    case binding(local: Int, value: FormulaNode, body: FormulaNode)

    // MARK: Reference interpreter

    /// Evaluates the tree for the classic modes. Undefined results are NaN or ±infinity.
    func evaluate(x: Double, parameters: FormulaParameters) -> Double {
        var inputs = [Double](repeating: 0, count: FormulaVariable.allCases.count)
        inputs[FormulaVariable.x.slot] = x
        inputs[FormulaVariable.a.slot] = parameters.a
        inputs[FormulaVariable.b.slot] = parameters.b
        inputs[FormulaVariable.c.slot] = parameters.c
        return evaluate(inputs: inputs)
    }

    /// Evaluates with all input variables given by slot (`FormulaVariable.slot`).
    func evaluate(inputs: [Double]) -> Double {
        var state = InterpreterState(inputs: inputs, locals: [Double](repeating: 0, count: localCount),
                                     budget: FormulaLimits.iterationsPerEvaluation)
        return interpret(&state)
    }

    private func interpret(_ state: inout InterpreterState) -> Double {
        switch self {
        case .number(let value):
            return value
        case .variable(let variable):
            return state.inputs[variable.slot]
        case .local(let slot):
            return state.locals[slot]
        case .negate(let operand):
            return -operand.interpret(&state)
        case .not(let operand):
            return MathSemantics.not(operand.interpret(&state))
        case .binary(.and, let lhs, let rhs):
            let left = lhs.interpret(&state)
            if left.isNaN { return .nan }
            if left == 0 { return 0 }
            return MathSemantics.truth(rhs.interpret(&state))
        case .binary(.or, let lhs, let rhs):
            let left = lhs.interpret(&state)
            if left.isNaN { return .nan }
            if left != 0 { return 1 }
            return MathSemantics.truth(rhs.interpret(&state))
        case .binary(let op, let lhs, let rhs):
            return MathSemantics.apply(op, lhs.interpret(&state), rhs.interpret(&state))
        case .call(let function, let arguments):
            return MathSemantics.apply(function, arguments.map { $0.interpret(&state) })
        case .conditional(let condition, let then, let otherwise):
            let c = condition.interpret(&state)
            if c.isNaN { return .nan }
            return c != 0 ? then.interpret(&state) : otherwise.interpret(&state)
        case .piecewise(let parts):
            var position = 0
            while position + 1 < parts.count {
                let c = parts[position].interpret(&state)
                if c.isNaN { return .nan }
                if c != 0 { return parts[position + 1].interpret(&state) }
                position += 2
            }
            return parts[parts.count - 1].interpret(&state)
        case .aggregate(let kind, let slot, let start, let end, let body):
            let accumulatorStart: Double = kind == .sum ? 0 : 1
            let range: ClosedRange<Int>
            switch MathSemantics.loopBounds(start.interpret(&state), end.interpret(&state)) {
            case .undefined: return .nan
            case .empty: return accumulatorStart
            case .range(let bounds): range = bounds
            }
            var accumulator = accumulatorStart
            for k in range {
                state.budget -= 1
                if state.budget < 0 { return .nan }
                state.locals[slot] = Double(k)
                let value = body.interpret(&state)
                if kind == .sum { accumulator += value } else { accumulator *= value }
            }
            return accumulator
        case .element(let elements, let index):
            guard let position = MathSemantics.listIndex(index.interpret(&state), count: elements.count) else { return .nan }
            return elements[position].interpret(&state)
        case .binding(let slot, let value, let body):
            state.locals[slot] = value.interpret(&state)
            return body.interpret(&state)
        }
    }

    // MARK: Inspection

    /// Number of local slots used (highest slot + 1).
    var localCount: Int {
        var highest = -1
        visit { node in
            switch node {
            case .local(let slot), .aggregate(_, let slot, _, _, _), .binding(let slot, _, _):
                highest = Swift.max(highest, slot)
            default: break
            }
        }
        return highest + 1
    }

    var nodeCount: Int {
        var count = 0
        visit { _ in count += 1 }
        return count
    }

    /// Input variables the tree reads.
    var usedVariables: Set<FormulaVariable> {
        var result = Set<FormulaVariable>()
        visit { node in
            if case .variable(let variable) = node { result.insert(variable) }
        }
        return result
    }

    var containsX: Bool { usedVariables.contains(.x) }

    var usedParameters: Set<FormulaVariable> {
        usedVariables.filter(\.isLegacyParameter)
    }

    /// Locals read but not bound inside this tree.
    var freeLocals: Set<Int> {
        switch self {
        case .number, .variable: return []
        case .local(let slot): return [slot]
        case .negate(let operand), .not(let operand): return operand.freeLocals
        case .binary(_, let lhs, let rhs): return lhs.freeLocals.union(rhs.freeLocals)
        case .call(_, let arguments), .piecewise(let arguments):
            return arguments.reduce(into: Set<Int>()) { $0.formUnion($1.freeLocals) }
        case .conditional(let c, let a, let b): return c.freeLocals.union(a.freeLocals).union(b.freeLocals)
        case .aggregate(_, let slot, let start, let end, let body):
            var inner = body.freeLocals
            inner.remove(slot)
            return start.freeLocals.union(end.freeLocals).union(inner)
        case .element(let elements, let index):
            return elements.reduce(into: index.freeLocals) { $0.formUnion($1.freeLocals) }
        case .binding(let slot, let value, let body):
            var inner = body.freeLocals
            inner.remove(slot)
            return value.freeLocals.union(inner)
        }
    }

    /// Pre-order traversal.
    func visit(_ body: (FormulaNode) -> Void) {
        body(self)
        switch self {
        case .number, .variable, .local: break
        case .negate(let operand), .not(let operand): operand.visit(body)
        case .binary(_, let lhs, let rhs):
            lhs.visit(body)
            rhs.visit(body)
        case .call(_, let arguments), .piecewise(let arguments):
            for argument in arguments { argument.visit(body) }
        case .conditional(let c, let a, let b):
            c.visit(body)
            a.visit(body)
            b.visit(body)
        case .aggregate(_, _, let start, let end, let loopBody):
            start.visit(body)
            end.visit(body)
            loopBody.visit(body)
        case .element(let elements, let index):
            index.visit(body)
            for element in elements { element.visit(body) }
        case .binding(_, let value, let inner):
            value.visit(body)
            inner.visit(body)
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
        case .local(let slot):
            return "$\(slot)"
        case .negate(let operand):
            return "(-\(operand.canonicalDescription))"
        case .not(let operand):
            return "(not \(operand.canonicalDescription))"
        case .binary(let op, let lhs, let rhs):
            let separator = (op == .and || op == .or) ? " \(op.rawValue) " : op.rawValue
            return "(\(lhs.canonicalDescription)\(separator)\(rhs.canonicalDescription))"
        case .call(let function, let arguments):
            return "\(function.rawValue)(\(arguments.map(\.canonicalDescription).joined(separator: ",")))"
        case .conditional(let c, let a, let b):
            return "if(\(c.canonicalDescription),\(a.canonicalDescription),\(b.canonicalDescription))"
        case .piecewise(let parts):
            return "piecewise(\(parts.map(\.canonicalDescription).joined(separator: ",")))"
        case .aggregate(let kind, let slot, let start, let end, let body):
            return "\(kind.rawValue)($\(slot),\(start.canonicalDescription),\(end.canonicalDescription),\(body.canonicalDescription))"
        case .element(let elements, let index):
            return "[\(elements.map(\.canonicalDescription).joined(separator: ","))][\(index.canonicalDescription)]"
        case .binding(let slot, let value, let body):
            return "($\(slot)=\(value.canonicalDescription);\(body.canonicalDescription))"
        }
    }
}

private struct InterpreterState {
    var inputs: [Double]
    var locals: [Double]
    var budget: Int
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
        case .less: return compare(lhs, rhs) { $0 < $1 }
        case .lessEqual: return compare(lhs, rhs) { $0 <= $1 }
        case .greater: return compare(lhs, rhs) { $0 > $1 }
        case .greaterEqual: return compare(lhs, rhs) { $0 >= $1 }
        case .equal: return compare(lhs, rhs) { $0 == $1 }
        case .notEqual: return compare(lhs, rhs) { $0 != $1 }
        case .and:
            if lhs.isNaN || rhs.isNaN { return .nan }
            return (lhs != 0 && rhs != 0) ? 1 : 0
        case .or:
            if lhs.isNaN || rhs.isNaN { return .nan }
            return (lhs != 0 || rhs != 0) ? 1 : 0
        }
    }

    /// Comparisons yield 1 (true) or 0 (false); an undefined operand gives an undefined result.
    @inline(__always)
    static func compare(_ lhs: Double, _ rhs: Double, _ predicate: (Double, Double) -> Bool) -> Double {
        if lhs.isNaN || rhs.isNaN { return .nan }
        return predicate(lhs, rhs) ? 1 : 0
    }

    @inline(__always)
    static func truth(_ value: Double) -> Double {
        if value.isNaN { return .nan }
        return value != 0 ? 1 : 0
    }

    @inline(__always)
    static func not(_ value: Double) -> Double {
        if value.isNaN { return .nan }
        return value == 0 ? 1 : 0
    }

    /// Powers. A negative base with an (almost) integer exponent is evaluated with the exact
    /// integer exponent, so (-1)^floor(…) is numerically stable; other negative bases with
    /// fractional exponents are undefined.
    static func power(_ base: Double, _ exponent: Double) -> Double {
        if base < 0, exponent.isFinite {
            let rounded = exponent.rounded()
            if Swift.abs(exponent - rounded) <= 1e-9 * Swift.max(1, Swift.abs(exponent)) {
                if base == -1 {
                    // Parity; every double above 2^53 is even.
                    if Swift.abs(rounded) >= 9_007_199_254_740_992 { return 1 }
                    return Int64(rounded) % 2 == 0 ? 1 : -1
                }
                return Foundation.pow(base, rounded)
            }
        }
        return Foundation.pow(base, exponent)
    }

    static func apply(_ function: MathFunction, _ arguments: [Double]) -> Double {
        let first = arguments.first ?? .nan
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
        case .frac: return frac(first)
        case .sign: return sign(first)
        case .min:
            if arguments.contains(where: \.isNaN) { return .nan }
            return arguments.min() ?? .nan
        case .max:
            if arguments.contains(where: \.isNaN) { return .nan }
            return arguments.max() ?? .nan
        case .mod:
            return modulo(first, arguments.count > 1 ? arguments[1] : .nan)
        case .clip:
            guard arguments.count == 3 else { return .nan }
            return clip(first, arguments[1], arguments[2])
        }
    }

    /// mod(a, b) = a − b·floor(a / b), defined only for finite a and finite b > 0.
    /// For b ≤ 0 the function is undefined (NaN → gap in the graph, muted sound).
    @inline(__always)
    static func modulo(_ a: Double, _ b: Double) -> Double {
        guard a.isFinite, b.isFinite, b > 0 else { return .nan }
        let result = a - b * Foundation.floor(a / b)
        // Guard against floating point results like 2.0000000000000004 for b = 2.
        if result >= b || result < 0 { return 0 }
        return result
    }

    /// frac(x) = x − floor(x), always in [0, 1).
    @inline(__always)
    static func frac(_ value: Double) -> Double {
        guard value.isFinite else { return .nan }
        let result = value - Foundation.floor(value)
        return result >= 1 ? 0 : result
    }

    @inline(__always)
    static func sign(_ value: Double) -> Double {
        if value.isNaN { return .nan }
        return value > 0 ? 1 : (value < 0 ? -1 : 0)
    }

    /// clip(v, lo, hi); undefined if a value is undefined or lo > hi.
    @inline(__always)
    static func clip(_ value: Double, _ low: Double, _ high: Double) -> Double {
        if value.isNaN || low.isNaN || high.isNaN || low > high { return .nan }
        return Swift.min(Swift.max(value, low), high)
    }

    enum LoopBounds: Equatable {
        /// Non-integer or non-finite bound, or more iterations than allowed.
        case undefined
        /// end < start: the empty sum is 0, the empty product 1.
        case empty
        case range(ClosedRange<Int>)
    }

    /// Inclusive integer loop range of sum/prod. Bounds must be (almost) integers.
    static func loopBounds(_ start: Double, _ end: Double) -> LoopBounds {
        guard let first = integer(start), let last = integer(end) else { return .undefined }
        if last < first { return .empty }
        if last - first + 1 > FormulaLimits.iterationsPerLoop { return .undefined }
        return .range(first...last)
    }

    /// Zero-based list index; nil if not an integer or out of range.
    @inline(__always)
    static func listIndex(_ value: Double, count: Int) -> Int? {
        guard let index = integer(value), index >= 0, index < count else { return nil }
        return index
    }

    @inline(__always)
    static func integer(_ value: Double) -> Int? {
        guard value.isFinite, Swift.abs(value) < 1e12 else { return nil }
        let rounded = value.rounded()
        guard Swift.abs(value - rounded) <= 1e-9 * Swift.max(1, Swift.abs(value)) else { return nil }
        return Int(rounded)
    }
}
