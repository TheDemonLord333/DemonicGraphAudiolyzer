import Foundation

typealias FormulaEvaluator = @Sendable (UnsafeMutablePointer<Double>) -> Double

/// A formula compiled into an immutable closure tree.
///
/// Evaluation reads input variables from an environment buffer (`FormulaVariable.slot`),
/// keeps an iteration budget in `budgetSlot` and stores loop variables, helper-function
/// parameters and bound definitions after `localBase`. Sub-expressions that do not depend on
/// inputs are folded to constants at compile time; `fixed` variables (e.g. a, b, c in the
/// classic modes, bpm or nyquist in the synthesizer) count as constants.
struct CompiledProgram: Sendable {
    static let inputCount = FormulaVariable.allCases.count
    static let budgetSlot = inputCount
    static let localBase = inputCount + 1

    let node: FormulaNode
    /// Number of environment slots needed.
    let slotCount: Int
    /// Constant result if the program does not depend on any non-fixed input.
    let constant: Double?
    /// Input variables read at run time (fixed ones excluded).
    let inputs: Set<FormulaVariable>
    private let evaluator: FormulaEvaluator

    init(_ node: FormulaNode, fixed: [FormulaVariable: Double] = [:]) {
        self.node = node
        self.slotCount = Self.localBase + node.localCount
        self.inputs = node.usedVariables.subtracting(fixed.keys)
        let scratch = UnsafeMutablePointer<Double>.allocate(capacity: slotCount)
        scratch.initialize(repeating: 0, count: slotCount)
        defer {
            scratch.deinitialize(count: slotCount)
            scratch.deallocate()
        }
        var compiler = FormulaCompiler(fixed: fixed, scratch: scratch)
        let built = compiler.build(node)
        self.evaluator = built.evaluator
        self.constant = built.constant
    }

    /// Evaluates with an environment whose input slots have been set by the caller.
    @inline(__always)
    func evaluate(_ environment: UnsafeMutablePointer<Double>) -> Double {
        environment[Self.budgetSlot] = Double(FormulaLimits.iterationsPerEvaluation)
        return evaluator(environment)
    }
}

/// Reusable environment buffer for hot loops (one per renderer / thread).
final class EvaluationBuffer {
    let pointer: UnsafeMutablePointer<Double>
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, CompiledProgram.localBase + 1)
        pointer = UnsafeMutablePointer<Double>.allocate(capacity: self.capacity)
        pointer.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        pointer.deinitialize(count: capacity)
        pointer.deallocate()
    }

    subscript(variable: FormulaVariable) -> Double {
        get { pointer[variable.slot] }
        set { pointer[variable.slot] = newValue }
    }

    @inline(__always)
    func evaluate(_ program: CompiledProgram) -> Double {
        precondition(program.slotCount <= capacity, "Evaluation buffer too small")
        return program.evaluate(pointer)
    }
}

private struct FormulaCompiler {
    struct Built {
        var evaluator: FormulaEvaluator
        var constant: Double?
        var freeLocals: Set<Int>
        var usesInputs: Bool
    }

    let fixed: [FormulaVariable: Double]
    let scratch: UnsafeMutablePointer<Double>

    init(fixed: [FormulaVariable: Double], scratch: UnsafeMutablePointer<Double>) {
        self.fixed = fixed
        self.scratch = scratch
    }

    private static func constant(_ value: Double) -> FormulaEvaluator {
        { _ in value }
    }

    /// Folds the node if it depends neither on inputs nor on free locals.
    private func finish(_ evaluator: @escaping FormulaEvaluator, freeLocals: Set<Int>, usesInputs: Bool) -> Built {
        if freeLocals.isEmpty, !usesInputs {
            scratch[CompiledProgram.budgetSlot] = Double(FormulaLimits.iterationsPerEvaluation)
            let value = evaluator(scratch)
            return Built(evaluator: Self.constant(value), constant: value, freeLocals: [], usesInputs: false)
        }
        return Built(evaluator: evaluator, constant: nil, freeLocals: freeLocals, usesInputs: usesInputs)
    }

