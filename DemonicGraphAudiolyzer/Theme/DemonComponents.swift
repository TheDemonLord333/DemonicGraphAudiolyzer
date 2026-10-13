import SwiftUI

// MARK: - Decorations

/// One metallic horn with bevel highlight and blurple glow.
struct DemonHorn: View {
    var mirrored = false

    var body: some View {
        ZStack {
            DemonHornShape(mirrored: mirrored)
                .fill(LinearGradient(colors: [DemonTheme.metalHighlight, DemonTheme.metalMid, DemonTheme.metalDeep, DemonTheme.metalShadow],
                                     startPoint: mirrored ? .topTrailing : .topLeading,
                                     endPoint: mirrored ? .bottomLeading : .bottomTrailing))
            DemonHornShape(mirrored: mirrored)
                .stroke(DemonTheme.metalHighlight.opacity(0.55), lineWidth: 0.8)
            DemonHornHighlightShape(mirrored: mirrored)
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
        .shadow(color: DemonTheme.blurple.opacity(0.6), radius: 5)
        .accessibilityHidden(true)
    }
}

/// Two glowing green eyes (as in the icon).
struct DemonEyes: View {
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.9) {
            DemonEyeShape()
                .fill(DemonTheme.neonGreen)
                .frame(width: size, height: size * 0.5)
            DemonEyeShape(mirrored: true)
                .fill(DemonTheme.neonGreen)
                .frame(width: size, height: size * 0.5)
        }
        .shadow(color: DemonTheme.neonGreen.opacity(0.9), radius: 4)
        .shadow(color: DemonTheme.green.opacity(0.6), radius: 9)
        .accessibilityHidden(true)
    }
}

