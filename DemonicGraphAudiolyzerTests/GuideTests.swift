import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Anleitungen")
struct GuideTests {
    /// Evaluates an example with the real parser in its context.
    private func evaluate(_ example: GuideExample) throws -> Double? {
        switch example.context {
        case .none:
            return nil
        case .classic(let x):
            switch ParsedFormula.parse(example.input) {
            case .success(let formula):
                return formula.root.evaluate(x: x, parameters: FormulaParameters())
            case .failure(let error):
                throw error
            }
        case .synth(let inputs):
            let environment = FormulaEnvironment(context: .synth)
            let program = try FormulaParser.parseProgram(example.input, environment: environment)
            let root = try FormulaBinder.bind(program, environment: environment).root
            var values = [Double](repeating: 0, count: FormulaVariable.allCases.count)
            for (name, value) in inputs {
                let variable = try #require(FormulaVariable(rawValue: name), "Unbekannte Variable \(name)")
                values[variable.slot] = value
            }
            return root.evaluate(inputs: values)
        }
    }

    @Test("Jede Funktion und jeder Operator des Parsers hat einen Eintrag")
    func coverage() {
        for spec in FormulaCatalog.functions {
            let entry = GuideCatalog.entry(id: "function-" + spec.id)
            #expect(entry != nil, "Funktion \(spec.id) fehlt")
            #expect(entry?.syntax == spec.syntax)
            for alias in spec.aliases {
                #expect(entry?.commands.contains(alias) == true, "Alias \(alias)")
            }
        }
        for spec in FormulaOperators.all {
            #expect(GuideCatalog.entry(id: "operator-" + spec.id) != nil, "Operator \(spec.id) fehlt")
        }
        for variable in FormulaVariable.allCases where !variable.isLegacyParameter || variable == .a {
            #expect(GuideCatalog.entry(id: "variable-" + variable.rawValue) != nil, "Variable \(variable.rawValue) fehlt")
        }
        // Every name the parser accepts as a function is documented.
        for spelling in FormulaCatalog.allSpellings {
            let spec = FormulaCatalog.function(named: spelling)!
            #expect(GuideCatalog.entry(forHelpTopic: spelling)?.functionID == spec.id, "Hilfe zu \(spelling)")
        }
        // Mandatory topics.
        for id in ["topic-808", "topic-reverse-bass", "topic-pendulum", "topic-fibonacci", "topic-pascal", "topic-riser",
                   "topic-roles", "topic-pitch-units", "topic-amplitude", "topic-signal", "topic-seconds-beats",
                   "topic-cyclic-access", "topic-helper-functions", "topic-intermediate-values", "topic-loop-variables",
                   "topic-formula-or-generator", "operator-times", "operator-divide", "operator-decimal", "operator-implicit"] {
            #expect(GuideCatalog.entry(id: id) != nil, "\(id) fehlt")
        }
        for category in GuideCategory.allCases {
            #expect(!GuideCatalog.entries(in: category).isEmpty, "\(category.title) ist leer")
        }
        #expect(Set(GuideCatalog.entries.map(\.id)).count == GuideCatalog.entries.count, "eindeutige IDs")
    }