    /// Builds the closure of a node. A small dispatcher: every case lives in its own function,
    /// so the recursion (one level per tree level) keeps small stack frames even in debug builds
    /// and on threads with 512 KB of stack.
    mutating func build(_ node: FormulaNode) -> Built {
        // The dispatcher binds no payloads: every case is extracted in its own small function.
        switch node {
        case .number, .variable, .local: return buildLeaf(node)
        case .negate, .not: return buildUnary(node)
        case .binary: return buildBinary(node)
        case .call: return buildCall(node)
        case .conditional: return buildConditional(node)
        case .piecewise: return buildPiecewise(node)
        case .aggregate: return buildAggregate(node)
        case .element: return buildElement(node)
        case .binding: return buildBinding(node)
        }
    }

    @inline(never)
    private func buildLeaf(_ node: FormulaNode) -> Built {
        switch node {
        case .number(let value):
            return Built(evaluator: Self.constant(value), constant: value, freeLocals: [], usesInputs: false)
        case .variable(let variable):
            return buildVariable(variable)
        case .local(let local):
            let slot = CompiledProgram.localBase + local
            return Built(evaluator: { env in env[slot] }, constant: nil, freeLocals: [local], usesInputs: false)
        default:
            preconditionFailure("not a leaf")
        }
    }

    @inline(never)
    private mutating func buildUnary(_ node: FormulaNode) -> Built {
        switch node {
        case .negate(let operand): return buildNegate(operand)
        case .not(let operand): return buildNot(operand)
        default: preconditionFailure("not unary")
        }
    }

    @inline(never)
    private func buildVariable(_ variable: FormulaVariable) -> Built {
        if let value = fixed[variable] {
            return Built(evaluator: Self.constant(value), constant: value, freeLocals: [], usesInputs: false)
        }
        let slot = variable.slot
        return Built(evaluator: { env in env[slot] }, constant: nil, freeLocals: [], usesInputs: true)
    }

    @inline(never)
    private mutating func buildNegate(_ operand: FormulaNode) -> Built {
        let inner = build(operand)
        let f = inner.evaluator
        return finish({ env in -f(env) }, freeLocals: inner.freeLocals, usesInputs: inner.usesInputs)
    }

    @inline(never)
    private mutating func buildNot(_ operand: FormulaNode) -> Built {
        let inner = build(operand)
        let f = inner.evaluator
        return finish({ env in MathSemantics.not(f(env)) }, freeLocals: inner.freeLocals, usesInputs: inner.usesInputs)
    }

    @inline(never)
    private mutating func buildBinary(_ node: FormulaNode) -> Built {
        guard case .binary(let op, let lhs, let rhs) = node else { preconditionFailure("not binary") }
        let left = build(lhs)
        let right = build(rhs)
        let evaluator = Self.binary(op, left, right)
        return finish(evaluator, freeLocals: left.freeLocals.union(right.freeLocals), usesInputs: left.usesInputs || right.usesInputs)
    }

    @inline(never)
    private mutating func buildCall(_ node: FormulaNode) -> Built {
        guard case .call(let function, let arguments) = node else { preconditionFailure("not a call") }
        var built: [Built] = []
        built.reserveCapacity(arguments.count)
        for argument in arguments { built.append(build(argument)) }
        let evaluator = Self.call(function, built)
        return finish(evaluator, freeLocals: built.reduce(into: Set<Int>()) { $0.formUnion($1.freeLocals) },
                      usesInputs: built.contains(where: \.usesInputs))
    }

    @inline(never)
    private mutating func buildConditional(_ node: FormulaNode) -> Built {
        guard case .conditional(let condition, let then, let otherwise) = node else { preconditionFailure("not conditional") }
        let c = build(condition)
        let a = build(then)
        let b = build(otherwise)
        if let value = c.constant {
            // Constant condition: only the selected branch remains.
            if value.isNaN { return Built(evaluator: Self.constant(.nan), constant: .nan, freeLocals: [], usesInputs: false) }
            return value != 0 ? a : b
        }
        let cf = c.evaluator, af = a.evaluator, bf = b.evaluator
        return finish({ env in
            let value = cf(env)
            if value.isNaN { return .nan }
            return value != 0 ? af(env) : bf(env)
        }, freeLocals: c.freeLocals.union(a.freeLocals).union(b.freeLocals), usesInputs: c.usesInputs || a.usesInputs || b.usesInputs)
    }

