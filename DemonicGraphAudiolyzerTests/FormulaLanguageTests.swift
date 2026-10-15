import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

/// Language version 2: conditions, lazy branches, sums/products, lists, definitions.
@Suite("Formelsprache v2")
struct FormulaLanguageTests {
    private func formula(_ text: String) throws -> ParsedFormula {
        switch ParsedFormula.parse(text) {
        case .success(let formula): return formula
        case .failure(let error): throw error
        }
    }

    private func value(_ text: String, x: Double = 0, parameters: FormulaParameters = FormulaParameters()) throws -> Double {
        let parsed = try formula(text)
        let interpreted = parsed.root.evaluate(x: x, parameters: parameters)
        let compiled = parsed.compiled(parameters: parameters).raw(x)
        if interpreted.isNaN {
            #expect(compiled.isNaN, "\(text): Compiler und Interpreter müssen übereinstimmen")
        } else {
            #expect(abs(interpreted - compiled) <= 1e-12 * max(1, abs(interpreted)), "\(text): \(interpreted) vs \(compiled)")
        }
        return interpreted
    }

    private func error(_ text: String, environment: FormulaEnvironment = .classic) -> FormulaError? {
        do {
            let program = try FormulaParser.parseProgram(text, environment: environment)
            _ = try FormulaBinder.bind(program, environment: environment)
            return nil
        } catch let error as FormulaError {
            return error
        } catch {
            return nil
        }
    }

    private func synthValue(_ text: String, inputs: [FormulaVariable: Double] = [:], prelude: String? = nil,
                            autoParameters: Bool = false) throws -> Double {
        var environment = FormulaEnvironment(context: .synth)
        environment.allowAutoParameters = autoParameters
        var preludePrograms: [FormulaSourceProgram] = []
        if let prelude {
            var definitionsEnvironment = FormulaEnvironment(context: .synth)
            definitionsEnvironment.requiresOutput = false
            let program = try FormulaParser.parseProgram(prelude, environment: definitionsEnvironment)
            preludePrograms.append(FormulaSourceProgram(program: program, sourceName: "Definitionen"))
            for statement in program.definitions {
                if case .function(let name, let parameters) = statement.kind {
                    environment.externalDefinitions[name] = .function(arity: parameters.count)
                } else if let name = statement.definedName {
                    environment.externalDefinitions[name] = statement.isList ? .list : .value
                }
            }
        }
        let program = try FormulaParser.parseProgram(text, environment: environment)
        let result = try FormulaBinder.bind(main: FormulaSourceProgram(program: program, sourceName: nil), prelude: preludePrograms,
                                            environment: environment, fixedVariables: [])
        var values = [Double](repeating: 0, count: FormulaVariable.allCases.count)
        for (variable, value) in inputs { values[variable.slot] = value }
        return result.root.evaluate(inputs: values)
    }

    // MARK: Conditions

    @Test("Vergleiche liefern 1/0, undefiniert bleibt undefiniert")
    func comparisons() throws {
        #expect(try value("3 > 2") == 1)
        #expect(try value("3 < 2") == 0)
        #expect(try value("2 <= 2") == 1)
        #expect(try value("2 >= 3") == 0)
        #expect(try value("2 == 2") == 1)
        #expect(try value("2 != 2") == 0)
        #expect(try value("2 ≠ 3") == 1)
        #expect(try value("sqrt(-1) < 2").isNaN)
        #expect(try value("x^2 > 4", x: 3) == 1)
    }

    @Test("and, or, not mit Kurzschluss")
    func logic() throws {
        #expect(try value("(2 > 1) and (3 > 4)") == 0)
        #expect(try value("(2 > 1) or (3 > 4)") == 1)
        #expect(try value("not(2 > 1)") == 0)
        #expect(try value("not 1 > 2") == 1, "not bindet schwächer als der Vergleich")
        // The right side is not evaluated when the left side decides.
        #expect(try value("(x > 0) and (sqrt(x) > 1)", x: -1) == 0)
        #expect(try value("(x < 0) or (ln(x) > 1)", x: -1) == 1)
    }

