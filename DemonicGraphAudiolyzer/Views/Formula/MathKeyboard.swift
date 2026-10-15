import SwiftUI
import UIKit

/// A key of the mathematical supplementary keyboard.
struct MathKey: Identifiable, Hashable {
    enum Action: Hashable {
        /// Inserts text; afterwards the cursor moves `cursorBack` characters to the left.
        case insert(String, cursorBack: Int)
        case moveLeft
        case moveRight
        case deleteBackward
        case done
    }

    let id: String
    let title: String
    let accessibilityName: String
    let action: Action
    var isFunction = false

    static func text(_ title: String, insert: String? = nil, name: String) -> MathKey {
        MathKey(id: "key-" + title, title: title, accessibilityName: name, action: .insert(insert ?? title, cursorBack: 0))
    }

    /// A catalogue function: inserts its template (with argument commas) and places the cursor
    /// after the opening parenthesis; the signature hint then shows the argument positions.
    static func function(_ id: String) -> MathKey {
        let spec = FormulaCatalog.function(named: id)!
        let template = spec.template
        return MathKey(id: "fn-" + spec.id, title: spec.id, accessibilityName: spec.title,
                       action: .insert(template, cursorBack: template.count - spec.id.count - 1), isFunction: true)
    }

    static func function(_ function: MathFunction, name: String) -> MathKey {
        Self.function(function.rawValue)
    }

    static let left = MathKey(id: "key-left", title: "◀", accessibilityName: "Cursor nach links", action: .moveLeft)
    static let right = MathKey(id: "key-right", title: "▶", accessibilityName: "Cursor nach rechts", action: .moveRight)
    static let delete = MathKey(id: "key-delete", title: "⌫", accessibilityName: "Löschen", action: .deleteBackward)
    static let done = MathKey(id: "keyboardDone", title: "Fertig", accessibilityName: "Fertig", action: .done)
}

/// Key sets of the supplementary keyboard for the classic modes and the synthesizer.
struct MathKeyboardLayout: Equatable {
    var symbols: [MathKey]
    var functions: [MathKey]

    private static let operators: [MathKey] = [
        .text("(", name: "Klammer auf"),
        .text(")", name: "Klammer zu"),
        .text("+", name: "plus"),
        .text("−", insert: "-", name: "minus"),
        .text("×", insert: "*", name: "mal"),
        .text("÷", insert: "/", name: "geteilt durch"),
        .text("^", name: "hoch"),
        .text("x²", insert: "^2", name: "zum Quadrat"),
        .text(".", name: "Dezimalpunkt"),
        .text(",", name: "Komma zwischen Argumenten"),
        .text("<", name: "kleiner als"),
        .text(">", name: "größer als"),
        .text("==", name: "gleich"),
        .text("[", name: "eckige Klammer auf"),
        .text("]", name: "eckige Klammer zu"),
        MathKey(id: "key-sqrt", title: "√", accessibilityName: "Quadratwurzel", action: .insert("sqrt()", cursorBack: 1))
    ]

    private static let functionKeys: [MathKey] = [
        "sin", "cos", "tan", "asin", "acos", "atan", "abs", "sqrt", "ln", "log10", "exp", "floor", "ceil", "round", "frac",
        "min", "max", "mod", "clip", "if", "piecewise", "sum", "prod", "len", "sign"
    ].map { MathKey.function($0) }

    static let classic = MathKeyboardLayout(
        symbols: [.text("x", name: "x"), .text("a", name: "Parameter a"), .text("b", name: "Parameter b"),
                  .text("c", name: "Parameter c"), .text("π", insert: "pi", name: "Pi"), .text("e", name: "Eulersche Zahl e")] + operators,
        functions: functionKeys)

    static let synth = MathKeyboardLayout(
        symbols: [.text("t", name: "Zeit t"), .text("beat", name: "Beat"), .text("bar", name: "Takt"),
                  .text("localTime", name: "Zeit seit dem Trigger"), .text("localBeat", name: "Beats seit dem Trigger"),
                  .text("n", name: "Triggerzähler"), .text("note", name: "Note"), .text("x", name: "x"),
                  .text("π", insert: "pi", name: "Pi"), .text("e", name: "Eulersche Zahl e")] + operators,
        functions: functionKeys)
}

