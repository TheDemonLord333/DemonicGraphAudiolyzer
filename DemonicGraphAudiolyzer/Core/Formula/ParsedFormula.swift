import Foundation

/// A successfully parsed formula of the classic modes ("Graph vertonen", "Formel als
/// Klangwelle") together with its source text. The source may be a single line (simple editor)
/// or a multi-line program with definitions (advanced editor).
struct ParsedFormula: Equatable, Sendable {
    let source: String
    let root: FormulaNode
    let program: SyntaxProgram

    var usesX: Bool { root.containsX }
    var usedParameters: Set<FormulaVariable> { root.usedParameters }
    var warnings: [FormulaWarning] { program.warnings }
    var isMultiLine: Bool { program.lineCount > 1 }

    static func == (lhs: ParsedFormula, rhs: ParsedFormula) -> Bool {
        lhs.source == rhs.source && lhs.root == rhs.root
    }

    static func parse(_ source: String) -> Result<ParsedFormula, FormulaError> {
        do {
            let program = try FormulaParser.parseProgram(source, environment: .classic)
            let root = try FormulaBinder.bind(program, environment: .classic).root
            return .success(ParsedFormula(source: source, root: root, program: program))
        } catch let error as FormulaError {
            return .failure(error)
        } catch {
            return .failure(FormulaError(kind: .unexpectedCharacter, message: "Die Formel konnte nicht gelesen werden.", range: nil, hint: nil))
        }
    }

    func compiled(parameters: FormulaParameters) -> CompiledFormula {
        CompiledFormula(formula: self, parameters: parameters)
    }

    /// The output expression as written (without `y =` / `f(x) =`), for display as `f(x) = …`.
    var displayBody: String {
        guard let output = program.outputStatement else {
            return source.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let characters = Array(source)
        let range = output.expression.range
        let start = max(0, min(range.start, characters.count))
        let end = max(start, min(range.end, characters.count))
        let text = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? source : text
    }
}

/// Fast, immutable, thread-safe evaluator for a formula with fixed parameters.
struct CompiledFormula: Sendable {
    let formula: ParsedFormula
    let parameters: FormulaParameters
    private let program: CompiledProgram

    init(formula: ParsedFormula, parameters: FormulaParameters) {
        self.formula = formula
        self.parameters = parameters
        self.program = CompiledProgram(formula.root, fixed: [.a: parameters.a, .b: parameters.b, .c: parameters.c])
    }

    /// f(x); returns NaN for undefined points (non-finite results are mapped to NaN).
    @inline(__always)
    func callAsFunction(_ x: Double) -> Double {
        let value = raw(x)
        return value.isFinite ? value : .nan
    }

    /// Raw result including ±infinity (used where the sign of a pole matters).
    func raw(_ x: Double) -> Double {
        if let constant = program.constant { return constant }
        let count = program.slotCount
        return withUnsafeTemporaryAllocation(of: Double.self, capacity: count) { buffer in
            let environment = buffer.baseAddress!
            environment.initialize(repeating: 0, count: count)
            environment[FormulaVariable.x.slot] = x
            return program.evaluate(environment)
        }
    }
}