    @Test("if und piecewise werten nur den gewählten Zweig aus")
    func lazyBranches() throws {
        #expect(try value("if(x > 0, sqrt(x), 0)", x: -1) == 0)
        #expect(try value("if(x != 0, 1/x, 0)", x: 0) == 0)
        #expect(try value("if(x > 0, sqrt(x), 0)", x: 4) == 2)
        #expect(try value("piecewise(x > 0, ln(x), 0)", x: -1) == 0)
        #expect(try value("piecewise(x < -2, -1, x < 2, x/2, 1)", x: 1) == 0.5)
        #expect(try value("piecewise(x < -2, -1, x < 2, x/2, 1)", x: 5) == 1)
        #expect(try value("piecewise(x < -2, -1, x < 2, x/2, 1)", x: -3) == -1)
        // An expensive loop in the inactive branch costs nothing and does not exhaust the budget.
        #expect(try value("if(x > 1, sum(i, 1, 10000, sum(j, 1, 10000, 1)), 3)", x: 0) == 3)
        // Undefined condition → undefined result.
        #expect(try value("if(sqrt(x) > 1, 1, 2)", x: -4).isNaN)
    }

    @Test("piecewise braucht einen Sonst-Fall")
    func piecewiseArity() {
        #expect(error("piecewise(x < 0, 1)")?.kind == .wrongArgumentCount)
        #expect(error("piecewise(x < 0, 1, x < 1, 2)")?.kind == .wrongArgumentCount)
        #expect(error("if(x < 0, 1)")?.kind == .wrongArgumentCount)
        #expect(error("0 < x < 1")?.kind == .comparisonChain)
    }

    // MARK: Functions

    @Test("frac, clip, clamp, arctan, sign, min/max mit mehreren Werten")
    func newFunctions() throws {
        #expect(try value("frac(2.75)") == 0.75)
        #expect(try value("frac(-0.25)") == 0.75)
        #expect(try value("clip(5, 0, 3)") == 3)
        #expect(try value("clip(-2, 0, 3)") == 0)
        #expect(try value("clamp(1.5, 0, 3)") == 1.5)
        #expect(try value("clip(1, 3, 0)").isNaN, "Untergrenze über Obergrenze ist undefiniert")
        #expect(try value("arctan(1)") == Double.pi / 4)
        #expect(try value("arcsin(1)") == Double.pi / 2)
        #expect(try value("sign(-3)") == -1)
        #expect(try value("min(4, -1, 3)") == -1)
        #expect(try value("max(4, -1, 3, 9)") == 9)
        #expect(try value("floor(-2.5)") == -3)
        #expect(try value("ceil(-2.5)") == -2)
        #expect(try value("round(-2.5)") == -3)
    }

    @Test("Potenz von -1 ist für ganzzahlige Exponenten exakt")
    func negativeBasePower() throws {
        #expect(try value("(-1)^3") == -1)
        #expect(try value("(-1)^4") == 1)
        #expect(try value("(-1)^floor(2^60)") == 1)
        #expect(try value("(-1)^floor(x)", x: 7.9) == -1)
        #expect(try value("(-8)^(1/3)").isNaN)
        #expect(try value("(-2)^3") == -8)
        // Precedence stays as before.
        #expect(try formula("-x^2").root.canonicalDescription == "(-(x^2))")
        #expect(try value("2^3^2") == 512)
    }

    // MARK: Sums and products

    @Test("sum und prod: inklusive Grenzen, leere Bereiche")
    func sumsAndProducts() throws {
        #expect(try value("sum(i, 1, 5, i)") == 15)
        #expect(try value("prod(i, 1, 4, i)") == 24)
        #expect(try value("sum(i, 5, 1, i)") == 0, "leere Summe")
        #expect(try value("prod(i, 5, 1, i)") == 1, "leeres Produkt")
        #expect(try value("sum(i, 3, 3, i^2)") == 9)
        #expect(try value("Σ(i, 1, 3, i)") == 6)
        let graph = try value("sum(i, 1, 5, sin(i*x)/i)", x: 0.7)
        let expected = (1...5).reduce(0.0) { $0 + sin(Double($1) * 0.7) / Double($1) }
        #expect(abs(graph - expected) < 1e-12)
    }