    @inline(never)
    private mutating func buildPiecewise(_ node: FormulaNode) -> Built {
        guard case .piecewise(let parts) = node else { preconditionFailure("not piecewise") }
        var built: [Built] = []
        built.reserveCapacity(parts.count)
        for part in parts { built.append(build(part)) }
        let conditions = stride(from: 0, to: built.count - 1, by: 2).map { built[$0].evaluator }
        let values = stride(from: 1, to: built.count, by: 2).map { built[$0].evaluator }
        let fallback = built[built.count - 1].evaluator
        return finish({ env in
            for index in 0..<conditions.count {
                let condition = conditions[index](env)
                if condition.isNaN { return .nan }
                if condition != 0 { return values[index](env) }
            }
            return fallback(env)
        }, freeLocals: built.reduce(into: Set<Int>()) { $0.formUnion($1.freeLocals) }, usesInputs: built.contains(where: \.usesInputs))
    }

    @inline(never)
    private mutating func buildAggregate(_ node: FormulaNode) -> Built {
        guard case .aggregate(let kind, let local, let start, let end, let body) = node else { preconditionFailure("not aggregate") }
        let s = build(start)
        let e = build(end)
        let b = build(body)
        let sf = s.evaluator, ef = e.evaluator, bf = b.evaluator
        let slot = CompiledProgram.localBase + local
        let budgetSlot = CompiledProgram.budgetSlot
        let isSum = kind == .sum
        var free = b.freeLocals
        free.remove(local)
        return finish({ env in
            let initial: Double = isSum ? 0 : 1
            let range: ClosedRange<Int>
            switch MathSemantics.loopBounds(sf(env), ef(env)) {
            case .undefined: return .nan
            case .empty: return initial
            case .range(let bounds): range = bounds
            }
            var accumulator = initial
            for k in range {
                env[budgetSlot] -= 1
                if env[budgetSlot] < 0 { return .nan }
                env[slot] = Double(k)
                let value = bf(env)
                if isSum { accumulator += value } else { accumulator *= value }
            }
            return accumulator
        }, freeLocals: s.freeLocals.union(e.freeLocals).union(free), usesInputs: s.usesInputs || e.usesInputs || b.usesInputs)
    }

    @inline(never)
    private mutating func buildElement(_ node: FormulaNode) -> Built {
        guard case .element(let elements, let index) = node else { preconditionFailure("not an element") }
        var built: [Built] = []
        built.reserveCapacity(elements.count)
        for element in elements { built.append(build(element)) }
        let i = build(index)
        let evaluators = built.map(\.evaluator)
        let indexEvaluator = i.evaluator
        let count = evaluators.count
        if let constantIndex = i.constant {
            guard let position = MathSemantics.listIndex(constantIndex, count: count) else {
                return Built(evaluator: Self.constant(.nan), constant: .nan, freeLocals: [], usesInputs: false)
            }
            return built[position]
        }
        let values = built.compactMap(\.constant)
        if values.count == count {
            // A list of numbers: plain array lookup.
            return finish({ env in
                guard let position = MathSemantics.listIndex(indexEvaluator(env), count: count) else { return .nan }
                return values[position]
            }, freeLocals: i.freeLocals, usesInputs: i.usesInputs)
        }
        return finish({ env in
            guard let position = MathSemantics.listIndex(indexEvaluator(env), count: count) else { return .nan }
            return evaluators[position](env)
        }, freeLocals: built.reduce(into: i.freeLocals) { $0.formUnion($1.freeLocals) },
           usesInputs: i.usesInputs || built.contains(where: \.usesInputs))
    }

    @inline(never)
    private mutating func buildBinding(_ node: FormulaNode) -> Built {
        guard case .binding(let local, let value, let body) = node else { preconditionFailure("not a binding") }
        let v = build(value)
        let b = build(body)
        let vf = v.evaluator, bf = b.evaluator
        let slot = CompiledProgram.localBase + local
        var free = b.freeLocals
        free.remove(local)
        return finish({ env in
            env[slot] = vf(env)
            return bf(env)
        }, freeLocals: v.freeLocals.union(free), usesInputs: v.usesInputs || b.usesInputs)
    }

