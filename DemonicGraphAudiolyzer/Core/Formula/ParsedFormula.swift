import Foundation

/// A successfully parsed formula together with its source text.
struct ParsedFormula: Equatable, Sendable {
    let source: String
    let root: FormulaNode

    var usesX: Bool { root.containsX }
    var usedParameters: Set<FormulaVariable> { root.usedParameters }

    static func parse(_ source: String) -> Result<ParsedFormula, FormulaError> {
        do {
            let root = try FormulaParser.parse(source)
            return .success(ParsedFormula(source: source, root: root))
        } catch let error as FormulaError {
            return .failure(error)
        } catch {
            return .failure(FormulaError(kind: .unexpectedCharacter, message: "Die Formel konnte nicht gelesen werden.", range: nil, hint: nil))
        }
    }

    func compiled(parameters: FormulaParameters) -> CompiledFormula {
        CompiledFormula(formula: self, parameters: parameters)
    }

    /// The formula without a `y =` / `f(x) =` prefix, for display as `f(x) = …`.
    var displayBody: String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let equals = trimmed.firstIndex(of: "=") {
            return String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}

/// Fast, immutable, thread-safe evaluator for a formula with fixed parameters.
struct CompiledFormula: Sendable {
    let formula: ParsedFormula
    let parameters: FormulaParameters
    private let function: @Sendable (Double) -> Double

    init(formula: ParsedFormula, parameters: FormulaParameters) {
        self.formula = formula
        self.parameters = parameters
        self.function = formula.root.compile(parameters: parameters)
    }

    /// f(x); returns NaN for undefined points (non-finite results are mapped to NaN).
    @inline(__always)
    func callAsFunction(_ x: Double) -> Double {
        let value = function(x)
        return value.isFinite ? value : .nan
    }

    /// Raw result including ±infinity (used where the sign of a pole matters).
    @inline(__always)
    func raw(_ x: Double) -> Double {
        function(x)
    }
}
