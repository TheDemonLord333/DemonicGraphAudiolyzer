import Foundation

/// A parsed source that contributes definitions (and possibly the output) to a formula.
struct FormulaSourceProgram: Equatable, Sendable {
    var program: SyntaxProgram
    /// Shown in error messages; nil for the edited formula itself.
    var sourceName: String?
}

/// Turns syntax programs into an evaluable `FormulaNode`:
/// resolves names and scopes, checks types (number vs. list), detects cyclic definitions,
/// inlines helper functions and binds definitions that are used more than once.
struct FormulaBinder {
    struct Result: Equatable, Sendable {
        var root: FormulaNode
        var warnings: [FormulaWarning]
        var autoParameters: [String]
    }

    private struct Definition {
        var statement: SyntaxStatement
        var sourceName: String?
        var multiLine: Bool
    }

    private var definitions: [String: Definition] = [:]
    private let environment: FormulaEnvironment
    private let fixedVariables: Set<FormulaVariable>
    private let autoParameterValues: [String: Double]
    private var nextSlot = 0
    private var definitionSlots: [String: Int] = [:]
    private var slotDefinitions: [Int: String] = [:]
    private var definitionTrees: [String: FormulaNode] = [:]
    private var listElements: [String: [FormulaNode]] = [:]
    /// Definitions and functions currently being resolved (cycle detection).
    private var resolving: [String] = []
    private var scopes: [[String: FormulaNode]] = []

    private init(environment: FormulaEnvironment, fixedVariables: Set<FormulaVariable>, autoParameterValues: [String: Double]) {
        self.environment = environment
        self.fixedVariables = fixedVariables
        self.autoParameterValues = autoParameterValues
    }

    /// Binds a single program (classic modes).
    static func bind(_ program: SyntaxProgram, environment: FormulaEnvironment) throws -> Result {
        try bind(main: FormulaSourceProgram(program: program, sourceName: environment.sourceName), prelude: [],
                 environment: environment, fixedVariables: [.a, .b, .c])
    }

    /// Binds the output of `main`; definitions of `prelude` (project and voice definitions,
    /// parameters) are visible. `fixedVariables` are constant per rendering (used to decide inlining).
    static func bind(main: FormulaSourceProgram, prelude: [FormulaSourceProgram], environment: FormulaEnvironment,
                     fixedVariables: Set<FormulaVariable>, autoParameterValues: [String: Double] = [:]) throws -> Result {
        var binder = FormulaBinder(environment: environment, fixedVariables: fixedVariables, autoParameterValues: autoParameterValues)
        for source in prelude + [main] {
            for statement in source.program.definitions {
                guard let name = statement.definedName else { continue }
                binder.definitions[name] = Definition(statement: statement, sourceName: source.sourceName,
                                                      multiLine: source.program.lineCount > 1)
            }
        }
        let root = try binder.bindOutput(of: main)
        let warnings = (prelude + [main]).flatMap { $0.program.warnings }
        let autoParameters = (prelude + [main]).flatMap { $0.program.autoParameters }
        return Result(root: root, warnings: warnings, autoParameters: autoParameters)
    }

    /// Only checks definition blocks (no output): types, cycles, helper function bodies.
    static func check(_ source: FormulaSourceProgram, prelude: [FormulaSourceProgram], environment: FormulaEnvironment) throws {
        var binder = FormulaBinder(environment: environment, fixedVariables: [], autoParameterValues: [:])
        for program in prelude + [source] {
            for statement in program.program.definitions {
                guard let name = statement.definedName else { continue }
                binder.definitions[name] = Definition(statement: statement, sourceName: program.sourceName,
                                                      multiLine: program.program.lineCount > 1)
            }
        }
        try binder.checkAllDefinitions(in: source)
    }

    // MARK: - Output

