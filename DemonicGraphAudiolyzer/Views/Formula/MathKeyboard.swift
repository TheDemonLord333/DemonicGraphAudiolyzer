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

    static func function(_ function: MathFunction, name: String) -> MathKey {
        MathKey(id: "fn-" + function.rawValue, title: function.rawValue, accessibilityName: name,
                action: .insert(function.rawValue + "()", cursorBack: 1), isFunction: true)
    }

    static let symbols: [MathKey] = [
        .text("x", name: "x"),
        .text("a", name: "Parameter a"),
        .text("b", name: "Parameter b"),
        .text("c", name: "Parameter c"),
        .text("π", insert: "pi", name: "Pi"),
        .text("e", name: "Eulersche Zahl e"),
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
        MathKey(id: "key-sqrt", title: "√", accessibilityName: "Quadratwurzel", action: .insert("sqrt()", cursorBack: 1))
    ]

    static let functions: [MathKey] = [
        .function(.sin, name: "Sinus"),
        .function(.cos, name: "Kosinus"),
        .function(.tan, name: "Tangens"),
        .function(.asin, name: "Arkussinus"),
        .function(.acos, name: "Arkuskosinus"),
        .function(.atan, name: "Arkustangens"),
        .function(.abs, name: "Betrag"),
        .function(.sqrt, name: "Quadratwurzel"),
        .function(.ln, name: "natürlicher Logarithmus"),
        .function(.log10, name: "Zehnerlogarithmus"),
        .function(.exp, name: "Exponentialfunktion"),
        .function(.floor, name: "abrunden"),
        .function(.ceil, name: "aufrunden"),
        .function(.round, name: "runden"),
        MathKey(id: "fn-min", title: "min", accessibilityName: "Minimum von zwei Werten", action: .insert("min(,)", cursorBack: 2), isFunction: true),
        MathKey(id: "fn-max", title: "max", accessibilityName: "Maximum von zwei Werten", action: .insert("max(,)", cursorBack: 2), isFunction: true),
        MathKey(id: "fn-mod", title: "mod", accessibilityName: "Modulo", action: .insert("mod(,)", cursorBack: 2), isFunction: true)
    ]

    static let left = MathKey(id: "key-left", title: "◀", accessibilityName: "Cursor nach links", action: .moveLeft)
    static let right = MathKey(id: "key-right", title: "▶", accessibilityName: "Cursor nach rechts", action: .moveRight)
    static let delete = MathKey(id: "key-delete", title: "⌫", accessibilityName: "Löschen", action: .deleteBackward)
    static let done = MathKey(id: "keyboardDone", title: "Fertig", accessibilityName: "Fertig", action: .done)
}

/// Two rows: symbols/operators and functions, plus fixed cursor/done keys.
struct MathKeyboardView: View {
    let onKey: (MathKey) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                keyRow(MathKey.symbols)
                fixedKey(.left)
                fixedKey(.right)
            }
            HStack(spacing: 6) {
                keyRow(MathKey.functions)
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
                            .font(key.isFunction ? Font.callout.weight(.semibold).monospaced() : Font.title3.weight(.semibold))
                            .foregroundStyle(key.isFunction ? DemonTheme.neonGreen : DemonTheme.textPrimary)
                            .padding(.horizontal, key.isFunction ? 10 : 6)
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

    init(onKey: @escaping (MathKey) -> Void) {
        host = UIHostingController(rootView: MathKeyboardView(onKey: onKey))
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

/// Formula text field (UIKit, to insert at the cursor position) with the math keyboard.
struct FormulaTextField: UIViewRepresentable {
    @Binding var text: String
    var isInvalid: Bool

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
        field.attributedPlaceholder = NSAttributedString(string: "z. B. sin(x) oder y = 2x^2",
                                                         attributes: [.foregroundColor: UIColor(DemonTheme.textTertiary)])
        field.accessibilityIdentifier = "formulaField"
        field.accessibilityLabel = "Formel"
        field.accessibilityHint = "Mathematische Funktion von x eingeben"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        field.inputAccessoryView = MathKeyboardAccessoryView { [weak field] key in
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
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
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
            UIDevice.current.playInputClick()
        }

        private func move(_ field: UITextField, by offset: Int) {
            guard let range = field.selectedTextRange,
                  let target = field.position(from: offset < 0 ? range.start : range.end, offset: offset) else { return }
            field.selectedTextRange = field.textRange(from: target, to: target)
        }
    }
}

extension MathKeyboardAccessoryView: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