/// Horn pair with crown spike that sits on top of a card.
struct DemonCrest: View {
    var hornHeight: CGFloat = 40
    var showsEyes = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            DemonHorn()
                .frame(width: hornHeight * 1.2, height: hornHeight)
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                CrownSpikeShape()
                    .fill(DemonTheme.metalGradient)
                    .overlay(CrownSpikeShape().stroke(DemonTheme.metalHighlight.opacity(0.6), lineWidth: 0.8))
                    .frame(width: hornHeight * 0.42, height: hornHeight * 0.6)
                    .shadow(color: DemonTheme.blurple.opacity(0.6), radius: 4)
                if showsEyes {
                    DemonEyes(size: hornHeight * 0.42)
                        .padding(.bottom, -hornHeight * 0.12)
                }
            }
            Spacer(minLength: 8)
            DemonHorn(mirrored: true)
                .frame(width: hornHeight * 1.2, height: hornHeight)
        }
        // The horns reach slightly beyond the card corners, like on the icon's crest.
        .padding(.horizontal, -10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Faint green audio bars like those behind the icon's sine wave.
struct AudioBarsDecoration: View {
    var body: some View {
        Canvas { context, size in
            let count = max(12, Int(size.width / 9))
            let spacing = size.width / CGFloat(count)
            for index in 0..<count {
                let t = Double(index) / Double(count)
                let envelope = 0.35 + 0.65 * abs(sin(t * Double.pi * 3.2 + 0.4)) * (0.6 + 0.4 * sin(t * 17))
                let height = size.height * CGFloat(max(0.08, envelope))
                let rect = CGRect(x: CGFloat(index) * spacing + spacing * 0.3,
                                  y: size.height / 2 - height / 2,
                                  width: spacing * 0.32, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(DemonTheme.green))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Dark night background with violet and blurple light.
struct DemonBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [DemonTheme.abyss, DemonTheme.void, DemonTheme.void], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [DemonTheme.violetNight, .clear], center: UnitPoint(x: 0.5, y: -0.05), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [DemonTheme.blurple.opacity(0.13), .clear], center: UnitPoint(x: 0.9, y: 1.0), startRadius: 0, endRadius: 420)
            VStack {
                Spacer()
                AudioBarsDecoration()
                    .frame(height: 90)
                    .opacity(0.06)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

struct DemonCardModifier: ViewModifier {
    var crest = false
    var padding: CGFloat = 16
    var hornHeight: CGFloat = 38

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    DemonPanelShape().fill(DemonTheme.cardFill)
                    DemonPanelShape().fill(RadialGradient(colors: [DemonTheme.blurple.opacity(0.12), .clear],
                                                          center: .top, startRadius: 0, endRadius: 280))
                }
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
            }
            .overlay {
                ZStack {
                    DemonPanelShape().stroke(DemonTheme.metalStroke, lineWidth: 1.6)
                    DemonPanelShape(cornerCut: DemonTheme.cornerCut - 3, spike: 3)
                        .stroke(DemonTheme.metalHighlight.opacity(0.10), lineWidth: 1)
                        .padding(4)
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if crest {
                    DemonCrest(hornHeight: hornHeight)
                        .offset(y: -hornHeight + 7)
                }
            }
            .padding(.top, crest ? hornHeight - 6 : 0)
    }
}

extension View {
    /// Dark metallic card with demonic outline; `crest` adds horns, crown and eyes on top.
    func demonCard(crest: Bool = false, padding: CGFloat = 16, hornHeight: CGFloat = 38) -> some View {
        modifier(DemonCardModifier(crest: crest, padding: padding, hornHeight: hornHeight))
    }
}

struct DemonSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            DiamondShape()
                .fill(DemonTheme.green)
                .frame(width: 8, height: 8)
                .shadow(color: DemonTheme.neonGreen.opacity(0.8), radius: 3)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DemonTheme.blurpleText)
            }
            Text(title.uppercased())
                .font(.footnote.weight(.heavy))
                .tracking(1.3)
                .foregroundStyle(DemonTheme.blurpleText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Rectangle()
                .fill(LinearGradient(colors: [DemonTheme.metalMid.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(minWidth: 12, maxWidth: .infinity)
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Header

struct DemonHeader: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            if !compact {
                DemonCrest(hornHeight: 30)
                    .frame(maxWidth: 230)
            }
            Text("DEMONIC GRAPH")
                .font((compact ? Font.headline : Font.title2).weight(.black))
                .fontWidth(.expanded)
                .tracking(compact ? 1 : 2)
                .foregroundStyle(LinearGradient(colors: [DemonTheme.metalHighlight, DemonTheme.metalLight, DemonTheme.blurple],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: DemonTheme.blurple.opacity(0.7), radius: 6)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("AUDIOLYZER")
                .font(.caption.weight(.heavy))
                .tracking(6)
                .foregroundStyle(DemonTheme.green)
                .shadow(color: DemonTheme.neonGreen.opacity(0.6), radius: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demonic Graph Audiolyzer")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

/// "Graph abspielen": blade shape with metallic blurple frame and green glow.
struct DemonPrimaryButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .foregroundStyle(DemonTheme.textPrimary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 12)
            .frame(minHeight: 58)
            .background {
                ZStack {
                    DemonBladeShape().fill(configuration.isPressed ? DemonTheme.pressedFill : DemonTheme.cardFill)
                    DemonBladeShape().fill(RadialGradient(colors: [DemonTheme.green.opacity(configuration.isPressed ? 0.35 : 0.16), .clear],
                                                          center: .center, startRadius: 0, endRadius: 140))
                }
            }
            .overlay {
                ZStack {
                    DemonBladeShape().stroke(DemonTheme.metalStroke, lineWidth: 2.6)
                    DemonBladeShape().stroke(DemonTheme.metalHighlight.opacity(0.22), lineWidth: 0.8).padding(5)
                }
            }
            .shadow(color: DemonTheme.green.opacity(configuration.isPressed ? 0.65 : 0.28), radius: configuration.isPressed ? 16 : 9)
            .shadow(color: DemonTheme.blurple.opacity(0.35), radius: 4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(DemonBladeShape())
    }
}

/// Secondary control: rune hexagon in blurple; green when active.
struct DemonRuneButtonStyle: ButtonStyle {
    var isActive = false
    var minWidth: CGFloat = 60
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(isActive ? DemonTheme.neonGreen : DemonTheme.blurpleText)
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth, minHeight: 48)
            .background {
                DemonRuneShape()
                    .fill(isActive ? AnyShapeStyle(DemonTheme.green.opacity(0.16)) : AnyShapeStyle(DemonTheme.cardFill))
            }
            .overlay {
                DemonRuneShape()
                    .stroke(isActive ? AnyShapeStyle(DemonTheme.green) : AnyShapeStyle(DemonTheme.metalStroke), lineWidth: 1.6)
            }
            .shadow(color: isActive ? DemonTheme.green.opacity(0.5) : .clear, radius: 8)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(DemonRuneShape())
    }
}

/// Small text button in the theme (toolbar actions, list actions).
struct DemonChipButtonStyle: ButtonStyle {
    var tint: Color = DemonTheme.blurpleText
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? DemonTheme.neonGreen : tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                DemonPanelShape(cornerCut: 8, spike: 0)
                    .fill(isActive ? DemonTheme.green.opacity(0.16) : Color.black.opacity(0.35))
            }
            .overlay {
                DemonPanelShape(cornerCut: 8, spike: 0)
                    .stroke(isActive ? AnyShapeStyle(DemonTheme.green) : AnyShapeStyle(DemonTheme.metalMid.opacity(0.85)), lineWidth: 1.1)
            }
            .brightness(configuration.isPressed ? 0.15 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

// MARK: - Selection controls

/// Custom segmented control: selected option glows green inside a rune shape.
struct DemonSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? DemonTheme.greenCore : DemonTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isSelected {
                                ZStack {
                                    DemonRuneShape().fill(DemonTheme.green.opacity(0.22))
                                    DemonRuneShape().stroke(DemonTheme.green, lineWidth: 1.4)
                                }
                                .shadow(color: DemonTheme.green.opacity(0.45), radius: 6)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(DemonPanelShape(cornerCut: 10, spike: 0).fill(Color.black.opacity(0.4)))
        .overlay(DemonPanelShape(cornerCut: 10, spike: 0).stroke(DemonTheme.metalStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Toggle with a diamond knob that turns green when on.
struct DemonToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .foregroundStyle(DemonTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? DemonTheme.green.opacity(0.32) : Color.black.opacity(0.5))
                    Capsule()
                        .stroke(configuration.isOn ? AnyShapeStyle(DemonTheme.green) : AnyShapeStyle(DemonTheme.metalStroke), lineWidth: 1.3)
                    DiamondShape()
                        .fill(configuration.isOn ? DemonTheme.greenCore : DemonTheme.metalLight)
                        .frame(width: 18, height: 18)
                        .shadow(color: configuration.isOn ? DemonTheme.neonGreen : .clear, radius: 5)
                        .padding(.horizontal, 6)
                }
                .frame(width: 58, height: 32)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// Native slider (diamond thumb via UIAppearance) with title and green value read-out.
struct DemonSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var logarithmic = false
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DemonTheme.textSecondary)
                Spacer(minLength: 8)
                Text(format(value))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(DemonTheme.green)
            }
            slider
                .tint(DemonTheme.green)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
        }
    }

    @ViewBuilder
    private var slider: some View {
        if logarithmic {
            Slider(value: Binding(get: { log2(max(value, range.lowerBound)) },
                                  set: { value = min(max(exp2($0), range.lowerBound), range.upperBound) }),
                   in: log2(range.lowerBound)...log2(range.upperBound))
        } else if let step {
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = $0 }),
                   in: range, step: step)
        } else {
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = $0 }),
                   in: range)
        }
    }
}

