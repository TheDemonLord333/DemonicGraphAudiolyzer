import SwiftUI

/// Renders a `MathBox` as readable mathematics: fractions with a bar, superscript powers,
/// radicals, Σ/Π with limits, case distinctions with a brace.
struct MathBoxView: View {
    let box: MathBox
    var size: CGFloat = 18
    /// Highlighted row of a case distinction at the top of the box (active section while playing).
    var activeCase: Int?

    var body: some View {
        MathRenderer(activeCase: activeCase).render(box, size: size, topLevel: true)
    }
}

private struct MathRenderer {
    var activeCase: Int?

    func color(for style: MathTextStyle) -> Color {
        switch style {
        case .number: return DemonTheme.textPrimary
        case .variable: return DemonTheme.greenCore
        case .name: return DemonTheme.neonGreen
        case .operatorSymbol: return DemonTheme.blurpleText
        case .punctuation: return DemonTheme.textTertiary
        }
    }

    func render(_ box: MathBox, size: CGFloat, topLevel: Bool = false) -> AnyView {
        switch box {
        case .text(let text, let style):
            return AnyView(
                Text(text)
                    .font(.system(size: size, weight: style == .name ? .semibold : .regular, design: style == .variable ? .serif : .default))
                    .italic(style == .variable)
                    .foregroundStyle(color(for: style))
                    .fixedSize()
            )
        case .row(let items):
            if topLevel, items.count == 1 {
                return render(items[0], size: size, topLevel: true)
            }
            return AnyView(
                HStack(alignment: .center, spacing: 1) {
                    ForEach(items.indices, id: \.self) { index in
                        render(items[index], size: size)
                    }
                }
            )
        case .fraction(let numerator, let denominator):
            let inner = max(11, size * 0.86)
            return AnyView(
                VStack(spacing: 2) {
                    render(numerator, size: inner)
                    Rectangle()
                        .fill(DemonTheme.textSecondary)
                        .frame(height: max(1, size / 15))
                    render(denominator, size: inner)
                }
                .fixedSize()
                .padding(.horizontal, 2)
            )
        case .power(let base, let exponent):
            return AnyView(
                HStack(alignment: .bottom, spacing: 0) {
                    render(base, size: size)
                    render(exponent, size: max(10, size * 0.66))
                        .padding(.bottom, size * 0.55)
                }
                .fixedSize()
            )
        case .radical(let inner):
            return AnyView(
                HStack(alignment: .center, spacing: 0) {
                    Text("√")
                        .font(.system(size: size * 1.15))
                        .foregroundStyle(DemonTheme.blurpleText)
                    render(inner, size: size)
                        .padding(.top, 3)
                        .overlay(alignment: .top) {
                            Rectangle().fill(DemonTheme.blurpleText).frame(height: 1.2)
                        }
                }
                .fixedSize()
            )
        case .delimited(let open, let inner, let close):
            return AnyView(
                HStack(alignment: .center, spacing: 1) {
                    if !open.isEmpty {
                        Text(open).font(.system(size: size * 1.1)).foregroundStyle(DemonTheme.blurpleText)
                    }
                    render(inner, size: size)
                    if !close.isEmpty {
                        Text(close).font(.system(size: size * 1.1)).foregroundStyle(DemonTheme.blurpleText)
                    }
                }
                .fixedSize()
            )
        case .bigOperator(let symbol, let lower, let upper, let body):
            let limitSize = max(10, size * 0.66)
            return AnyView(
                HStack(alignment: .center, spacing: 4) {
                    VStack(spacing: 0) {
                        render(upper, size: limitSize)
                        Text(symbol)
                            .font(.system(size: size * 1.9, weight: .light, design: .serif))
                            .foregroundStyle(DemonTheme.green)
                            .shadow(color: DemonTheme.neonGreen.opacity(0.5), radius: 3)
                        render(lower, size: limitSize)
                    }
                    .fixedSize()
                    render(body, size: size)
                }
                .fixedSize()
            )
        case .cases(let rows):
            let highlight = topLevel ? activeCase : nil
            return AnyView(
                HStack(alignment: .center, spacing: 4) {
                    Text("{")
                        .font(.system(size: size * (0.9 + 1.05 * CGFloat(rows.count)), weight: .ultraLight))
                        .foregroundStyle(DemonTheme.blurpleText)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows.indices, id: \.self) { index in
                            caseRow(rows[index], size: size, active: highlight == index)
                        }
                    }
                }
                .fixedSize()
            )
        }
    }

    private func caseRow(_ row: MathCase, size: CGFloat, active: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            render(row.value, size: size)
            if let condition = row.condition {
                Text("falls")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(DemonTheme.textTertiary)
                render(condition, size: size * 0.9)
            } else {
                Text("sonst")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(DemonTheme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background {
            if active {
                DemonPanelShape(cornerCut: 4, spike: 0)
                    .fill(DemonTheme.green.opacity(0.22))
                    .shadow(color: DemonTheme.neonGreen.opacity(0.6), radius: 5)
            }
        }
    }
}

/// All lines of a program in readable notation (definitions first, output last).
struct MathProgramView: View {
    let program: SyntaxProgram
    var outputLabel = "y"
    var size: CGFloat = 18
    var activeCase: Int?

    var body: some View {
        let lines = MathLayout.lines(of: program, outputLabel: outputLabel)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines.indices, id: \.self) { index in
                    let line = lines[index]
                    HStack(alignment: .center, spacing: 6) {
                        MathBoxView(box: line.label, size: line.kind == .output ? size : size * 0.9)
                        Text("=")
                            .font(.system(size: size))
                            .foregroundStyle(DemonTheme.blurpleText)
                        MathBoxView(box: line.body, size: line.kind == .output ? size : size * 0.9,
                                    activeCase: line.kind == .output ? activeCase : nil)
                    }
                    .opacity(line.kind == .output ? 1 : 0.85)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mathematische Darstellung")
        .accessibilityValue(lines.map { "\($0.label.spokenText) gleich \($0.body.spokenText)" }.joined(separator: ". "))
    }
}