    @Test("Scoping der Laufvariable")
    func loopScoping() throws {
        // Inner loop variable shadows the outer one.
        #expect(try value("sum(i, 1, 3, sum(i, 1, 2, i))") == 9)
        // Start and end see the outer definition, the body the loop variable.
        #expect(try value("i = 4\nsum(i, 1, i, i)") == 10)
        // Outside the body the loop variable does not exist.
        #expect(error("sum(k, 1, 3, k) + k")?.kind == .unknownName)
        #expect(error("sum(k, 1, k, 1)")?.kind == .unknownName)
        // The loop variable shadows x inside the body only.
        #expect(try value("sum(x, 1, 3, x) + x", x: 10) == 16)
        // Helper functions do not see the caller's loop variable.
        #expect(error("g(y) = y + i\nsum(i, 1, 3, g(i))")?.kind == .unknownName)
    }

    @Test("Grenzen und Iterationslimits")
    func loopLimits() throws {
        #expect(error("sum(i, 1, 2.5, i)")?.kind == .invalidArgument)
        #expect(error("sum(i, 1, 20000, 1)")?.kind == .invalidArgument)
        #expect(try value("sum(i, 1, x, i)", x: 2.5).isNaN, "nicht ganzzahlige Grenze zur Laufzeit")
        #expect(try value("sum(i, 1, x, 1)", x: 20_000).isNaN, "zu viele Durchläufe zur Laufzeit")
        #expect(try value("sum(i, 1, x, sum(j, 1, x, 1))", x: 1_000).isNaN, "Gesamtbudget je Auswertung")
        #expect(try value("sum(i, 1, x, sum(j, 1, x, 1))", x: 100) == 10_000)
        #expect(error("sum(2, 1, 3, 1)")?.kind == .invalidArgument)
        #expect(error("sum(i, 1, 3)")?.kind == .wrongArgumentCount)
    }

    // MARK: Lists and definitions

    @Test("Listen: nullbasierter Index, len, zyklischer Zugriff, negative mod")
    func lists() throws {
        let notes = "notes = [0, 3, 7, 10]\n"
        #expect(try value(notes + "notes[0]") == 0)
        #expect(try value(notes + "notes[2]") == 7)
        #expect(try value(notes + "len(notes)") == 4)
        #expect(try value(notes + "notes[mod(-1, len(notes))]") == 10)
        #expect(try value(notes + "notes[mod(x, len(notes))]", x: 6) == 7)
        #expect(try value(notes + "notes[4]").isNaN, "außerhalb")
        #expect(try value(notes + "notes[-1]").isNaN, "negative Indizes zählen nicht vom Ende")
        #expect(try value(notes + "notes[1.5]").isNaN)
        #expect(try value("[2, 4, 8][1]") == 4)
        #expect(try value("mod(-7, 3)") == 2)
        #expect(error(notes + "notes + 1")?.kind == .typeMismatch)
        #expect(error("[1, [2, 3]][0]")?.kind == .typeMismatch)
        #expect(error("k = 3\nk[0]")?.kind == .typeMismatch)
    }