    private mutating func bindOutput(of main: FormulaSourceProgram) throws -> FormulaNode {
        try checkAllDefinitions(in: main)
        guard let output = main.program.outputStatement else {
            throw FormulaError(kind: .missingOutput, message: "Es fehlt die Ausgabezeile.", range: nil,
                               hint: "Die Ausgabe ist die Zeile ohne Gleichheitszeichen.", sourceName: main.sourceName)
        }
        var outputTree: FormulaNode
        switch output.kind {
        case .output, .value:
            outputTree = try located(output, main.sourceName, main.program.lineCount > 1) {
                try $0.resolveNumber(output.expression)
            }
        case .function(let name, _):
            // Legacy `f(x) = …`: the output is f(x).
            outputTree = try located(output, main.sourceName, main.program.lineCount > 1) {
                try $0.inlineCall(name, arguments: [.variable(.x)], range: output.nameRange ?? output.expression.range)
            }
        }
        // Resolve every definition reachable from the output.
        var pending = Array(referencedDefinitions(in: outputTree))
        var reachable = Set<String>()
        while let name = pending.popLast() {
            guard !reachable.contains(name) else { continue }
            reachable.insert(name)
            let tree = try valueTree(name)
            pending += referencedDefinitions(in: tree)
        }
        let order = try topologicalOrder(reachable)

        // Decide which definitions are inlined (used once or constant) and which are bound.
        var total: [String: Int] = [:]
        for name in reachable { total[name] = occurrences(of: name, in: outputTree) }
        var inline: [String: Bool] = [:]
        var constant: [String: Bool] = [:]
        for name in order {
            let tree = definitionTrees[name]!
            let references = referencedDefinitions(in: tree)
            constant[name] = isConstant(tree) && references.allSatisfy { constant[$0] == true }
        }
        for name in order.reversed() {
            let count = total[name] ?? 0
            inline[name] = count <= 1 || constant[name] == true || isTrivial(definitionTrees[name]!)
            let tree = definitionTrees[name]!
            for dependency in referencedDefinitions(in: tree) {
                total[dependency, default: 0] += occurrences(of: dependency, in: tree) * (inline[name]! ? max(count, 1) : 1)
            }
        }

        var root = materialize(outputTree, inline: inline)
        for name in order.reversed() where inline[name] == false {
            root = .binding(local: definitionSlots[name]!, value: materialize(definitionTrees[name]!, inline: inline), body: root)
        }
        try checkLimits(root, output: output, main: main)
        return renumberLocals(root)
    }

    private func checkLimits(_ root: FormulaNode, output: SyntaxStatement, main: FormulaSourceProgram) throws {
        if root.nodeCount > FormulaLimits.maximumNodes {
            throw FormulaError(kind: .tooComplex,
                               message: "Die Formel ist zu komplex (mehr als \(FormulaLimits.maximumNodes) Knoten nach dem Einsetzen der Hilfsfunktionen).",
                               range: output.expression.range, hint: "Verwende Zwischenwerte statt mehrfach eingesetzter Hilfsfunktionen.",
                               line: main.program.lineCount > 1 ? output.line : nil, sourceName: main.sourceName)
        }
        var problem: String?
        root.visit { node in
            guard problem == nil, case .aggregate(let kind, _, let start, let end, _) = node,
                  start.usedVariables.isEmpty, start.freeLocals.isEmpty,
                  end.usedVariables.isEmpty, end.freeLocals.isEmpty else { return }
            let first = start.evaluate(inputs: [Double](repeating: 0, count: FormulaVariable.allCases.count))
            let last = end.evaluate(inputs: [Double](repeating: 0, count: FormulaVariable.allCases.count))
            if MathSemantics.integer(first) == nil || MathSemantics.integer(last) == nil {
                problem = "Start und Ende von \(kind.rawValue) müssen ganze Zahlen sein."
            } else if case .undefined = MathSemantics.loopBounds(first, last) {
                problem = "\(kind.rawValue) hat zu viele Durchläufe (höchstens \(FormulaLimits.iterationsPerLoop))."
            }
        }
        if let problem {
            throw FormulaError(kind: .invalidArgument, message: problem, range: output.expression.range, hint: nil,
                               line: main.program.lineCount > 1 ? output.line : nil, sourceName: main.sourceName)
        }
    }

