import Foundation

/// The single structured definition of all functions of the formula language.
///
/// The parser takes names, aliases and argument counts from here, and the "Anleitungen"
/// area renders exactly these entries (syntax, argument table, examples, notes). Tests check
/// that every example parses and evaluates to the documented result, so parser and guide
/// cannot drift apart.
enum FormulaCatalog {
    static let functions: [FunctionSpec] = trigonometry + powersAndLogs + rounding + comparisons + conditions + aggregates + lists

    /// Lookup by name or alias. Built-in names are case-insensitive (old formulas like `SIN(X)`).
    static func function(named name: String) -> FunctionSpec? {
        lookup[name.lowercased()]
    }

    /// All spellings (names and aliases, lower case) – used by the parser's name segmentation.
    static var allSpellings: [String] { Array(lookup.keys) }

    private static let lookup: [String: FunctionSpec] = {
        var table: [String: FunctionSpec] = [:]
        for spec in functions {
            table[spec.id] = spec
            for alias in spec.aliases {
                table[alias.lowercased()] = spec
            }
        }
        return table
    }()
}

/// What a function call does when it is evaluated.
enum FunctionImplementation: Equatable, Sendable {
    /// Strict function: all arguments are evaluated, then `MathSemantics` is applied.
    case math(MathFunction)
    /// Construct with its own evaluation rule (lazy branches, local variables, lists).
    case special(SpecialForm)
}

enum SpecialForm: String, Sendable {
    case ifElse = "if"
    case piecewise
    case sum
    case prod
    case len
}

/// Type and evaluation rule of one argument position.
enum ArgumentKind: Equatable, Sendable {
    case number
    /// A condition: non-zero counts as true, 0 as false, undefined stays undefined.
    case condition
    /// Only evaluated if selected (if/piecewise branches, loop bodies).
    case lazyExpression
    /// A new name (loop variable).
    case identifier
    case list
}

struct ArgumentSpec: Equatable, Sendable {
    /// Placeholder shown in signatures, e.g. "divisor".
    var name: String
    var meaning: String
    var kind: ArgumentKind = .number
    /// Where the argument appears in the printed mathematical notation (Σ, Π, cases …).
    var mathPosition: String?
    /// Allowed values and units.
    var allowed: String?
    /// The argument may be repeated (variadic tail, e.g. min/max, piecewise pairs).
    var isRepeatable = false
}

/// An example that the guide shows and the tests evaluate.
struct FormulaExample: Equatable, Sendable {
    var input: String
    /// Result as shown in the guide.
    var result: String
    /// Expected numeric value (evaluated at `x`), nil for graph examples.
    var value: Double?
    var x: Double = 0
    /// Explanation of the example.
    var note: String?
}

struct FunctionSpec: Equatable, Sendable, Identifiable {
    /// Canonical input name, e.g. "atan".
    var id: String
    var aliases: [String] = []
    var implementation: FunctionImplementation
    /// German name.
    var title: String
    /// Mathematical symbol / printed notation.
    var symbol: String
    var summary: String
    var arguments: [ArgumentSpec]
    var minimumArguments: Int
    /// nil = unlimited (variadic).
    var maximumArguments: Int?
    var examples: [FormulaExample]
    /// Example with x (classic graph) – shown as graph and openable in the editor.
    var graphExample: FormulaExample?
    var notes: [String] = []
    var keywords: [String] = []

    /// Generic syntax with named argument positions, e.g. "mod(wert, divisor)".
    var syntax: String {
        "\(id)(\(signatureArguments.joined(separator: ", ")))"
    }

    var signatureArguments: [String] {
        var names = arguments.map(\.name)
        if arguments.contains(where: \.isRepeatable) {
            names.append("…")
        }
        return names
    }

    /// Number of arguments accepted?
    func accepts(_ count: Int) -> Bool {
        if count < minimumArguments { return false }
        if let maximumArguments, count > maximumArguments { return false }
        if id == SpecialForm.piecewise.rawValue { return count % 2 == 1 }
        return true
    }

    /// Text inserted by the keyboard (cursor goes after the opening parenthesis).
    var template: String {
        let commas = String(repeating: ",", count: max(0, minimumArguments - 1))
        return "\(id)(\(commas))"
    }

    /// Index of the argument description for argument position `index` (variadic tails repeat).
    func argumentSpec(at index: Int) -> ArgumentSpec? {
        guard !arguments.isEmpty else { return nil }
        if index < arguments.count { return arguments[index] }
        if id == SpecialForm.piecewise.rawValue {
            // c1, e1, c2, e2, …, default: odd positions after the pairs are conditions/expressions.
            return index % 2 == 0 ? arguments[0] : arguments[1]
        }
        return arguments.last(where: \.isRepeatable)
    }
}

// MARK: - Catalogue content

extension FormulaCatalog {
    private static let angleArgument = ArgumentSpec(name: "winkel", meaning: "Winkel im Bogenmaß (Radiant)",
                                                    allowed: "jede Zahl; π entspricht 180°")