    @Test("Hilfsfunktionen, Zwischenwerte, mehrzeilige Definitionen")
    func definitions() throws {
        #expect(try value("r(x) = frac(2*x)\nr(0.75)") == 0.5)
        #expect(try value("p = x + 8\n1 + (5/12)*(floor((1+p/8)sin(pi*p^2/4))+1)", x: 0)
                == 1 + (5.0 / 12) * (floor(2 * sin(Double.pi * 16)) + 1))
        // Order does not matter.
        #expect(try value("k^2 + 1\nk = 3") == 10)
        // Walsh/Rademacher with a two-parameter helper.
        let walsh = "r(k,x) = (-1)^floor(2^kx)\nK = 2\n6(1+prod(k, 0, K, r(k,x)))"
        let expected = 6 * (1 + (0...2).reduce(1.0) { $0 * pow(-1, floor(pow(2, Double($1)) * 0.3)) })
        #expect(try value(walsh, x: 0.3) == expected)
        // Legacy prefixes keep their meaning.
        #expect(try formula("f(x) = sin(x)").root == formula("sin(x)").root)
        #expect(try formula("y = sin(x)").root == formula("sin(x)").root)
        // A definition used twice is bound once, not evaluated twice.
        let bound = try formula("s = sin(x)\ns*s + s")
        if case .binding = bound.root {} else { Issue.record("Zweimal verwendete Definition sollte gebunden werden") }
    }

    @Test("Zyklen, doppelte Namen und reservierte Namen werden erkannt")
    func definitionErrors() {
        #expect(error("u = v\nv = u\nu")?.kind == .cyclicDefinition)
        #expect(error("u = u + 1\nu")?.kind == .cyclicDefinition)
        #expect(error("g(y) = g(y)\ng(1)")?.kind == .cyclicDefinition)
        #expect(error("k = 1\nk = 2\nk")?.kind == .duplicateDefinition)
        #expect(error("pi = 3\npi")?.kind == .invalidDefinition)
        #expect(error("sin = 3\nsin")?.kind == .invalidDefinition)
        #expect(error("x = 2")?.kind == .misplacedEquals)
        #expect(error("k = 1\nk + 1\nk + 2")?.kind == .multipleOutputs)
        #expect(error("k = 1")?.kind == .missingOutput)
        // Even unused definitions are checked.
        #expect(error("u = v\nv = u\n1")?.kind == .cyclicDefinition)
    }

    @Test("Fehler nennen Zeile und Position")
    func errorLocation() {
        let multiLine = error("k = 2\nk +* 3")
        #expect(multiLine?.line == 2)
        #expect(multiLine?.column == 4)
        #expect(multiLine?.localizedSummary.contains("Zeile 2") == true)
        let single = error("sin(x")
        #expect(single?.line == nil)
        #expect(single?.localizedSummary.contains("Position 4") == true)
    }

    // MARK: Names

    @Test("Mehrbuchstabige Namen, Ziffern und griechische Aliasse")
    func identifiers() throws {
        #expect(try value("tau = 0.09\nexp(-0.09/tau)") == exp(-1))
        #expect(try value("f1 = 2\nf2 = 3\nf1*f2") == 6)
        #expect(try value("τ = 2\nτ*3") == 6)
        #expect(try value("ω = 3\nomega + ω") == 6)
        #expect(abs(try value("2πx", x: 1) - 2 * Double.pi) < 1e-12)
        #expect(abs(try value("p = 2\npip^2") - 4 * Double.pi) < 1e-12)
        #expect(try value("k = 3\nkmod(x, 2)", x: 5) == 3)
        #expect(try value("N_k = 6\nN_k") == 6)
        // Classic segmentation is unchanged.
        #expect(try value("bx", x: 4, parameters: FormulaParameters(a: 1, b: 0.5, c: 0)) == 2)
        #expect(try value("asin(bx)+c", x: 4, parameters: FormulaParameters(a: 1, b: 0.25, c: 1)) == asin(1) + 1)
    }

    @Test("Mehrdeutige Buchstabenfolgen werden gemeldet, nicht still erraten")
    func ambiguity() throws {
        let parsed = try formula("aacos(x)")
        #expect(!parsed.warnings.isEmpty)
        #expect(parsed.warnings.first?.message.contains("mehrdeutig") == true)
        #expect(try value("aacos(x)", x: 0.5, parameters: FormulaParameters(a: 2, b: 1, c: 0)) == 2 * acos(0.5))
        #expect(try formula("2pix").warnings.isEmpty, "eindeutige Zerlegung ohne Warnung")
    }

    @Test("Zeitvariablen nur im Synthesizer")
    func synthContext() throws {
        #expect(error("sin(t)")?.kind == .unknownName)
        #expect(error("sin(t)")?.hint?.contains("Formel-Synthesizer") == true)
        #expect(try synthValue("beat + bar", inputs: [.beat: 5, .bar: 1]) == 6)
        #expect(try synthValue("exp(-13*mod(localBeat, 2^(-k)))", inputs: [.localBeat: 0.75], prelude: "k = 2") == 1)
        #expect(error("Beat + 1", environment: FormulaEnvironment(context: .synth))?.hint?.contains("beat") == true)
        // Definitions from earlier sources are visible.
        #expect(try synthValue("notes[mod(n, len(notes))]", inputs: [.n: 5], prelude: "notes = [0, 3, 7, 10]") == 3)
        // Automatic parameters in the simple editor.
        #expect(try synthValue("2*depth", autoParameters: true) == 2)
    }

    @Test("Kompilierte Auswertung entspricht dem Interpreter für neue Konstrukte")
    func compiledMatchesInterpreterV2() throws {
        let formulas = [
            "if(x > 0, sqrt(x), -x)", "piecewise(x < -1, x^2, x < 1, sin(3x), frac(x))",
            "sum(k, 0, 6, 0.55^kcos(3^kpix/2))", "notes = [0, 3, 7, 10]\nnotes[mod(floor(x), len(notes))]",
            "r(x) = frac(2*x)\nr(x) + r(x/3)", "clip(3tan(pi*(frac(x)-0.5)), -12, 24)", "24/(1+6*mod(x,2))-12",
            "atan(s*sin(4pi*x))/atan(s)\ns = 8", "(x > 0) and (x < 2) or (x < -3)"
        ]
        for text in formulas {
            let parsed = try formula(text)
            let compiled = parsed.compiled(parameters: FormulaParameters())
            for step in -40...40 {
                let x = Double(step) * 0.173
                let interpreted = parsed.root.evaluate(x: x, parameters: FormulaParameters())
                let fast = compiled.raw(x)
                if interpreted.isNaN {
                    #expect(fast.isNaN, "\(text) at \(x)")
                } else {
                    #expect(abs(interpreted - fast) <= 1e-12 * max(1, abs(interpreted)), "\(text) at \(x)")
                }
            }
        }
    }

    // MARK: Stack safety

    /// Parses, binds, compiles and evaluates `text`; returns "ok" or the error kind.
    private static func outcome(_ text: String) -> String {
        let environment = FormulaEnvironment.classic
        do {
            let program = try FormulaParser.parseProgram(text, environment: environment)
            let root = try FormulaBinder.bind(program, environment: environment).root
            let compiled = CompiledProgram(root)
            let buffer = EvaluationBuffer(capacity: compiled.slotCount)
            buffer[.x] = 1
            let fast = buffer.evaluate(compiled)
            let reference = root.evaluate(x: 1, parameters: FormulaParameters())
            return fast == reference || (fast.isNaN && reference.isNaN) ? "ok" : "mismatch"
        } catch let error as FormulaError {
            return "\(error.kind)"
        } catch {
            return "error"
        }
    }

    @Test("Tiefe Formeln brauchen wenig Stack: alles läuft auf einem Thread mit 512 KB (wie Hintergrund-Threads unter iOS)")
    func deepFormulasFitSmallStacks() {
        let helpers = (1...31).map { "f\($0)(k) = f\($0 - 1)(k) + 1" }.joined(separator: "\n")
        let tooManyHelpers = (1...40).map { "g\($0)(k) = g\($0 - 1)(k) + 1" }.joined(separator: "\n")
        let chainOfDefinitions = "a1 = x + 1\n" + (1..<78).map { "a\($0 + 1) = a\($0) + 1" }.joined(separator: "\n") + "\na78"
        let cases: [(String, String)] = [
            (String(repeating: "x+", count: 150) + "x", "ok"),
            (String(repeating: "x+", count: 170) + "x", "tooComplex"),
            (String(repeating: "(", count: 63) + "x" + String(repeating: ")", count: 63), "ok"),
            (String(repeating: "(", count: 100) + "x" + String(repeating: ")", count: 100), "nestingTooDeep"),
            (String(repeating: "sin(", count: 63) + "x" + String(repeating: ")", count: 63), "ok"),
            (String(repeating: "-", count: 400) + "x", "nestingTooDeep"),
            (String(repeating: "2^", count: 100) + "x", "nestingTooDeep"),
            (String(repeating: "not ", count: 100) + "x", "nestingTooDeep"),
            ("f0(k) = k + 1\n" + helpers + "\nf31(x)", "ok"),
            ("g0(k) = k + 1\n" + tooManyHelpers + "\ng40(x)", "tooComplex"),
            (chainOfDefinitions, "ok"),
            ("--x", "ok")
        ]
        let box = OutcomeBox()
        let texts = cases.map(\.0)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.values = texts.map { Self.outcome($0) }
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        done.wait()
        #expect(box.values == cases.map(\.1))
    }
}

/// Result of the small-stack thread (handed over through a semaphore).
private final class OutcomeBox: @unchecked Sendable {
    var values: [String] = []
}