    /// Resolves all definitions of a source so that errors in unused lines are reported, too.
    private mutating func checkAllDefinitions(in source: FormulaSourceProgram) throws {
        for statement in source.program.definitions {
            guard let name = statement.definedName else { continue }
            switch statement.kind {
            case .value:
                if statement.isList {
                    _ = try listTree(name)
                } else {
                    _ = try valueTree(name)
                    _ = try topologicalOrder(Set([name]).union(allReachable(from: name)))
                }
            case .function(_, let parameters):
                // Body with dummy locals for the parameters.
                var scope: [String: FormulaNode] = [:]
                for parameter in parameters {
                    scope[parameter] = .local(allocateSlot())
                }
                let definition = definitions[name]!
                resolving.append(name)
                scopes.append(scope)
                defer {
                    scopes.removeLast()
                    resolving.removeLast()
                }
                _ = try located(statement, definition.sourceName, definition.multiLine) {
                    try $0.resolveNumber(statement.expression)
                }
            case .output:
                break
            }
        }
    }

    private mutating func allReachable(from name: String) throws -> Set<String> {
        var result = Set<String>()
        var pending = Array(referencedDefinitions(in: try valueTree(name)))
        while let next = pending.popLast() {
            guard !result.contains(next) else { continue }
            result.insert(next)
            pending += referencedDefinitions(in: try valueTree(next))
        }
        return result
    }

    // MARK: - Definitions

    private mutating func allocateSlot() -> Int {
        defer { nextSlot += 1 }
        return nextSlot
    }

    private mutating func slot(forDefinition name: String) -> Int {
        if let slot = definitionSlots[name] { return slot }
        let slot = allocateSlot()
        definitionSlots[name] = slot
        slotDefinitions[slot] = name
        return slot
    }

    /// Resolved tree of a value definition; references to other definitions stay as their slots.
    private mutating func valueTree(_ name: String) throws -> FormulaNode {
        if let tree = definitionTrees[name] { return tree }
        guard let definition = definitions[name] else {
            throw FormulaError(kind: .unknownName, message: "Unbekannter Name „\(name)“.", range: nil, hint: nil)
        }
        if resolving.contains(name) {
            throw cycleError(name, definition: definition)
        }
        resolving.append(name)
        let savedScopes = scopes
        scopes = []
        defer {
            scopes = savedScopes
            resolving.removeLast()
        }
        let tree = try located(definition.statement, definition.sourceName, definition.multiLine) {
            try $0.resolveNumber(definition.statement.expression)
        }
        definitionTrees[name] = tree
        return tree
    }

    private mutating func listTree(_ name: String) throws -> [FormulaNode] {
        if let elements = listElements[name] { return elements }
        guard let definition = definitions[name], case .list(let syntaxElements, _) = definition.statement.expression else {
            throw FormulaError(kind: .typeMismatch, message: "„\(name)“ ist keine Liste.", range: nil, hint: nil)
        }
        if resolving.contains(name) {
            throw cycleError(name, definition: definition)
        }
        resolving.append(name)
        let savedScopes = scopes
        scopes = []
        defer {
            scopes = savedScopes
            resolving.removeLast()
        }
        let elements = try located(definition.statement, definition.sourceName, definition.multiLine) { binder in
            try syntaxElements.map { try binder.resolveNumber($0) }
        }
        listElements[name] = elements
        return elements
    }

    private func cycleError(_ name: String, definition: Definition) -> FormulaError {
        var chain = resolving
        if let start = chain.firstIndex(of: name) {
            chain = Array(chain[start...])
        }
        chain.append(name)
        return FormulaError(kind: .cyclicDefinition,
                            message: "Zyklische Definition: \(chain.joined(separator: " → ")).",
                            range: definition.statement.nameRange,
                            hint: "Eine Definition darf sich nicht (über Umwege) selbst verwenden.",
                            line: definition.multiLine ? definition.statement.line : nil,
                            sourceName: definition.sourceName)
    }

    private func topologicalOrder(_ names: Set<String>) throws -> [String] {
        var order: [String] = []
        var state: [String: Int] = [:]   // 1 = visiting, 2 = done
        func visit(_ name: String, path: [String]) throws {
            if state[name] == 2 { return }
            if state[name] == 1 {
                let definition = definitions[name]!
                var chain = path
                if let start = chain.firstIndex(of: name) { chain = Array(chain[start...]) }
                chain.append(name)
                throw FormulaError(kind: .cyclicDefinition,
                                   message: "Zyklische Definition: \(chain.joined(separator: " → ")).",
                                   range: definition.statement.nameRange,
                                   hint: "Eine Definition darf sich nicht (über Umwege) selbst verwenden.",
                                   line: definition.multiLine ? definition.statement.line : nil,
                                   sourceName: definition.sourceName)
            }
            state[name] = 1
            if let tree = definitionTrees[name] {
                for dependency in referencedDefinitions(in: tree).sorted() where names.contains(dependency) {
                    try visit(dependency, path: path + [name])
                }
            }
            state[name] = 2
            order.append(name)
        }
        for name in names.sorted() {
            try visit(name, path: [])
        }
        return order
    }