    static let trigonometry: [FunctionSpec] = [
        FunctionSpec(
            id: "sin", implementation: .math(.sin), title: "Sinus", symbol: "sin x",
            summary: "Schwingt gleichmäßig zwischen −1 und 1. Eine volle Periode dauert 2π.",
            arguments: [angleArgument], minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "sin(pi/2)", result: "1", value: 1)],
            graphExample: FormulaExample(input: "sin(x)", result: "Welle mit Periode 2π ≈ 6,28"),
            notes: ["Winkel immer im Bogenmaß: sin(90) ist nicht sin(90°). Für Grad: sin(pi*w/180).",
                    "Als Klang: sin(2*pi*f*t) ist ein reiner Ton der Frequenz f – für veränderliche Frequenzen besser die Tonhöhen-Rolle verwenden (kontinuierliche Phase)."],
            keywords: ["sinus", "welle", "schwingung", "trigonometrie"]),
        FunctionSpec(
            id: "cos", implementation: .math(.cos), title: "Kosinus", symbol: "cos x",
            summary: "Wie der Sinus, aber um eine Viertelperiode verschoben: cos(x) = sin(x + π/2).",
            arguments: [angleArgument], minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "cos(0)", result: "1", value: 1),
                       FormulaExample(input: "cos(pi)", result: "−1", value: -1)],
            graphExample: FormulaExample(input: "cos(x)", result: "Welle, beginnt bei x = 0 mit dem Maximum"),
            notes: ["Winkel im Bogenmaß."],
            keywords: ["kosinus", "cosinus", "welle"]),
        FunctionSpec(
            id: "tan", implementation: .math(.tan), title: "Tangens", symbol: "tan x",
            summary: "sin(x)/cos(x). Hat Polstellen bei x = π/2 + k·π, dort springt der Wert von +∞ nach −∞.",
            arguments: [angleArgument], minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "tan(pi/4)", result: "1", value: 1)],
            graphExample: FormulaExample(input: "tan(x)", result: "Äste zwischen den Polstellen"),
            notes: ["Polstellen werden im Graphen getrennt, nicht mit senkrechten Linien verbunden.",
                    "Als Tonhöhe sollte tan begrenzt werden, z. B. clip(3tan(x), -12, 24)."],
            keywords: ["tangens", "polstelle"]),
        FunctionSpec(
            id: "asin", aliases: ["arcsin"], implementation: .math(.asin), title: "Arkussinus", symbol: "arcsin x",
            summary: "Umkehrfunktion des Sinus: liefert den Winkel zwischen −π/2 und π/2.",
            arguments: [ArgumentSpec(name: "wert", meaning: "Sinuswert", allowed: "−1 … 1, sonst undefiniert")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "asin(1)", result: "π/2 ≈ 1,5708", value: Double.pi / 2)],
            graphExample: FormulaExample(input: "asin(x)", result: "nur zwischen x = −1 und 1 definiert"),
            notes: ["Außerhalb von −1 … 1 undefiniert: Lücke im Graphen, Stille im Klang.",
                    "Gleichwertige Eingaben: asin(x) und arcsin(x)."],
            keywords: ["arkussinus", "umkehrfunktion", "arcsin"]),
        FunctionSpec(
            id: "acos", aliases: ["arccos"], implementation: .math(.acos), title: "Arkuskosinus", symbol: "arccos x",
            summary: "Umkehrfunktion des Kosinus: liefert den Winkel zwischen 0 und π.",
            arguments: [ArgumentSpec(name: "wert", meaning: "Kosinuswert", allowed: "−1 … 1, sonst undefiniert")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "acos(1)", result: "0", value: 0),
                       FormulaExample(input: "acos(-1)", result: "π ≈ 3,1416", value: Double.pi)],
            graphExample: FormulaExample(input: "acos(x)", result: "nur zwischen x = −1 und 1 definiert"),
            notes: ["Gleichwertige Eingaben: acos(x) und arccos(x)."],
            keywords: ["arkuskosinus", "arccos"]),
        FunctionSpec(
            id: "atan", aliases: ["arctan"], implementation: .math(.atan), title: "Arkustangens", symbol: "arctan x",
            summary: "Umkehrfunktion des Tangens: für jede Zahl definiert, Ergebnis zwischen −π/2 und π/2. Wirkt wie eine weiche Begrenzung (Sättigung).",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "atan(1)", result: "π/4 ≈ 0,7854", value: Double.pi / 4),
                       FormulaExample(input: "arctan(1)", result: "π/4 ≈ 0,7854 (Alias)", value: Double.pi / 4)],
            graphExample: FormulaExample(input: "atan(8sin(x))/atan(8)", result: "Sinus, weich gesättigt"),
            notes: ["Gleichwertige Eingaben: atan(x) und arctan(x).",
                    "Sättigung: atan(s*sin(…))/atan(s) normiert die Spitze auf 1; bei s = 0 ist der Ausdruck 0/0 und muss mit if abgefangen werden."],
            keywords: ["arkustangens", "arctan", "sättigung", "saturation"])
    ]

    static let powersAndLogs: [FunctionSpec] = [
        FunctionSpec(
            id: "sqrt", implementation: .math(.sqrt), title: "Quadratwurzel", symbol: "√x",
            summary: "Die nichtnegative Zahl, deren Quadrat x ergibt.",
            arguments: [ArgumentSpec(name: "wert", meaning: "Radikand", allowed: "≥ 0, sonst undefiniert")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "sqrt(16)", result: "4", value: 4),
                       FormulaExample(input: "sqrt(2)", result: "≈ 1,4142 (Tritonus-Verhältnis)", value: 2.0.squareRoot())],
            graphExample: FormulaExample(input: "sqrt(x)", result: "beginnt bei x = 0"),
            notes: ["Das Zeichen √ der Zusatztastatur fügt sqrt() ein; √ braucht immer Klammern.",
                    "Andere Wurzeln über Potenzen: x^(1/3) ist die dritte Wurzel für x ≥ 0."],
            keywords: ["wurzel", "quadratwurzel"]),
        FunctionSpec(
            id: "exp", implementation: .math(.exp), title: "Exponentialfunktion", symbol: "eˣ",
            summary: "e hoch x. Mit negativem Argument entsteht ein exponentielles Abklingen – die Grundform vieler Hüllkurven.",
            arguments: [ArgumentSpec(name: "exponent", meaning: "Hochzahl zur Basis e ≈ 2,71828")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "exp(1)", result: "e ≈ 2,71828", value: M_E),
                       FormulaExample(input: "exp(0)", result: "1", value: 1)],
            graphExample: FormulaExample(input: "exp(-x)", result: "fällt exponentiell ab"),
            notes: ["exp(x) und e^x sind gleichwertig.",
                    "Hüllkurve: exp(-k*localTime) klingt nach jedem Trigger ab; größeres k = schneller."],
            keywords: ["exponential", "e hoch", "abklingen", "hüllkurve"]),
        FunctionSpec(
            id: "ln", implementation: .math(.ln), title: "Natürlicher Logarithmus", symbol: "ln x",
            summary: "Umkehrfunktion von exp: ln(e^x) = x.",
            arguments: [ArgumentSpec(name: "wert", meaning: "Argument", allowed: "> 0, sonst undefiniert")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "ln(e)", result: "1", value: 1)],
            graphExample: FormulaExample(input: "ln(x)", result: "nur für x > 0 definiert"),
            notes: ["„log“ allein wird nicht erraten: ln für den natürlichen, log10 für den Zehnerlogarithmus verwenden."],
            keywords: ["logarithmus", "natürlich", "log"]),
        FunctionSpec(
            id: "log10", implementation: .math(.log10), title: "Zehnerlogarithmus", symbol: "log₁₀ x",
            summary: "Welche Zehnerpotenz ergibt x? log10(1000) = 3.",
            arguments: [ArgumentSpec(name: "wert", meaning: "Argument", allowed: "> 0, sonst undefiniert")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "log10(1000)", result: "3", value: 3)],
            graphExample: FormulaExample(input: "log10(x)", result: "nur für x > 0 definiert"),
            notes: ["Pegel in Dezibel: 20*log10(a) rechnet einen linearen Faktor a in dB um."],
            keywords: ["logarithmus", "zehner", "dezibel"])
    ]

    static let rounding: [FunctionSpec] = [
        FunctionSpec(
            id: "abs", implementation: .math(.abs), title: "Betrag", symbol: "|x|",
            summary: "Abstand zur Null: negative Werte werden positiv.",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "abs(-3)", result: "3", value: 3)],
            graphExample: FormulaExample(input: "abs(sin(x))", result: "nur positive Bögen"),
            notes: ["In der mathematischen Darstellung stehen Betragsstriche |x|. Eingegeben wird abs(x) – Striche | werden nicht als Eingabe akzeptiert, weil verschachtelte Striche mehrdeutig sind."],
            keywords: ["betrag", "absolut", "betragsstriche"]),
        FunctionSpec(
            id: "floor", implementation: .math(.floor), title: "Abrunden", symbol: "⌊x⌋",
            summary: "Die größte ganze Zahl, die nicht größer als x ist. Bei negativen Zahlen geht es weiter weg von null.",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "floor(2.7)", result: "2", value: 2),
                       FormulaExample(input: "floor(-2.5)", result: "−3", value: -3)],
            graphExample: FormulaExample(input: "floor(x)", result: "Treppe – jede Stufe ein Ton"),
            notes: ["floor ist nicht frac: floor(2.7) = 2 ist der ganzzahlige Anteil nach unten, frac(2.7) = 0,7 der Rest.",
                    "Numerische Rundung (floor, round) ist etwas anderes als Skalenquantisierung auf Dur-, Moll- oder Pentatonik-Töne."],
            keywords: ["abrunden", "ganzzahl", "treppe", "stufe", "quantisieren"]),
        FunctionSpec(
            id: "ceil", implementation: .math(.ceil), title: "Aufrunden", symbol: "⌈x⌉",
            summary: "Die kleinste ganze Zahl, die nicht kleiner als x ist. Bei negativen Zahlen geht es in Richtung null.",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "ceil(2.1)", result: "3", value: 3),
                       FormulaExample(input: "ceil(-2.5)", result: "−2", value: -2)],
            graphExample: FormulaExample(input: "ceil(x)", result: "Treppe, Stufen rechts geschlossen"),
            keywords: ["aufrunden", "ganzzahl"]),
        FunctionSpec(
            id: "round", implementation: .math(.round), title: "Runden", symbol: "round x",
            summary: "Zur nächsten ganzen Zahl. Genau halbe Werte werden von der Null weg gerundet.",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "round(2.5)", result: "3", value: 3),
                       FormulaExample(input: "round(-2.5)", result: "−3", value: -3),
                       FormulaExample(input: "round(-2.4)", result: "−2", value: -2)],
            graphExample: FormulaExample(input: "round(2sin(x))", result: "quantisierte Sinuswelle mit 5 Stufen"),
            keywords: ["runden", "quantisieren"]),
        FunctionSpec(
            id: "frac", implementation: .math(.frac), title: "Nachkommaanteil", symbol: "frac x",
            summary: "x − floor(x): der Anteil hinter dem Komma, immer zwischen 0 (einschließlich) und 1 (ausschließlich). Ideal für Sägezähne und Wiederholungen.",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "frac(2.75)", result: "0,75", value: 0.75),
                       FormulaExample(input: "frac(-0.25)", result: "0,75", value: 0.75, note: "Nach der Definition x − floor(x) ist der Nachkommaanteil negativer Zahlen nicht negativ.")],
            graphExample: FormulaExample(input: "frac(x)", result: "Sägezahn mit Periode 1"),
            notes: ["frac ist nicht floor: frac liefert den Rest, floor den ganzzahligen Teil.",
                    "frac(x) entspricht mod(x, 1)."],
            keywords: ["nachkomma", "bruchteil", "rest", "sägezahn", "fraktional"]),
        FunctionSpec(
            id: "sign", implementation: .math(.sign), title: "Vorzeichen", symbol: "sgn x",
            summary: "−1 für negative, 0 für null, 1 für positive Werte.",
            arguments: [ArgumentSpec(name: "wert", meaning: "beliebige Zahl")],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "sign(-3)", result: "−1", value: -1),
                       FormulaExample(input: "sign(0)", result: "0", value: 0)],
            graphExample: FormulaExample(input: "sign(sin(x))", result: "Rechteckwelle"),
            notes: ["sign(sin(…)) als direktes Audiosignal ist nicht bandbegrenzt – für Rechteckklänge besser den Oszillator „Rechteck“ verwenden."],
            keywords: ["vorzeichen", "signum", "rechteck"]),
        FunctionSpec(
            id: "min", implementation: .math(.min), title: "Minimum", symbol: "min",
            summary: "Der kleinste der angegebenen Werte.",
            arguments: [ArgumentSpec(name: "wert1", meaning: "erster Wert"),
                        ArgumentSpec(name: "wert2", meaning: "zweiter Wert"),
                        ArgumentSpec(name: "weitere", meaning: "beliebig viele weitere Werte (optional)", isRepeatable: true)],
            minimumArguments: 2, maximumArguments: nil,
            examples: [FormulaExample(input: "min(2, 5)", result: "2", value: 2),
                       FormulaExample(input: "min(4, -1, 3)", result: "−1", value: -1)],
            graphExample: FormulaExample(input: "min(sin(x), 0.5)", result: "Sinus, oben bei 0,5 abgeschnitten"),
            notes: ["Ist ein Wert undefiniert, ist auch das Ergebnis undefiniert."],
            keywords: ["minimum", "kleinster"]),
        FunctionSpec(
            id: "max", implementation: .math(.max), title: "Maximum", symbol: "max",
            summary: "Der größte der angegebenen Werte.",
            arguments: [ArgumentSpec(name: "wert1", meaning: "erster Wert"),
                        ArgumentSpec(name: "wert2", meaning: "zweiter Wert"),
                        ArgumentSpec(name: "weitere", meaning: "beliebig viele weitere Werte (optional)", isRepeatable: true)],
            minimumArguments: 2, maximumArguments: nil,
            examples: [FormulaExample(input: "max(2, 5)", result: "5", value: 5)],
            graphExample: FormulaExample(input: "max(sin(x), 0)", result: "Einweggleichrichtung: nur positive Halbwellen"),
            keywords: ["maximum", "größter"]),
        FunctionSpec(
            id: "mod", implementation: .math(.mod), title: "Modulo (Rest)", symbol: "x mod m",
            summary: "Rest beim Teilen, immer zwischen 0 und dem Divisor: mod(wert, divisor) = wert − divisor·floor(wert/divisor). Damit lassen sich Muster periodisch wiederholen.",
            arguments: [ArgumentSpec(name: "wert", meaning: "zu teilender Wert"),
                        ArgumentSpec(name: "divisor", meaning: "Divisor (Periodenlänge)", allowed: "> 0, sonst undefiniert")],
            minimumArguments: 2, maximumArguments: 2,
            examples: [FormulaExample(input: "mod(7, 3)", result: "1", value: 1),
                       FormulaExample(input: "mod(-1, 4)", result: "3", value: 3, note: "Auch bei negativen Werten liegt das Ergebnis zwischen 0 und dem Divisor – wichtig für zyklischen Listenzugriff."),
                       FormulaExample(input: "mod(5.5, 2)", result: "1,5", value: 1.5)],
            graphExample: FormulaExample(input: "mod(x, 2)", result: "Sägezahn mit Periode 2"),
            notes: ["Für divisor ≤ 0 ist mod undefiniert (Lücke bzw. Stille).",
                    "Zyklischer Listenzugriff: notes[mod(n, len(notes))]."],
            keywords: ["modulo", "rest", "periodisch", "wiederholen", "zyklisch"]),
        FunctionSpec(
            id: "clip", aliases: ["clamp"], implementation: .math(.clip), title: "Begrenzen", symbol: "clip",
            summary: "Hält einen Wert zwischen Unter- und Obergrenze: kleinere Werte werden zur Untergrenze, größere zur Obergrenze.",
            arguments: [ArgumentSpec(name: "wert", meaning: "zu begrenzender Wert"),
                        ArgumentSpec(name: "untergrenze", meaning: "kleinster erlaubter Wert"),
                        ArgumentSpec(name: "obergrenze", meaning: "größter erlaubter Wert", allowed: "≥ untergrenze, sonst undefiniert")],
            minimumArguments: 3, maximumArguments: 3,
            examples: [FormulaExample(input: "clip(5, 0, 3)", result: "3", value: 3),
                       FormulaExample(input: "clip(-2, 0, 3)", result: "0", value: 0),
                       FormulaExample(input: "clamp(1.5, 0, 3)", result: "1,5 (Alias)", value: 1.5)],
            graphExample: FormulaExample(input: "clip(3tan(pi*(frac(x)-0.5)), -12, 24)", result: "begrenzter Tangens: Polstellen werden abgeschnitten"),
            notes: ["clamp ist ein gleichwertiger Name für clip.",
                    "Liegt die Untergrenze über der Obergrenze, ist das Ergebnis undefiniert."],
            keywords: ["begrenzen", "clamp", "clip", "kappen", "grenze"])
    ]

    /// Comparison helpers are operators, not functions; they are documented in `FormulaOperators`.
    static let comparisons: [FunctionSpec] = []

    static let conditions: [FunctionSpec] = [
        FunctionSpec(
            id: "if", implementation: .special(.ifElse), title: "Wenn – dann – sonst", symbol: "{ a falls c, sonst b",
            summary: "Prüft die Bedingung. Ist sie wahr (nicht 0), wird nur der Dann-Ausdruck berechnet, sonst nur der Sonst-Ausdruck. Der nicht gewählte Zweig wird nicht ausgewertet – eine ungültige Stelle darin stört nicht.",
            arguments: [ArgumentSpec(name: "bedingung", meaning: "Vergleich oder Zahl: wahr = nicht 0", kind: .condition),
                        ArgumentSpec(name: "dannAusdruck", meaning: "Ergebnis, wenn die Bedingung wahr ist", kind: .lazyExpression, mathPosition: "obere Zeile der geschweiften Klammer"),
                        ArgumentSpec(name: "sonstAusdruck", meaning: "Ergebnis, wenn die Bedingung falsch ist", kind: .lazyExpression, mathPosition: "untere Zeile („sonst“)")],
            minimumArguments: 3, maximumArguments: 3,
            examples: [FormulaExample(input: "if(2 > 1, 10, 20)", result: "10", value: 10),
                       FormulaExample(input: "if(-4 > 0, sqrt(-4), 0)", result: "0 – sqrt(-4) wird nicht berechnet", value: 0)],
            graphExample: FormulaExample(input: "if(x > 0, sqrt(x), -1)", result: "links −1, rechts die Wurzel"),
            notes: ["Ist die Bedingung selbst undefiniert, ist auch das Ergebnis undefiniert.",
                    "Vergleiche liefern 1 (wahr) oder 0 (falsch)."],
            keywords: ["wenn", "dann", "sonst", "bedingung", "if", "verzweigung"]),
        FunctionSpec(
            id: "piecewise", implementation: .special(.piecewise), title: "Fallunterscheidung", symbol: "{ … (abschnittsweise)",
            summary: "Abschnittsweise definierte Funktion: Die Bedingungen werden der Reihe nach geprüft, die erste wahre wählt ihren Ausdruck. Trifft keine zu, gilt der Sonst-Fall – das letzte Argument. Nur der gewählte Ausdruck wird berechnet.",
            arguments: [ArgumentSpec(name: "bedingung1", meaning: "erste Bedingung", kind: .condition, mathPosition: "rechts in der ersten Zeile („falls …“)", isRepeatable: true),
                        ArgumentSpec(name: "ausdruck1", meaning: "Wert, falls Bedingung 1 als erste wahr ist", kind: .lazyExpression, mathPosition: "links in der ersten Zeile", isRepeatable: true),
                        ArgumentSpec(name: "sonstAusdruck", meaning: "Wert, wenn keine Bedingung wahr ist (Pflicht, immer das letzte Argument)", kind: .lazyExpression, mathPosition: "letzte Zeile („sonst“)")],
            minimumArguments: 3, maximumArguments: nil,
            examples: [FormulaExample(input: "piecewise(3 < 2, 1, 3 < 5, 2, 3)", result: "2 – die erste Bedingung ist falsch, die zweite wahr", value: 2),
                       FormulaExample(input: "piecewise(1 > 2, 7, 9)", result: "9 (Sonst-Fall)", value: 9)],
            graphExample: FormulaExample(input: "piecewise(x < -2, -1, x < 2, x/2, 1)", result: "drei Abschnitte"),
            notes: ["Aufbau: piecewise(bedingung1, ausdruck1, bedingung2, ausdruck2, …, sonstAusdruck) – also immer eine ungerade Anzahl von Argumenten.",
                    "Die mathematische Darstellung zeigt eine geschweifte Klammer; eingegeben werden geschweifte Klammern nicht.",
                    "Der visuelle Editor „Fallunterscheidung“ erzeugt diese Schreibweise."],
            keywords: ["fallunterscheidung", "abschnittsweise", "stückweise", "piecewise", "geschweifte klammer", "fälle"])
    ]

    static let aggregates: [FunctionSpec] = [
        FunctionSpec(
            id: "sum", implementation: .special(.sum), title: "Summe", symbol: "Σ",
            summary: "Endliche Summe: Der Ausdruck wird für jeden ganzzahligen Wert der Laufvariable von start bis ende (einschließlich) berechnet und alles addiert.",
            arguments: [ArgumentSpec(name: "laufvariable", meaning: "Name der Zählvariable, beispielsweise i", kind: .identifier, mathPosition: "Unter dem Σ, links vom Gleichheitszeichen"),
                        ArgumentSpec(name: "start", meaning: "Erster ganzzahliger Wert", mathPosition: "Unter dem Σ, rechts vom Gleichheitszeichen"),
                        ArgumentSpec(name: "ende", meaning: "Letzter ganzzahliger Wert, einschließlich", mathPosition: "Über dem Σ"),
                        ArgumentSpec(name: "ausdruck", meaning: "Term, der für jeden Wert berechnet und addiert wird", kind: .lazyExpression, mathPosition: "Rechts neben dem Σ")],
            minimumArguments: 4, maximumArguments: 4,
            examples: [FormulaExample(input: "sum(i, 1, 5, i)", result: "1 + 2 + 3 + 4 + 5 = 15", value: 15,
                                      note: "Ohne x oder t ist das Ergebnis konstant. Als Funktion dargestellt ergibt sich y = 15.")],
            graphExample: FormulaExample(input: "sum(i, 1, 5, sin(i*x)/i)", result: "Fünf Sinusfunktionen mit unterschiedlichen Frequenzen und Gewichtungen werden addiert."),
            notes: ["Die Laufvariable gilt nur im Ausdruck (4. Argument); außerhalb und in start/ende ist sie unbekannt. Ein gleichnamiger äußerer Name wird im Ausdruck verdeckt.",
                    "Start und Ende müssen ganze Zahlen ergeben. Ist ende < start, ist die Summe leer und ergibt 0.",
                    "Höchstens 10 000 Durchläufe je Summe (zusammen höchstens 200 000 je Auswertung) – sonst ist das Ergebnis undefiniert.",
                    "Σ als Zeichen wird ebenfalls als sum erkannt: Σ(i, 1, 5, i)."],
            keywords: ["summe", "sigma", "addieren", "reihe", "fourier"]),
        FunctionSpec(
            id: "prod", implementation: .special(.prod), title: "Produkt", symbol: "Π",
            summary: "Endliches Produkt: Der Ausdruck wird für jeden ganzzahligen Wert der Laufvariable von start bis ende (einschließlich) berechnet und alles multipliziert.",
            arguments: [ArgumentSpec(name: "laufvariable", meaning: "Name der Zählvariable, beispielsweise i", kind: .identifier, mathPosition: "Unter dem Π, links vom Gleichheitszeichen"),
                        ArgumentSpec(name: "start", meaning: "Erster ganzzahliger Wert", mathPosition: "Unter dem Π, rechts vom Gleichheitszeichen"),
                        ArgumentSpec(name: "ende", meaning: "Letzter ganzzahliger Wert, einschließlich", mathPosition: "Über dem Π"),
                        ArgumentSpec(name: "ausdruck", meaning: "Term, der für jeden Wert berechnet und multipliziert wird", kind: .lazyExpression, mathPosition: "Rechts neben dem Π")],
            minimumArguments: 4, maximumArguments: 4,
            examples: [FormulaExample(input: "prod(i, 1, 4, i)", result: "1·2·3·4 = 24", value: 24)],
            graphExample: FormulaExample(input: "6*(1 + prod(k, 0, 2, (-1)^floor(2^k*x)))", result: "Walsh-Muster aus Rademacher-Funktionen"),
            notes: ["Scoping wie bei sum: Die Laufvariable gilt nur im Ausdruck.",
                    "Leerer Bereich (ende < start) ergibt 1.",
                    "Π als Zeichen wird ebenfalls als prod erkannt."],
            keywords: ["produkt", "pi groß", "multiplizieren", "walsh", "rademacher"])
    ]

    static let lists: [FunctionSpec] = [
        FunctionSpec(
            id: "len", implementation: .special(.len), title: "Listenlänge", symbol: "|L|",
            summary: "Anzahl der Elemente einer Liste.",
            arguments: [ArgumentSpec(name: "liste", meaning: "Name einer Liste oder Liste in eckigen Klammern", kind: .list)],
            minimumArguments: 1, maximumArguments: 1,
            examples: [FormulaExample(input: "len([0, 3, 7, 10])", result: "4", value: 4)],
            graphExample: nil,
            notes: ["Indizes laufen von 0 bis len(liste) − 1.",
                    "Zyklischer Zugriff: liste[mod(n, len(liste))]."],
            keywords: ["länge", "anzahl", "liste", "len"])
    ]
}

