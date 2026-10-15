import SwiftUI

extension VoiceColor {
    var color: Color { Color(hex: hex) }
}

/// Small capsule that names the meaning of an editor's output ("Tonhöhe · Halbtöne").
struct DemonBadge: View {
    let text: String
    var icon: String?
    var tint: Color = DemonTheme.blurpleText

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DemonPanelShape(cornerCut: 5, spike: 0).fill(tint.opacity(0.13)))
        .overlay(DemonPanelShape(cornerCut: 5, spike: 0).stroke(tint.opacity(0.55), lineWidth: 0.8))
    }
}

/// Small explanatory text in the theme.
struct DemonCaption: View {
    let text: String
    var warning = false

    init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(warning ? DemonTheme.danger : DemonTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Subtitle inside cards.
struct DemonSubheader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(DemonTheme.textSecondary)
    }
}

/// A dark inset panel (used for editors and diagrams).
struct DemonInsetModifier: ViewModifier {
    var tint: Color = DemonTheme.metalMid
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DemonPanelShape(cornerCut: 9, spike: 0).fill(Color.black.opacity(0.45)))
            .overlay(DemonPanelShape(cornerCut: 9, spike: 0).stroke(tint.opacity(0.8), lineWidth: 1))
    }
}

extension View {
    func demonInset(tint: Color = DemonTheme.metalMid, padding: CGFloat = 10) -> some View {
        modifier(DemonInsetModifier(tint: tint, padding: padding))
    }
}

/// Colour dot of a voice.
struct VoiceColorDot: View {
    let color: VoiceColor
    var size: CGFloat = 12

    var body: some View {
        DiamondShape()
            .fill(color.color)
            .frame(width: size, height: size)
            .shadow(color: color.color.opacity(0.8), radius: 3)
            .accessibilityHidden(true)
    }
}

/// Selection from a longer list as a themed menu (title, current value, chevron).
struct DemonMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var identifier: String?

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DemonTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(currentTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DemonTheme.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DemonTheme.blurpleText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(DemonPanelShape(cornerCut: 8, spike: 0).fill(Color.black.opacity(0.4)))
            .overlay(DemonPanelShape(cornerCut: 8, spike: 0).stroke(DemonTheme.metalMid.opacity(0.85), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
        .accessibilityIdentifier(identifier ?? title)
    }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? "–"
    }
}

/// Integer stepper with rune buttons.
struct DemonStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DemonTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Button {
                value = max(range.lowerBound, value - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(value <= range.lowerBound)
            .accessibilityLabel("\(title) verringern")
            Text(format(value))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(DemonTheme.green)
                .frame(minWidth: 34)
            Button {
                value = min(range.upperBound, value + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(value >= range.upperBound)
            .accessibilityLabel("\(title) erhöhen")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
    }
}

/// Plain themed text field (names, rhythm patterns).
struct DemonTextField: View {
    let title: String
    @Binding var text: String
    var monospaced = false
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.textTertiary)
                .accessibilityHidden(true)
            TextField(title, text: $text)
                .font(monospaced ? .body.monospaced() : .body.weight(.semibold))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(DemonTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(DemonPanelShape(cornerCut: 7, spike: 0).fill(Color.black.opacity(0.45)))
                .overlay(DemonPanelShape(cornerCut: 7, spike: 0).stroke(DemonTheme.metalMid.opacity(0.85), lineWidth: 1))
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}

/// List of numbers ("0, 3, 7, 10"). Commits on return or when focus is lost; invalid entries
/// are marked and not applied.
struct NumberListField: View {
    let title: String
    @Binding var values: [Double]
    var minimumCount = 1
    var maximumCount = 64
    var identifier: String?

    @State private var text = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemonTheme.textTertiary)
                .accessibilityHidden(true)
            TextField(title, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .font(.body.monospaced())
                .foregroundStyle(isInvalid ? DemonTheme.danger : DemonTheme.textPrimary)
                .focused($isFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(DemonPanelShape(cornerCut: 7, spike: 0).fill(Color.black.opacity(0.45)))
                .overlay(DemonPanelShape(cornerCut: 7, spike: 0)
                    .stroke(isInvalid ? DemonTheme.danger : (isFocused ? DemonTheme.green : DemonTheme.metalMid.opacity(0.85)), lineWidth: 1.2))
                .accessibilityLabel(title)
                .accessibilityHint(isInvalid ? "Ungültige Liste" : "Zahlen durch Semikolon oder Leerzeichen getrennt")
                .accessibilityIdentifier(identifier ?? title)
            if isInvalid {
                DemonCaption("Bitte \(minimumCount)–\(maximumCount) Zahlen eingeben, getrennt durch Semikolon oder Leerzeichen (z. B. 0; 3; 7; 10).", warning: true)
            }
        }
        .onAppear { text = Self.format(values) }
        .onChange(of: values) { _, newValue in
            if !isFocused { text = Self.format(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    static func format(_ values: [Double]) -> String {
        values.map { NumberText.compact($0, maximumFractionDigits: 4) }.joined(separator: "; ")
    }

    private func commit() {
        guard let parsed = NumberListParser.parse(text), (minimumCount...maximumCount).contains(parsed.count) else {
            isInvalid = true
            return
        }
        isInvalid = false
        values = parsed
        text = Self.format(parsed)
    }
}