    private func referencedDefinitions(in tree: FormulaNode) -> Set<String> {
        var result = Set<String>()
        tree.visit { node in
            if case .local(let slot) = node, let name = slotDefinitions[slot] {
                result.insert(name)
            }
        }
        return result
    }

    private func occurrences(of name: String, in tree: FormulaNode) -> Int {
        guard let slot = definitionSlots[name] else { return 0 }
        var count = 0
        tree.visit { node in
            if case .local(slot) = node { count += 1 }
        }
        return count
    }

    private func isConstant(_ tree: FormulaNode) -> Bool {
        guard tree.usedVariables.isSubset(of: fixedVariables) else { return false }
        return tree.freeLocals.allSatisfy { slotDefinitions[$0] != nil }
    }

    private func isTrivial(_ tree: FormulaNode) -> Bool {
        switch tree {
        case .number, .variable: return true
        case .local(let slot): return slotDefinitions[slot] == nil
        default: return false
        }
    }

    private func materialize(_ tree: FormulaNode, inline: [String: Bool]) -> FormulaNode {
        map(tree) { node in
            if case .local(let slot) = node, let name = slotDefinitions[slot], inline[name] == true {
                return materialize(definitionTrees[name]!, inline: inline)
            }
            return nil
        }
    }

    /// Renumbers local slots densely (0, 1, 2, …) in order of first appearance.
    private func renumberLocals(_ tree: FormulaNode) -> FormulaNode {
        var mapping: [Int: Int] = [:]
        func slot(_ old: Int) -> Int {
            if let new = mapping[old] { return new }
            let new = mapping.count
            mapping[old] = new
            return new
        }
        func rewrite(_ node: FormulaNode) -> FormulaNode {
            switch node {
            case .number, .variable: return node
            case .local(let old): return .local(slot(old))
            case .negate(let operand): return .negate(rewrite(operand))
            case .not(let operand): return .not(rewrite(operand))
            case .binary(let op, let lhs, let rhs): return .binary(op, rewrite(lhs), rewrite(rhs))
            case .call(let function, let arguments): return .call(function, arguments.map(rewrite))
            case .conditional(let c, let a, let b): return .conditional(rewrite(c), rewrite(a), rewrite(b))
            case .piecewise(let parts): return .piecewise(parts.map(rewrite))
            case .aggregate(let kind, let old, let start, let end, let body):
                let newSlot = slot(old)
                return .aggregate(kind, local: newSlot, start: rewrite(start), end: rewrite(end), body: rewrite(body))
            case .element(let elements, let index): return .element(elements.map(rewrite), index: rewrite(index))
            case .binding(let old, let value, let body):
                let newSlot = slot(old)
                return .binding(local: newSlot, value: rewrite(value), body: rewrite(body))
            }
        }
        return rewrite(tree)
    }

    /// Bottom-up replacement helper: `transform` returns a replacement or nil to recurse.
    private func map(_ node: FormulaNode, _ transform: (FormulaNode) -> FormulaNode?) -> FormulaNode {
        if let replaced = transform(node) { return replaced }
        switch node {
        case .number, .variable, .local: return node
        case .negate(let operand): return .negate(map(operand, transform))
        case .not(let operand): return .not(map(operand, transform))
        case .binary(let op, let lhs, let rhs): return .binary(op, map(lhs, transform), map(rhs, transform))
        case .call(let function, let arguments): return .call(function, arguments.map { map($0, transform) })
        case .conditional(let c, let a, let b): return .conditional(map(c, transform), map(a, transform), map(b, transform))
        case .piecewise(let parts): return .piecewise(parts.map { map($0, transform) })
        case .aggregate(let kind, let slot, let start, let end, let body):
            return .aggregate(kind, local: slot, start: map(start, transform), end: map(end, transform), body: map(body, transform))
        case .element(let elements, let index):
            return .element(elements.map { map($0, transform) }, index: map(index, transform))
        case .binding(let slot, let value, let body):
            return .binding(local: slot, value: map(value, transform), body: map(body, transform))
        }
    }

