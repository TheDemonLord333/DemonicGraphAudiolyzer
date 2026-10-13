import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Formel-Parser")
struct FormulaParserTests {
    private func parse(_ text: String) throws -> ParsedFormula {
        switch ParsedFormula.parse(text) {
        case .success(let formula): return formula
        case .failure(let error): throw error
        }
    }

    private func value(_ text: String, x: Double = 0, parameters: FormulaParameters = FormulaParameters()) throws -> Double {
        try parse(text).root.evaluate(x: x, parameters: parameters)
    }

    private func error(_ text: String) -> FormulaError? {
        if case .failure(let error) = ParsedFormula.parse(text) { return error }
        return nil
    }

    @Test("Definitionspräfixe y = und f(x) = werden akzeptiert")
    func definitionPrefixes() throws {
        let plain = try parse("sin(x)").root
        #expect(try parse("y = sin(x)").root == plain)
        #expect(try parse("f(x) = sin(x)").root == plain)
        #expect(try parse("  Y=SIN(X) ").root == plain)
    }

    @Test("Rangfolge: -x^2 = -(x^2) und 2^3^2 = 2^(3^2)")
    func precedence() throws {
        #expect(try parse("-x^2").root.canonicalDescription == "(-(x^2))")
        #expect(try value("-x^2", x: 3) == -9)
        #expect(try parse("2^3^2").root.canonicalDescription == "(2^(3^2))")
        #expect(try value("2^3^2") == 512)
        #expect(try value("2^-1") == 0.5)
        #expect(try value("1+2*3") == 7)
        #expect(try value("(1+2)*3") == 9)
        #expect(try value("10-4-3") == 3)
        #expect(try value("16/4/2") == 2)
        #expect(try value("-2^2") == -4)
        #expect(try value("--3") == 3)
    }

    @Test("Implizite Multiplikation")
    func implicitMultiplication() throws {
        #expect(try value("2x", x: 3) == 6)
        #expect(try value("2sin(x)", x: Double.pi / 2) == 2)
        #expect(try value("2(x+1)", x: 1) == 4)
        #expect(try value("(x+1)(x-1)", x: 3) == 8)
        #expect(try value("2x^2", x: 3) == 18)
        #expect(abs(try value("2pi") - 2 * Double.pi) < 1e-12)
        #expect(try value("bx", x: 4, parameters: FormulaParameters(a: 1, b: 0.5, c: 0)) == 2)
        #expect(try value("0.5sin(2x)", x: Double.pi / 4) == 0.5)
        #expect(try value("sin(x)cos(3x)", x: 0) == 0)
    }

    @Test("Konstanten und Parameter")
    func constantsAndParameters() throws {
        #expect(try value("pi") == Double.pi)
        #expect(try value("π") == Double.pi)
        #expect(try value("e") == M_E)
        let parameters = FormulaParameters(a: 2, b: 3, c: 4)
        #expect(try value("a*x+b*c", x: 5, parameters: parameters) == 22)
        #expect(try parse("a*x+c").usedParameters == [.a, .c])
        #expect(try parse("asin(bx)+c").usedParameters == [.b, .c])
    }

    @Test("Alle Funktionen")
    func functions() throws {
        let tolerance = 1e-12
        #expect(abs(try value("sin(pi/2)") - 1) < tolerance)
        #expect(abs(try value("cos(pi)") + 1) < tolerance)
        #expect(abs(try value("tan(pi/4)") - 1) < tolerance)
        #expect(abs(try value("asin(1)") - Double.pi / 2) < tolerance)
        #expect(abs(try value("acos(1)")) < tolerance)
        #expect(abs(try value("atan(1)") - Double.pi / 4) < tolerance)
        #expect(try value("abs(-3)") == 3)
        #expect(try value("sqrt(16)") == 4)
        #expect(abs(try value("ln(e)") - 1) < tolerance)
        #expect(try value("log10(1000)") == 3)
        #expect(abs(try value("exp(1)") - M_E) < tolerance)
        #expect(try value("floor(-1.5)") == -2)
        #expect(try value("ceil(-1.5)") == -1)
        #expect(try value("round(2.5)") == 3)
        #expect(try value("round(-2.5)") == -3)
        #expect(try value("min(2, 3)") == 2)
        #expect(try value("max(2; 3)") == 3)
    }