/// Text field for numbers ("0,5", "0.5", "2pi"). Commits on return or when focus is lost.
struct NumericField: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>?
    var fractionDigits = 3
    var accessibilityIdentifier: String?

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
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(isInvalid ? DemonTheme.danger : DemonTheme.textPrimary)
                .focused($isFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(DemonPanelShape(cornerCut: 7, spike: 0).fill(Color.black.opacity(0.45)))
                .overlay(DemonPanelShape(cornerCut: 7, spike: 0)
                    .stroke(isInvalid ? DemonTheme.danger : (isFocused ? DemonTheme.green : DemonTheme.metalMid.opacity(0.85)), lineWidth: 1.2))
                .accessibilityLabel(title)
                .accessibilityHint(isInvalid ? "Ungültige Zahl" : "Zahl eingeben, Dezimalkomma oder -punkt")
                .accessibilityIdentifier(accessibilityIdentifier ?? title)
        }
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = formatted(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func formatted(_ number: Double) -> String {
        NumberText.compact(number, maximumFractionDigits: fractionDigits)
    }

    private func commit() {
        guard let parsed = NumberText.parse(text) else {
            isInvalid = true
            return
        }
        var newValue = parsed
        if let range { newValue = min(max(newValue, range.lowerBound), range.upperBound) }
        isInvalid = false
        value = newValue
        text = formatted(newValue)
    }
}

/// Expandable section ("Erweiterte Einstellungen").
struct DemonDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    DemonSectionHeader(title: title)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DemonTheme.green)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "aufgeklappt" : "zugeklappt")
            .accessibilityHint("Doppeltippen zum \(isExpanded ? "Zuklappen" : "Aufklappen")")
            if isExpanded {
                content()
            }
        }
    }
}

/// Labelled value used in read-outs (x, y, frequency).
struct ReadoutValue: View {
    let label: String
    let value: String
    var highlighted = false

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(DemonTheme.textTertiary)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(highlighted ? DemonTheme.green : DemonTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