/// Operators and other syntax elements (documented in the guide, used by the lexer/parser).
enum FormulaOperators {
    struct Spec: Equatable, Sendable, Identifiable {
        var id: String
        var symbol: String
        var title: String
        /// All accepted spellings.
        var spellings: [String]
        var precedenceNote: String
        var summary: String
        var examples: [FormulaExample]
        var notes: [String] = []
        var keywords: [String] = []
    }

    static let all: [Spec] = [
        Spec(id: "plus", symbol: "+", title: "Addition", spellings: ["+"], precedenceNote: "niedrig, wie Minus",
             summary: "Addiert zwei Werte. Stimmen werden im Synthesizer nicht über + in einer Formel, sondern als getrennte Signale gemischt.",
             examples: [FormulaExample(input: "2 + 3", result: "5", value: 5)], keywords: ["plus", "addieren", "summe"]),
        Spec(id: "minus", symbol: "−", title: "Subtraktion und unäres Minus", spellings: ["-", "−"], precedenceNote: "Subtraktion niedrig; unäres Minus schwächer als ^",
             summary: "Zieht ab oder kehrt das Vorzeichen um. Wichtig: -x^2 bedeutet -(x^2), nicht (-x)^2.",
             examples: [FormulaExample(input: "10 - 4 - 3", result: "3 (von links nach rechts)", value: 3),
                        FormulaExample(input: "-3^2", result: "−9, denn -(3^2)", value: -9),
                        FormulaExample(input: "(-3)^2", result: "9", value: 9)],
             keywords: ["minus", "subtrahieren", "negativ", "vorzeichen"]),
        Spec(id: "times", symbol: "·", title: "Multiplikation", spellings: ["*", "·", "×"], precedenceNote: "mittel, wie Division",
             summary: "Multipliziert. Eingegeben wird der Stern *; in der gedruckten Darstellung erscheint der Malpunkt ·. Auch × und · werden als Eingabe akzeptiert.",
             examples: [FormulaExample(input: "4 * 2.5", result: "10", value: 10)],
             notes: ["Gedrucktes Malzeichen (·, ×) und eingegebener Stern * bedeuten dasselbe."],
             keywords: ["mal", "multiplizieren", "stern", "malpunkt"]),
        Spec(id: "implicit", symbol: "2x", title: "Implizite Multiplikation", spellings: ["2x", "2pi", "x(x+1)"], precedenceNote: "wie *, aber eine Potenz bindet stärker: 2x^2 = 2·(x^2)",
             summary: "Zwischen Zahl und Name, zwischen Namen und vor Klammern darf das * fehlen: 2x, 2pi, 2sin(x), (x+1)(x-1). Ein zusammenhängender Buchstabenblock wird zuerst als ganzer Name gelesen; nur wenn es diesen Namen nicht gibt, wird er in bekannte Namen zerlegt (2pift = 2·pi·f·t). Ist die Zerlegung mehrdeutig, zeigt der Editor eine Warnung – dann * schreiben.",
             examples: [FormulaExample(input: "2(3+1)", result: "8", value: 8),
                        FormulaExample(input: "2x^2", result: "18 bei x = 3", value: 18, x: 3)],
             notes: ["Vor einer Zahl ist keine implizite Multiplikation erlaubt: „x 2“ ist ein Fehler – x*2 schreiben.",
                     "Mehrbuchstabige Namen wie tau oder localTime sind ein Name, nicht t·a·u."],
             keywords: ["implizit", "ohne stern", "multiplikation", "zerlegung"]),
        Spec(id: "divide", symbol: "÷", title: "Division und Bruch", spellings: ["/", "÷"], precedenceNote: "mittel, von links nach rechts: 16/4/2 = 2",
             summary: "Teilt. Die gedruckte Bruchdarstellung mit Bruchstrich entspricht einer Division mit / – Zähler und Nenner müssen dabei geklammert werden: (a+b)/(c+d).",
             examples: [FormulaExample(input: "16 / 4 / 2", result: "2", value: 2),
                        FormulaExample(input: "(1 + 2) / (3 + 3)", result: "0,5", value: 0.5)],
             notes: ["1/x ist bei x = 0 undefiniert (Polstelle): Lücke im Graphen, Stille im Klang.",
                     "a/b*c bedeutet (a/b)·c, nicht a/(b·c)."],
             keywords: ["geteilt", "division", "bruch", "bruchstrich"]),
        Spec(id: "power", symbol: "xⁿ", title: "Potenz", spellings: ["^", "²", "³"], precedenceNote: "höchste Stufe, rechtsassoziativ: 2^3^2 = 2^(3^2)",
             summary: "Basis hoch Exponent. Potenzen werden von rechts gebunden. ² und ³ werden als ^2 und ^3 gelesen.",
             examples: [FormulaExample(input: "2^3^2", result: "512, denn 2^(3^2) = 2^9", value: 512),
                        FormulaExample(input: "2^-1", result: "0,5", value: 0.5),
                        FormulaExample(input: "(-1)^3", result: "−1 (ganzzahliger Exponent, exakt)", value: -1)],
             notes: ["Negative Basis mit nicht ganzzahligem Exponenten ist undefiniert.",
                     "e^x und exp(x) sind gleichwertig."],
             keywords: ["hoch", "potenz", "exponent", "quadrat"]),
        Spec(id: "parentheses", symbol: "( )", title: "Klammern und Rangfolge", spellings: ["(", ")"], precedenceNote: "Klammern zuerst",
             summary: "Rangfolge von stark nach schwach: Klammern und Funktionsaufrufe, Index [ ], Potenz ^, unäres Minus, * und / (auch implizit), + und −, Vergleiche, not, and, or.",
             examples: [FormulaExample(input: "1 + 2 * 3", result: "7", value: 7),
                        FormulaExample(input: "(1 + 2) * 3", result: "9", value: 9)],
             keywords: ["klammer", "rangfolge", "reihenfolge", "punkt vor strich"]),
        Spec(id: "decimal", symbol: ".", title: "Dezimalpunkt und Argumenttrenner", spellings: [".", ",", ";"], precedenceNote: "–",
             summary: "Dezimalzahlen werden mit Punkt geschrieben: 0.5. Das Komma trennt Argumente in Funktionen und Elemente in Listen: min(0.5, 2). Ein Semikolon wird wie ein Komma behandelt.",
             examples: [FormulaExample(input: "min(0.5, 2)", result: "0,5", value: 0.5)],
             notes: ["Die Anzeige der App verwendet das deutsche Dezimalkomma (0,5), die Formeleingabe den Punkt.",
                     "„0,5“ außerhalb einer Funktion wird als Fehler gemeldet und nicht erraten."],
             keywords: ["komma", "punkt", "dezimal", "trennzeichen", "semikolon"]),
        Spec(id: "comparison", symbol: "< ≤ > ≥ = ≠", title: "Vergleiche", spellings: ["<", "<=", ">", ">=", "==", "!=", "≤", "≥", "≠"], precedenceNote: "schwächer als + und −",
             summary: "Vergleiche liefern 1 (wahr) oder 0 (falsch): <, <=, >, >=, == (gleich) und != (ungleich). Ketten wie 0 < x < 1 werden nicht erraten – schreibe (0 < x) and (x < 1).",
             examples: [FormulaExample(input: "3 > 2", result: "1 (wahr)", value: 1),
                        FormulaExample(input: "2 == 3", result: "0 (falsch)", value: 0),
                        FormulaExample(input: "2 != 3", result: "1", value: 1)],
             notes: ["== vergleicht exakt. Für berechnete Werte round() verwenden, z. B. round(x) == 2.",
                     "Ein einzelnes = steht nur in Definitionen (k = 7)."],
             keywords: ["vergleich", "kleiner", "größer", "gleich", "ungleich", "bedingung"]),
        Spec(id: "logic", symbol: "∧ ∨ ¬", title: "and, or, not", spellings: ["and", "or", "not"], precedenceNote: "not vor and vor or",
             summary: "Verknüpft Bedingungen: and (beide wahr), or (mindestens eine wahr), not (Umkehrung). Ausgewertet wird von links; ist das Ergebnis schon klar, wird die rechte Seite nicht berechnet.",
             examples: [FormulaExample(input: "(2 > 1) and (3 > 4)", result: "0", value: 0),
                        FormulaExample(input: "(2 > 1) or (3 > 4)", result: "1", value: 1),
                        FormulaExample(input: "not(2 > 1)", result: "0", value: 0)],
             keywords: ["und", "oder", "nicht", "logik", "and", "or", "not"]),
        Spec(id: "constants", symbol: "π e", title: "Konstanten pi und e", spellings: ["pi", "π", "e"], precedenceNote: "–",
             summary: "pi (oder π) ≈ 3,14159 und die Eulersche Zahl e ≈ 2,71828. Konstanten können nicht neu definiert werden.",
             examples: [FormulaExample(input: "2pi", result: "≈ 6,2832", value: 2 * Double.pi),
                        FormulaExample(input: "e^1", result: "≈ 2,7183", value: M_E)],
             notes: ["Griechische Buchstaben werden als Namen gelesen: π → pi, τ → tau, ω → omega, φ → phi, δ → delta. tau und omega sind keine Konstanten, sondern freie Namen für eigene Definitionen."],
             keywords: ["pi", "π", "euler", "konstante", "griechisch", "tau", "omega"]),
        Spec(id: "list", symbol: "[ ]", title: "Listen und Index", spellings: ["[", "]"], precedenceNote: "Index bindet am stärksten",
             summary: "Eine Liste steht in eckigen Klammern: notes = [0, 3, 7, 10]. notes[i] liefert das Element mit nullbasiertem Index i (0 ist das erste). Ein Index außerhalb von 0 … len − 1 oder ein nicht ganzzahliger Index ist undefiniert.",
             examples: [FormulaExample(input: "[0, 3, 7, 10][2]", result: "7", value: 7),
                        FormulaExample(input: "[0, 3, 7, 10][mod(-1, 4)]", result: "10 (letztes Element, zyklisch)", value: 10)],
             notes: ["Zyklischer Zugriff ausdrücklich mit mod: notes[mod(n, len(notes))].",
                     "Negative Indizes zählen nicht vom Ende – sie sind undefiniert.",
                     "Listen können nicht verschachtelt und nicht direkt in Rechnungen verwendet werden."],
             keywords: ["liste", "index", "eckige klammer", "noten", "array"]),
        Spec(id: "definition", symbol: "=", title: "Definitionen und mehrzeilige Formeln", spellings: ["=", "#"], precedenceNote: "eine Definition pro Zeile",
             summary: "Im erweiterten Editor steht jede Definition in einer eigenen Zeile: Zwischenwerte (p = x + 8), Listen (notes = [0, 3, 7]) und Hilfsfunktionen (r(x) = frac(2*x)). Die Ausgabe ist die Zeile ohne Gleichheitszeichen – oder die Definition von y bzw. f(x). # leitet einen Kommentar ein.",
             examples: [FormulaExample(input: "k = 3\nk^2 + 1", result: "10", value: 10)],
             notes: ["Die Reihenfolge der Zeilen ist egal; zyklische Definitionen (a = b, b = a) werden erkannt.",
                     "Parameter einer Hilfsfunktion gelten nur in ihrem Rumpf und verdecken gleichnamige Namen.",
                     "Eingebaute Variablen, Konstanten und Funktionsnamen können nicht neu definiert werden."],
             keywords: ["definition", "zwischenwert", "hilfsfunktion", "mehrzeilig", "kommentar", "variable"])
    ]
}