    @Test("mod(a,b) = a - b*floor(a/b) für b > 0, sonst undefiniert")
    func modulo() throws {
        #expect(try value("mod(7, 3)") == 1)
        #expect(try value("mod(-7, 3)") == 2)
        #expect(abs(try value("mod(5.5, 2)") - 1.5) < 1e-12)
        #expect(try value("mod(x, 2)", x: -0.5) == 1.5)
        #expect(try value("mod(7, 0)").isNaN)
        #expect(try value("mod(7, -3)").isNaN)
    }

    @Test("Definitionslücken liefern NaN/unendlich statt Absturz")
    func undefinedValues() throws {
        #expect(try value("sqrt(-1)").isNaN)
        #expect(try value("ln(0)").isNaN)
        #expect(try value("ln(-1)").isNaN)
        #expect(try value("log10(-5)").isNaN)
        #expect(try value("asin(2)").isNaN)
        #expect(try value("acos(-1.5)").isNaN)
        #expect(try value("1/x", x: 0).isInfinite)
        #expect(try value("0/0").isNaN)
        let compiled = try parse("1/x").compiled(parameters: FormulaParameters())
        #expect(compiled(0).isNaN, "CompiledFormula maps non-finite results to NaN")
    }

    @Test("Kompilierte Auswertung entspricht dem Interpreter")
    func compiledMatchesInterpreter() throws {
        let formulas = ["sin(x) + 0.5sin(2x)", "floor(x)", "sin(4*x)exp(-0.2abs(x))", "abs(sin(3*x))",
                        "sin(x)cos(3x)", "asin(bx)+c", "mod(x, 1.5) - x^2/7", "min(x, 2) + max(-x, 1)", "2^x/(1+x^2)"]
        let parameters = FormulaParameters(a: 1.5, b: 0.1, c: -0.3)
        for text in formulas {
            let formula = try parse(text)
            let compiled = formula.compiled(parameters: parameters)
            for step in -40...40 {
                let x = Double(step) * 0.37
                let interpreted = formula.root.evaluate(x: x, parameters: parameters)
                let fast = compiled.raw(x)
                if interpreted.isNaN {
                    #expect(fast.isNaN, "\(text) at \(x)")
                } else {
                    #expect(abs(interpreted - fast) <= 1e-12 * max(1, abs(interpreted)), "\(text) at \(x)")
                }
            }
        }
    }

    @Test("Syntaxfehler mit Position")
    func syntaxErrors() {
        #expect(error("")?.kind == .empty)
        #expect(error("y = ")?.kind == .empty)
        #expect(error("sin(x")?.kind == .missingClosingParenthesis)
        #expect(error("sin(x")?.range?.start == 3)
        #expect(error("x)")?.kind == .unexpectedClosingParenthesis)
        #expect(error("x)")?.range?.start == 1)
        #expect(error("2+")?.kind == .missingOperand)
        #expect(error("2+*3")?.kind == .missingOperand)
        #expect(error("2+*3")?.range?.start == 2)
        #expect(error("sinx")?.kind == .functionNeedsParenthesis)
        #expect(error("foo(x)")?.kind == .unknownName)
        #expect(error("log(x)")?.kind == .unknownName)
        #expect(error("x $ 2")?.kind == .unexpectedCharacter)
        #expect(error("x $ 2")?.range?.start == 2)
        #expect(error("min(x)")?.kind == .wrongArgumentCount)
        #expect(error("sin(x, 2)")?.kind == .wrongArgumentCount)
        #expect(error("2 3")?.kind == .missingOperator)
        #expect(error("0,5x")?.kind == .invalidNumber)
        #expect(error("1.2.3")?.kind == .invalidNumber)
        #expect(error("x = 2")?.kind == .misplacedEquals)
        #expect(error("y + 2")?.kind == .unknownName)
        #expect(error(String(repeating: "(", count: 100) + "x" + String(repeating: ")", count: 100))?.kind == .nestingTooDeep)
        #expect(error(String(repeating: "x+", count: 300) + "x")?.kind == .tooLong)
    }

    @Test("Fehlermeldungen sind deutsch und nennen die Position")
    func errorSummary() {
        let summary = error("sin(x")?.localizedSummary ?? ""
        #expect(summary.contains("Position 4"))
        #expect(summary.contains("Klammer"))
    }

    @Test("Mitgelieferte Presets sind gültig")
    func builtInPresetsParse() throws {
        for preset in BuiltInPresets.all {
            let formula = try parse(preset.formula)
            #expect(formula.usesX, "\(preset.name)")
            #expect(preset.settings.validationIssue == nil, "\(preset.name)")
        }
    }
}