    // MARK: - Expressions

    /// Adds line and source to errors thrown while resolving a statement.
    private mutating func located<T>(_ statement: SyntaxStatement, _ sourceName: String?, _ multiLine: Bool,
                                     _ body: (inout FormulaBinder) throws -> T) throws -> T {
        do {
            return try body(&self)
        } catch var error as FormulaError {
            if error.sourceName == nil { error.sourceName = sourceName }
            if error.line == nil, multiLine { error.line = statement.line }
            throw error
        }
    }

    private mutating func resolveNumber(_ expression: SyntaxExpression) throws -> FormulaNode {
        switch expression {
        case .number(let value, _):
            return .number(value)
        case .name(let reference, let spelling, let range):
            return try resolveName(reference, spelling: spelling, range: range)
        case .negate(let operand, _):
            return .negate(try resolveNumber(operand))
        case .not(let operand, _):
            return .not(try resolveNumber(operand))
        case .binary(let op, let lhs, let rhs, _, _):
            return .binary(op, try resolveNumber(lhs), try resolveNumber(rhs))
        case .group(let inner, _):
            return try resolveNumber(inner)
        case .call(let reference, let spelling, let arguments, let range):
            return try resolveCall(reference, spelling: spelling, arguments: arguments, range: range)
        case .list(_, let range):
            throw FormulaError(kind: .typeMismatch, message: "Eine Liste kann nicht direkt verrechnet werden.", range: range,
                               hint: "Greife mit [index] auf ein Element zu, z. B. [0, 3, 7][i].")
        case .index(let base, let index, _):
            let elements = try resolveList(base)
            return .element(elements, index: try resolveNumber(index))
        }
    }

    private mutating func resolveName(_ reference: NameReference, spelling: String, range: SourceRange) throws -> FormulaNode {
        switch reference {
        case .constant(let constant):
            return .number(constant.value)
        case .variable(let variable):
            return .variable(variable)
        case .local(let name):
            for scope in scopes.reversed() {
                if let node = scope[name] { return node }
            }
            throw FormulaError(kind: .unknownName, message: "„\(name)“ ist hier nicht definiert.", range: range,
                               hint: "Eine Laufvariable gilt nur im Ausdruck (4. Argument) ihrer Summe bzw. ihres Produkts.")
        case .autoParameter(let name):
            return .number(autoParameterValues[name] ?? 1)
        case .definition(let name):
            guard let definition = definitions[name] else {
                throw FormulaError(kind: .unknownName, message: "Unbekannter Name „\(name)“.", range: range, hint: nil)
            }
            switch definition.statement.kind {
            case .value:
                if definition.statement.isList {
                    throw FormulaError(kind: .typeMismatch, message: "„\(name)“ ist eine Liste.", range: range,
                                       hint: "Verwende \(name)[i] für ein Element oder len(\(name)) für die Länge.")
                }
                if resolving.contains(name) {
                    throw cycleError(name, definition: definition)
                }
                _ = try valueTree(name)
                return .local(slot(forDefinition: name))
            case .function:
                throw FormulaError(kind: .functionNeedsParenthesis, message: "Die Hilfsfunktion „\(name)“ braucht Argumente in Klammern.",
                                   range: range, hint: "Schreibe z. B. \(name)(x).")
            case .output:
                throw FormulaError(kind: .unknownName, message: "Unbekannter Name „\(name)“.", range: range, hint: nil)
            }
        case .function(let id):
            throw FormulaError(kind: .functionNeedsParenthesis, message: "Nach „\(id)“ wird eine Klammer erwartet.", range: range,
                               hint: "Schreibe z. B. \(id)(x).")
        }
    }