/// Two rows: symbols/operators and functions, plus fixed cursor/done keys.
struct MathKeyboardView: View {
    var layout: MathKeyboardLayout = .classic
    let onKey: (MathKey) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                keyRow(layout.symbols)
                fixedKey(.left)
                fixedKey(.right)
            }
            HStack(spacing: 6) {
                keyRow(layout.functions)
                fixedKey(.delete)
                Button {
                    onKey(.done)
                } label: {
                    Text(MathKey.done.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(DemonTheme.void)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(DemonBladeShape().fill(DemonTheme.green))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fertig")
                .accessibilityIdentifier("keyboardDone")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            LinearGradient(colors: [DemonTheme.cardTop, DemonTheme.void], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(DemonTheme.metalStroke).frame(height: 1)
                }
        )
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func keyRow(_ keys: [MathKey]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(keys) { key in
                    Button {
                        onKey(key)
                    } label: {
                        Text(key.title)
                            .font(key.isFunction || key.title.count > 2 ? Font.callout.weight(.semibold).monospaced() : Font.title3.weight(.semibold))
                            .foregroundStyle(key.isFunction ? DemonTheme.neonGreen : DemonTheme.textPrimary)
                            .padding(.horizontal, key.isFunction || key.title.count > 2 ? 10 : 6)
                            .frame(minWidth: 40, minHeight: 40)
                            .background(DemonRuneShape().fill(Color.black.opacity(0.45)))
                            .overlay(DemonRuneShape().stroke(DemonTheme.metalMid.opacity(0.9), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key.accessibilityName)
                    .accessibilityIdentifier(key.id)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func fixedKey(_ key: MathKey) -> some View {
        Button {
            onKey(key)
        } label: {
            Text(key.title)
                .font(.body.weight(.bold))
                .foregroundStyle(DemonTheme.blurpleText)
                .frame(minWidth: 40, minHeight: 40)
                .background(DemonRuneShape().fill(DemonTheme.metalShadow.opacity(0.8)))
                .overlay(DemonRuneShape().stroke(DemonTheme.metalStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibilityName)
        .accessibilityIdentifier(key.id)
    }
}

/// Input accessory view that hosts the SwiftUI keyboard above the system keyboard.
final class MathKeyboardAccessoryView: UIInputView {
    private let host: UIHostingController<MathKeyboardView>

    init(layout: MathKeyboardLayout = .classic, onKey: @escaping (MathKey) -> Void) {
        host = UIHostingController(rootView: MathKeyboardView(layout: layout, onKey: onKey))
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 104), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 104)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

extension MathKeyboardAccessoryView: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// Character offset of the cursor in a text input (for the signature help).
private func characterOffset(in input: UITextInput, position: UITextPosition) -> Int {
    input.offset(from: input.beginningOfDocument, to: position)
}

/// Single-line formula field (UIKit, to insert at the cursor position) with the math keyboard.
struct FormulaTextField: UIViewRepresentable {
    @Binding var text: String
    var isInvalid: Bool
    var cursor: Binding<Int>?
    var layout: MathKeyboardLayout = .classic
    var placeholder = "z. B. sin(x) oder y = 2x^2"
    var identifier = "formulaField"
    var accessibilityName = "Formel"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        let baseFont = UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
        field.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: baseFont, maximumPointSize: 34)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .white
        field.tintColor = UIColor(DemonTheme.neonGreen)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.keyboardType = .asciiCapable
        field.keyboardAppearance = .dark
        field.returnKeyType = .done
        field.clearButtonMode = .never
        field.attributedPlaceholder = NSAttributedString(string: placeholder,
                                                         attributes: [.foregroundColor: UIColor(DemonTheme.textTertiary)])
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityName
        field.accessibilityHint = "Mathematische Formel eingeben"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        field.inputAccessoryView = MathKeyboardAccessoryView(layout: layout) { [weak field] key in
            guard let field else { return }
            coordinator.handle(key, in: field)
        }
        field.text = text
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.accessibilityValue = isInvalid ? "\(text), ungültig" : text
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormulaTextField

        init(parent: FormulaTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
            reportCursor(field)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            reportCursor(textField)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        private func reportCursor(_ field: UITextField) {
            guard let cursor = parent.cursor, let position = field.selectedTextRange?.start else { return }
            let offset = characterOffset(in: field, position: position)
            if cursor.wrappedValue != offset {
                cursor.wrappedValue = offset
            }
        }

        func handle(_ key: MathKey, in field: UITextField) {
            switch key.action {
            case .insert(let text, let cursorBack):
                field.insertText(text)
                if cursorBack > 0, let position = field.selectedTextRange?.start,
                   let target = field.position(from: position, offset: -cursorBack) {
                    field.selectedTextRange = field.textRange(from: target, to: target)
                }
            case .moveLeft:
                move(field, by: -1)
            case .moveRight:
                move(field, by: 1)
            case .deleteBackward:
                field.deleteBackward()
            case .done:
                field.resignFirstResponder()
            }
            parent.text = field.text ?? ""
            reportCursor(field)
            UIDevice.current.playInputClick()
        }

        private func move(_ field: UITextField, by offset: Int) {
            guard let range = field.selectedTextRange,
                  let target = field.position(from: offset < 0 ? range.start : range.end, offset: offset) else { return }
            field.selectedTextRange = field.textRange(from: target, to: target)
        }
    }
}

/// Multi-line formula editor (advanced editor) with the same keyboard.
struct FormulaTextView: UIViewRepresentable {
    @Binding var text: String
    var isInvalid: Bool
    var cursor: Binding<Int>?
    var layout: MathKeyboardLayout = .classic
    var identifier = "formulaTextView"
    var accessibilityName = "Formel, mehrzeilig"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        let baseFont = UIFont.monospacedSystemFont(ofSize: 17, weight: .medium)
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont, maximumPointSize: 30)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .white
        view.backgroundColor = .clear
        view.tintColor = UIColor(DemonTheme.neonGreen)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        view.keyboardAppearance = .dark
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = accessibilityName
        view.accessibilityHint = "Eine Definition pro Zeile; die Zeile ohne Gleichheitszeichen ist die Ausgabe"
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        view.inputAccessoryView = MathKeyboardAccessoryView(layout: layout) { [weak view] key in
            guard let view else { return }
            coordinator.handle(key, in: view)
        }
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
        }
        view.accessibilityValue = isInvalid ? "\(text), ungültig" : text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(88, size.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: FormulaTextView

        init(parent: FormulaTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            reportCursor(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            reportCursor(textView)
        }

        private func reportCursor(_ view: UITextView) {
            guard let cursor = parent.cursor, let position = view.selectedTextRange?.start else { return }
            let offset = characterOffset(in: view, position: position)
            if cursor.wrappedValue != offset {
                cursor.wrappedValue = offset
            }
        }

        func handle(_ key: MathKey, in view: UITextView) {
            switch key.action {
            case .insert(let text, let cursorBack):
                view.insertText(text)
                if cursorBack > 0, let position = view.selectedTextRange?.start,
                   let target = view.position(from: position, offset: -cursorBack) {
                    view.selectedTextRange = view.textRange(from: target, to: target)
                }
            case .moveLeft, .moveRight:
                let offset = key.action == .moveLeft ? -1 : 1
                if let range = view.selectedTextRange,
                   let target = view.position(from: offset < 0 ? range.start : range.end, offset: offset) {
                    view.selectedTextRange = view.textRange(from: target, to: target)
                }
            case .deleteBackward:
                view.deleteBackward()
            case .done:
                view.resignFirstResponder()
            }
            parent.text = view.text ?? ""
            reportCursor(view)
            UIDevice.current.playInputClick()
        }
    }
}
