import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Formel-Editor: Darstellung und Signaturhilfe")
struct FormulaEditingTests {
    private func program(_ text: String, environment: FormulaEnvironment = .classic) throws -> SyntaxProgram {
        try FormulaParser.parseProgram(text, environment: environment)
    }

    @Test("Summe wird als Σ mit Laufvariable, Start, Ende und Ausdruck dargestellt")
    func sumLayout() throws {
        let lines = MathLayout.lines(of: try program("sum(i, 1, 5, i)"))
        #expect(lines.count == 1)
        guard case .bigOperator(let symbol, let lower, let upper, let body) = lines[0].body else {
            Issue.record("Σ erwartet, gefunden \(lines[0].body)")
            return
        }
        #expect(symbol == "Σ")
        #expect(lower.plainText == "i=1")
        #expect(upper.plainText == "5")
        #expect(body.plainText == "i")
        guard case .bigOperator(let productSymbol, _, _, _) = MathLayout.lines(of: try program("prod(i, 1, 4, i)"))[0].body else {
            Issue.record("Π erwartet")
            return
        }
        #expect(productSymbol == "Π")
    }

    @Test("Brüche, Potenzen, Wurzel, Betrag und Fallunterscheidungen")
    func structures() throws {
        let fraction = MathLayout.lines(of: try program("(x+1)/(x-1)"))[0].body
        guard case .fraction(let numerator, let denominator) = fraction else {
            Issue.record("Bruch erwartet")
            return
        }
        #expect(numerator.plainText == "x + 1")
        #expect(denominator.plainText == "x − 1")
        guard case .power(_, let exponent) = MathLayout.lines(of: try program("2^(x+1)"))[0].body else {
            Issue.record("Potenz erwartet")
            return
        }
        #expect(exponent.plainText == "x + 1")
        #expect(MathLayout.lines(of: try program("abs(x)"))[0].body.plainText == "|x|")
        #expect(MathLayout.lines(of: try program("sqrt(x)"))[0].body.plainText == "√(x)")
        #expect(MathLayout.lines(of: try program("2*pi*x"))[0].body.plainText == "2·π·x")
        #expect(MathLayout.lines(of: try program("2x"))[0].body.plainText == "2x")
        guard case .cases(let rows) = MathLayout.lines(of: try program("piecewise(x < 0, -1, x < 1, 0, 1)"))[0].body else {
            Issue.record("Fallunterscheidung erwartet")
            return
        }
        #expect(rows.count == 3)
        #expect(rows[0].condition?.plainText == "x < 0")
        #expect(rows[2].condition == nil, "letzte Zeile ist der Sonst-Fall")
        guard case .cases(let ifRows) = MathLayout.lines(of: try program("if(x > 0, x, 0)"))[0].body else {
            Issue.record("if als Fallunterscheidung erwartet")
            return
        }
        #expect(ifRows.count == 2)
    }

    @Test("Mehrzeilige Programme: Definitionen zuerst, Ausgabe zuletzt")
    func programLines() throws {
        let lines = MathLayout.lines(of: try program("y = p^2\np = x + 8\nr(x) = frac(2*x)"))
        #expect(lines.map(\.kind) == [.definition, .function, .output])
        #expect(lines[0].label.plainText == "p")
        #expect(lines[1].label.plainText == "r(x)")
        #expect(MathLayout.lines(of: try program("tau = 2\ntau*x"))[0].label.plainText == "τ")
    }

    @Test("Signaturhilfe hebt den aktuellen Argumentplatz hervor")
    func signatureHelp() {
        let clip = FormulaTextTools.signature(in: "clip(x, 0, ", cursor: 11)
        #expect(clip?.functionName == "clip")
        #expect(clip?.argumentNames == ["wert", "untergrenze", "obergrenze"])
        #expect(clip?.activeArgument == 2)
        #expect(clip?.activeMeaning == "größter erlaubter Wert")

        let nested = "mod(sin(x), "
        #expect(FormulaTextTools.signature(in: nested, cursor: 8)?.functionName == "sin")
        #expect(FormulaTextTools.signature(in: nested, cursor: 12)?.functionName == "mod")
        #expect(FormulaTextTools.signature(in: nested, cursor: 12)?.activeArgument == 1)

        let sum = "sum(i, 1, 5, "
        let context = FormulaTextTools.signature(in: sum, cursor: sum.count)
        #expect(context?.argumentNames == ["laufvariable", "start", "ende", "ausdruck"])
        #expect(context?.activeArgument == 3)

        // Commas inside lists do not move the argument position.
        let list = "max([1, 2][0], "
        #expect(FormulaTextTools.signature(in: list, cursor: list.count)?.activeArgument == 1)

        // Helper functions of the program.
        let user = "r(k, x) = k*x\nr(2, "
        let userContext = FormulaTextTools.signature(in: user, cursor: user.count)
        #expect(userContext?.argumentNames == ["k", "x"])
        #expect(userContext?.activeArgument == 1)
        #expect(userContext?.isBuiltIn == false)

        #expect(FormulaTextTools.helpTopic(in: "sin(x) + clip", cursor: 13) == "clip")
        #expect(FormulaTextTools.helpTopic(in: "arctan(x)", cursor: 3) == "atan")
    }

    @Test("Visueller Fallunterscheidungs-Editor: lesen und schreiben")
    func piecewiseDraft() throws {
        let text = "1 + piecewise(x < 0, -1, x < 1, x, 1)"
        let call = try #require(FormulaTextTools.enclosingCall(in: text, cursor: 10, names: ["piecewise", "if"]))
        #expect(call.range == 4..<text.count)
        let draft = try #require(PiecewiseDraft(call: call))
        #expect(draft.cases.count == 2)
        #expect(draft.cases[1].condition == "x < 1")
        #expect(draft.otherwise == "1")
        var edited = draft
        edited.cases.append(PiecewiseDraft.Case(condition: "x < 2", expression: "2x"))
        let replaced = FormulaTextTools.replacing(call.range, in: text, with: edited.formulaText)
        #expect(replaced == "1 + piecewise(x < 0, -1, x < 1, x, x < 2, 2x, 1)")
        if case .failure(let error) = ParsedFormula.parse(replaced) { Issue.record("\(error)") }

        let ifCall = try #require(FormulaTextTools.enclosingCall(in: "if(x > 0, x, 0)", cursor: 3, names: ["if"]))
        let fromIf = try #require(PiecewiseDraft(call: ifCall))
        #expect(fromIf.formulaText == "piecewise(x > 0, x, 0)")
        var empty = PiecewiseDraft.empty
        empty.otherwise = " "
        #expect(empty.missingParts == ["Sonst-Fall"])
    }

    @Test("Visueller Summen-/Produkt-Editor")
    func aggregateDraft() throws {
        let call = try #require(FormulaTextTools.enclosingCall(in: "sum(k, 0, N, 0.5^k)", cursor: 5, names: ["sum", "prod"]))
        let draft = try #require(AggregateDraft(call: call))
        #expect(draft.kind == .sum)
        #expect(draft.variable == "k")
        #expect(draft.end == "N")
        var product = AggregateDraft.sumExample
        product.kind = .prod
        #expect(product.formulaText == "prod(i, 1, 5, sin(i*x)/i)")
        product.variable = "2i"
        #expect(!product.variableIsValid)
        #expect(FormulaTextTools.splitArguments("a, (b, c), [d, e]") == ["a", "(b, c)", "[d, e]"])
    }
}