    private static func binary(_ op: BinaryOperator, _ left: Built, _ right: Built) -> FormulaEvaluator {
        let l = left.evaluator
        let r = right.evaluator
        switch op {
        case .add:
            if let c = right.constant { return { env in l(env) + c } }
            if let c = left.constant { return { env in c + r(env) } }
            return { env in l(env) + r(env) }
        case .subtract:
            if let c = right.constant { return { env in l(env) - c } }
            if let c = left.constant { return { env in c - r(env) } }
            return { env in l(env) - r(env) }
        case .multiply:
            if let c = right.constant { return { env in l(env) * c } }
            if let c = left.constant { return { env in c * r(env) } }
            return { env in l(env) * r(env) }
        case .divide:
            if let c = right.constant { return { env in l(env) / c } }
            return { env in l(env) / r(env) }
        case .power:
            if let c = right.constant {
                if c == 2 { return { env in let v = l(env); return v * v } }
                return { env in MathSemantics.power(l(env), c) }
            }
            return { env in MathSemantics.power(l(env), r(env)) }
        case .less: return { env in MathSemantics.compare(l(env), r(env)) { $0 < $1 } }
        case .lessEqual: return { env in MathSemantics.compare(l(env), r(env)) { $0 <= $1 } }
        case .greater: return { env in MathSemantics.compare(l(env), r(env)) { $0 > $1 } }
        case .greaterEqual: return { env in MathSemantics.compare(l(env), r(env)) { $0 >= $1 } }
        case .equal: return { env in MathSemantics.compare(l(env), r(env)) { $0 == $1 } }
        case .notEqual: return { env in MathSemantics.compare(l(env), r(env)) { $0 != $1 } }
        case .and:
            return { env in
                let a = l(env)
                if a.isNaN { return .nan }
                if a == 0 { return 0 }
                return MathSemantics.truth(r(env))
            }
        case .or:
            return { env in
                let a = l(env)
                if a.isNaN { return .nan }
                if a != 0 { return 1 }
                return MathSemantics.truth(r(env))
            }
        }
    }

    private static func call(_ function: MathFunction, _ arguments: [Built]) -> FormulaEvaluator {
        let f = arguments[0].evaluator
        switch function {
        case .sin: return { env in Foundation.sin(f(env)) }
        case .cos: return { env in Foundation.cos(f(env)) }
        case .tan: return { env in Foundation.tan(f(env)) }
        case .atan: return { env in Foundation.atan(f(env)) }
        case .abs: return { env in Swift.abs(f(env)) }
        case .exp: return { env in Foundation.exp(f(env)) }
        case .floor: return { env in Foundation.floor(f(env)) }
        case .ceil: return { env in Foundation.ceil(f(env)) }
        case .round: return { env in Foundation.round(f(env)) }
        case .frac: return { env in MathSemantics.frac(f(env)) }
        case .sign: return { env in MathSemantics.sign(f(env)) }
        case .asin, .acos, .sqrt, .ln, .log10:
            return { env in MathSemantics.apply(function, [f(env)]) }
        case .mod:
            let g = arguments[1].evaluator
            if let divisor = arguments[1].constant { return { env in MathSemantics.modulo(f(env), divisor) } }
            return { env in MathSemantics.modulo(f(env), g(env)) }
        case .clip:
            let low = arguments[1].evaluator
            let high = arguments[2].evaluator
            return { env in MathSemantics.clip(f(env), low(env), high(env)) }
        case .min, .max:
            let all = arguments.map(\.evaluator)
            let isMinimum = function == .min
            if all.count == 2 {
                let g = all[1]
                return { env in
                    let a = f(env), b = g(env)
                    if a.isNaN || b.isNaN { return .nan }
                    return isMinimum ? Swift.min(a, b) : Swift.max(a, b)
                }
            }
            return { env in
                var result = isMinimum ? Double.infinity : -Double.infinity
                for evaluator in all {
                    let value = evaluator(env)
                    if value.isNaN { return .nan }
                    result = isMinimum ? Swift.min(result, value) : Swift.max(result, value)
                }
                return result
            }
        }
    }
}