    private mutating func resolveList(_ expression: SyntaxExpression) throws -> [FormulaNode] {
        switch expression {
        case .list(let elements, _):
            return try elements.map { try resolveNumber($0) }
        case .name(.definition(let name), _, let range):
            guard let definition = definitions[name], definition.statement.isList else {
                throw FormulaError(kind: .typeMismatch, message: "„\(name)“ ist keine Liste.", range: range,
                                   hint: "Listen werden mit eckigen Klammern definiert: \(name) = [0, 3, 7].")
            }
            return try listTree(name)
        case .group(let inner, _):
            return try resolveList(inner)
        default:
            throw FormulaError(kind: .typeMismatch, message: "Hier wird eine Liste erwartet.", range: expression.range,
                               hint: "Beispiel: notes[2] oder len(notes) mit notes = [0, 3, 7].")
        }
    }

    private mutating func resolveCall(_ reference: NameReference, spelling: String, arguments: [SyntaxExpression], range: SourceRange) throws -> FormulaNode {
        switch reference {
        case .definition(let name):
            let resolved = try arguments.map { try resolveNumber($0) }
            return try inlineCall(name, arguments: resolved, range: range)
        case .function(let id):
            guard let spec = FormulaCatalog.function(named: id) else {
                throw FormulaError(kind: .unknownName, message: "Unbekannte Funktion „\(spelling)“.", range: range, hint: nil)
            }
            switch spec.implementation {
            case .math(let function):
                return .call(function, try arguments.map { try resolveNumber($0) })
            case .special(.ifElse):
                return .conditional(try resolveNumber(arguments[0]), try resolveNumber(arguments[1]), try resolveNumber(arguments[2]))
            case .special(.piecewise):
                return .piecewise(try arguments.map { try resolveNumber($0) })
            case .special(.len):
                return .number(Double(try resolveList(arguments[0]).count))
            case .special(.sum), .special(.prod):
                guard case .name(.local(let variable), _, _) = arguments[0] else {
                    throw FormulaError(kind: .invalidArgument, message: "Das erste Argument muss der Name der Laufvariable sein.",
                                       range: arguments[0].range, hint: "Syntax: \(spec.syntax).")
                }
                let start = try resolveNumber(arguments[1])
                let end = try resolveNumber(arguments[2])
                let loopSlot = allocateSlot()
                scopes.append([variable: .local(loopSlot)])
                defer { scopes.removeLast() }
                let body = try resolveNumber(arguments[3])
                return .aggregate(spec.implementation == .special(.sum) ? .sum : .prod,
                                  local: loopSlot, start: start, end: end, body: body)
            }
        default:
            throw FormulaError(kind: .unknownName, message: "„\(spelling)“ ist keine Funktion.", range: range, hint: nil)
        }
    }

    /// Inlines a helper function: parameters are substituted directly (simple arguments) or
    /// bound to fresh local slots.
    private mutating func inlineCall(_ name: String, arguments: [FormulaNode], range: SourceRange) throws -> FormulaNode {
        guard let definition = definitions[name], case .function(_, let parameters) = definition.statement.kind else {
            throw FormulaError(kind: .unknownName, message: "Unbekannte Funktion „\(name)“.", range: range, hint: nil)
        }
        guard parameters.count == arguments.count else {
            throw FormulaError(kind: .wrongArgumentCount,
                               message: "„\(name)“ erwartet \(parameters.count) Argumente, gefunden: \(arguments.count).",
                               range: range, hint: nil)
        }
        if resolving.contains(name) {
            throw cycleError(name, definition: definition)
        }
        var scope: [String: FormulaNode] = [:]
        var bindings: [(Int, FormulaNode)] = []
        for (parameter, argument) in zip(parameters, arguments) {
            switch argument {
            case .number, .variable:
                scope[parameter] = argument
            case .local(let slot) where slotDefinitions[slot] == nil:
                scope[parameter] = argument
            default:
                let slot = allocateSlot()
                bindings.append((slot, argument))
                scope[parameter] = .local(slot)
            }
        }
        resolving.append(name)
        let savedScopes = scopes
        // The body sees its parameters and global names – not the caller's locals.
        scopes = [scope]
        defer {
            scopes = savedScopes
            resolving.removeLast()
        }
        var body = try located(definition.statement, definition.sourceName, definition.multiLine) {
            try $0.resolveNumber(definition.statement.expression)
        }
        for (slot, value) in bindings.reversed() {
            body = .binding(local: slot, value: value, body: body)
        }
        return body
    }
}