    @Test("Pflichteintrag Summenzeichen Σ")
    func sumEntry() throws {
        let entry = try #require(GuideCatalog.entry(id: "function-sum"))
        #expect(entry.symbol == "Σ")
        #expect(entry.mathNotation == "Σ von i = 1 bis 5 über i")
        #expect(entry.syntax == "sum(laufvariable, start, ende, ausdruck)")
        #expect(entry.arguments.map(\.position) == [1, 2, 3, 4])
        #expect(entry.arguments.map(\.name) == ["laufvariable", "start", "ende", "ausdruck"])
        #expect(entry.arguments[0].meaning == "Name der Zählvariable, beispielsweise i")
        #expect(entry.arguments[1].meaning == "Erster ganzzahliger Wert")
        #expect(entry.arguments[2].meaning == "Letzter ganzzahliger Wert, einschließlich")
        #expect(entry.arguments[3].meaning.hasPrefix("Term, der für jeden Wert berechnet und addiert wird"))
        #expect(entry.arguments.map(\.mathPosition) == ["Unter dem Σ, links vom Gleichheitszeichen",
                                                        "Unter dem Σ, rechts vom Gleichheitszeichen",
                                                        "Über dem Σ", "Rechts neben dem Σ"])
        let example = try #require(entry.examples.first)
        #expect(example.input == "sum(i, 1, 5, i)")
        #expect(example.result == "1 + 2 + 3 + 4 + 5 = 15")
        #expect(example.note == "Ohne x oder t ist das Ergebnis konstant. Als Funktion dargestellt ergibt sich y = 15.")
        #expect(try evaluate(example) == 15)
        let graph = try #require(entry.graphExample)
        #expect(graph.input == "sum(i, 1, 5, sin(i*x)/i)")
        #expect(graph.result == "Fünf Sinusfunktionen mit unterschiedlichen Frequenzen und Gewichtungen werden addiert.")
        #expect(entry.diagram == .bigOperator(symbol: "Σ", variable: "i", start: "1", end: "5", body: "i"))
        #expect(entry.commands.contains("Σ"))

        let product = try #require(GuideCatalog.entry(id: "function-prod"))
        #expect(product.syntax == "prod(laufvariable, start, ende, ausdruck)")
        #expect(product.examples.first?.result == "1·2·3·4 = 24")
        #expect(try evaluate(product.examples[0]) == 24)
    }

    @Test("Argumentpositionen stimmen mit dem Parser überein")
    func argumentPositions() throws {
        let mod = try #require(GuideCatalog.entry(id: "function-mod"))
        #expect(mod.syntax == "mod(wert, divisor)")
        #expect(mod.arguments.map(\.meaning) == ["zu teilender Wert", "Divisor (Periodenlänge)"])
        let clip = try #require(GuideCatalog.entry(id: "function-clip"))
        #expect(clip.syntax == "clip(wert, untergrenze, obergrenze)")
        #expect(clip.arguments.map(\.meaning) == ["zu begrenzender Wert", "kleinster erlaubter Wert", "größter erlaubter Wert"])
        // The parser really uses this order: clip(value, low, high).
        #expect(try evaluate(GuideExample(input: "clip(5, 0, 3)", result: "", expectedValue: 3, context: .classic(x: 0))) == 3)
        #expect(try evaluate(GuideExample(input: "mod(7, 3)", result: "", expectedValue: 1, context: .classic(x: 0))) == 1)
        // Signature help uses the same argument names as the guide.
        for spec in FormulaCatalog.functions where spec.implementation != .special(.piecewise) {
            let entry = try #require(GuideCatalog.entry(id: "function-" + spec.id))
            let context = FormulaTextTools.signature(in: spec.id + "(", cursor: spec.id.count + 1)
            #expect(context?.argumentNames.first == entry.arguments.first?.name, "\(spec.id)")
        }
    }

    @Test("Alle kopierbaren Beispiele lassen sich mit dem echten Parser auswerten")
    func examplesEvaluate() throws {
        var evaluated = 0
        for entry in GuideCatalog.entries {
            for example in entry.examples + [entry.graphExample].compactMap({ $0 }) {
                if case .none = example.context {
                    // Graph examples: must at least parse in their role.
                    if case .formula(let text, let role) = example.payload?.content {
                        switch role {
                        case .graph, .waveform:
                            if case .failure(let error) = ParsedFormula.parse(text) { Issue.record("\(entry.id): \(text) – \(error.localizedSummary)") }
                        default:
                            break
                        }
                    }
                    continue
                }
                do {
                    let value = try evaluate(example)
                    if let expected = example.expectedValue, let value {
                        #expect(abs(value - expected) <= 1e-9 * max(1, abs(expected)), "\(entry.id): \(example.input) = \(value), erwartet \(expected)")
                    }
                    evaluated += 1
                } catch let error as FormulaError {
                    Issue.record("\(entry.id): \(example.input) – \(error.localizedSummary)")
                }
            }
        }
        #expect(evaluated > 80)
    }

    @Test("„Im Editor öffnen“ lädt Beispiele vollständig konfiguriert")
    func openInEditor() throws {
        for entry in GuideCatalog.entries {
            for example in entry.examples + [entry.graphExample].compactMap({ $0 }) {
                guard let payload = example.payload else { continue }
                let preset = try #require(payload.makePreset(), "\(entry.id)")
                if let project = preset.project {
                    let compilation = SynthCompilation(project: project, sampleRate: 44_100)
                    #expect(compilation.blockingIssue == nil, "\(entry.id): \(compilation.blockingIssue ?? "")")
                } else {
                    if case .failure(let error) = ParsedFormula.parse(preset.formula) {
                        Issue.record("\(entry.id): \(error.localizedSummary)")
                    }
                }
            }
        }
        // An example with additional parameters opens with all of them, its role and mode.
        let parameters = try #require(GuideCatalog.entry(id: "topic-parameters")?.examples.first?.payload?.makePreset())
        #expect(parameters.settings.mode == .synthesizer)
        let voice = try #require(parameters.project?.voices.first)
        #expect(voice.parameters.map(\.name) == ["period", "k"])
        #expect(voice.parameters[0].mode == .perBar)
        #expect(voice.pitch.unit == .octaves)
        #expect(voice.pitch.formula == "-1.6 + 5exp(-k*mod(x, period))")
        let amplitude = try #require(GuideCatalog.entry(id: "variable-localTime")?.examples.first?.payload?.makePreset())
        #expect(amplitude.project?.voices.first?.amplitude.formula == "exp(-6*localTime)")
        let classic = try #require(GuideCatalog.entry(id: "variable-a")?.examples.first?.payload?.makePreset())
        #expect(classic.settings.mode == .graph)
        #expect(classic.parameters == FormulaParameters(a: 1.5, b: 2, c: 0))
        let preset = try #require(GuideCatalog.entry(id: "topic-reverse-bass")?.examples.first?.payload?.makePreset())
        #expect(preset.id == SynthPresets.reverseBass.id)
    }

    @Test("Suche nach Symbol, deutschem Namen und Befehl")
    func search() {
        #expect(GuideCatalog.search("Σ").first?.id == "function-sum")
        #expect(GuideCatalog.search("Summe").first?.id == "function-sum")
        #expect(GuideCatalog.search("sum").first?.id == "function-sum")
        #expect(GuideCatalog.search("Π").first?.id == "function-prod")
        #expect(GuideCatalog.search("Betrag").first?.id == "function-abs")
        #expect(GuideCatalog.search("abs").first?.id == "function-abs")
        #expect(GuideCatalog.search("arctan").first?.id == "function-atan")
        #expect(GuideCatalog.search("Fallunterscheidung").first?.id == "function-piecewise")
        #expect(GuideCatalog.search("π").contains { $0.id == "operator-constants" })
        #expect(GuideCatalog.search("modulo").first?.id == "function-mod")
        #expect(GuideCatalog.search("Wurzel").first?.id == "function-sqrt")
        #expect(GuideCatalog.search("beatInBar").first?.id == "variable-beatInBar")
        #expect(GuideCatalog.search("").count == GuideCatalog.entries.count)
        #expect(GuideCatalog.search("xyzunbekannt").isEmpty)
    }

    @Test("Die Hilfe funktioniert offline und verweist auf keine Webseiten")
    func offline() {
        for entry in GuideCatalog.entries {
            let text = ([entry.title, entry.explanation, entry.syntax] + entry.notes + entry.examples.map(\.result)).joined(separator: " ")
            #expect(!text.contains("http"), "\(entry.id)")
            #expect(!entry.explanation.isEmpty)
        }
    }

    @Test("„Anleitungen“ steht zwischen „Presets“ und „Einstellungen“")
    func tabOrder() {
        #expect(AppTab.allCases.map(\.title) == ["Graph & Klang", "Presets", "Anleitungen", "Einstellungen"])
        #expect(AppTab.guides.icon.contains("book"))
    }
}
