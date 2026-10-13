import SwiftUI
import UIKit

/// Central design tokens derived from the app icon: near-black night sky, metallic
/// blurple horns with light edges, neon green signal and eyes.
enum DemonTheme {
    // MARK: Brand colours
    /// Discord blurple #5865F2 – main colour, metal, secondary controls.
    static let blurple = Color(hex: 0x5865F2)
    /// Spotify green #1DB954 – active elements, played curve, progress.
    static let green = Color(hex: 0x1DB954)
    /// Brighter neon green of the icon's eyes (glow only).
    static let neonGreen = Color(hex: 0x37FC87)
    /// Bright core of the moving point.
    static let greenCore = Color(hex: 0xEAFFF2)

    // MARK: Backgrounds
    static let void = Color(hex: 0x06070F)
    static let abyss = Color(hex: 0x0D142B)
    static let violetNight = Color(hex: 0x1A0B2E)
    static let screen = Color(hex: 0x04071A)
    static let cardTop = Color(hex: 0x111633)
    static let cardBottom = Color(hex: 0x080A1A)

    // MARK: Metal (horns)
    static let metalHighlight = Color(hex: 0xD4D3FF)
    static let metalLight = Color(hex: 0x9EA2FF)
    static let metalMid = Color(hex: 0x5358FD)
    static let metalDeep = Color(hex: 0x3A33D5)
    static let metalShadow = Color(hex: 0x14125E)

    // MARK: Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xCDD0EC)
    static let textTertiary = Color(hex: 0x9BA0CC)
    /// Blurple that is readable as small text on the dark background (contrast > 7:1).
    static let blurpleText = Color(hex: 0xAEB4FF)
    static let danger = Color(hex: 0xFF6B86)

    // MARK: Graph (light paper mode only changes the plot area)
    static let paper = Color(hex: 0xFAFAF6)
    static let ink = Color.black

    // MARK: Gradients

    static let metalGradient = LinearGradient(
        stops: [
            .init(color: metalHighlight, location: 0),
            .init(color: metalLight, location: 0.18),
            .init(color: metalMid, location: 0.45),
            .init(color: metalDeep, location: 0.7),
            .init(color: metalShadow, location: 1)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Stroke for frames: light edge on top, deep metal below (like the horns' bevel).
    static let metalStroke = LinearGradient(
        stops: [
            .init(color: metalHighlight.opacity(0.95), location: 0),
            .init(color: metalMid, location: 0.35),
            .init(color: metalDeep, location: 0.7),
            .init(color: metalLight.opacity(0.8), location: 1)
        ],
        startPoint: .top, endPoint: .bottom)

    static let cardFill = LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)

    static let greenFill = LinearGradient(colors: [neonGreen, green], startPoint: .top, endPoint: .bottom)

    static let pressedFill = LinearGradient(colors: [Color(hex: 0x1B2A2A), Color(hex: 0x0B1514)], startPoint: .top, endPoint: .bottom)

    // MARK: Metrics
    static let cornerCut: CGFloat = 14
    static let minimumTouch: CGFloat = 44
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// UIKit appearance so that native controls (sliders, alerts, pickers) match the theme.
enum DemonAppearance {
    @MainActor
    static func configure() {
        let slider = UISlider.appearance()
        slider.minimumTrackTintColor = UIColor(DemonTheme.green)
        slider.maximumTrackTintColor = UIColor(DemonTheme.metalShadow)
        slider.setThumbImage(thumbImage(highlighted: false), for: .normal)
        slider.setThumbImage(thumbImage(highlighted: true), for: .highlighted)

        UITextField.appearance().keyboardAppearance = .dark
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(DemonTheme.green)
    }

    /// Diamond thumb with metallic rim and green core (like the axis tips of the icon).
    @MainActor
    static func thumbImage(highlighted: Bool) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = highlighted ? 12 : 11
            let diamond = UIBezierPath()
            diamond.move(to: CGPoint(x: center.x, y: center.y - radius))
            diamond.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            diamond.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            diamond.close()

            cg.saveGState()
            cg.setShadow(offset: .zero, blur: highlighted ? 8 : 5, color: UIColor(DemonTheme.neonGreen).withAlphaComponent(0.8).cgColor)
            UIColor(DemonTheme.metalDeep).setFill()
            diamond.fill()
            cg.restoreGState()

            let inner = UIBezierPath()
            let innerRadius = radius * 0.55
            inner.move(to: CGPoint(x: center.x, y: center.y - innerRadius))
            inner.addLine(to: CGPoint(x: center.x + innerRadius, y: center.y))
            inner.addLine(to: CGPoint(x: center.x, y: center.y + innerRadius))
            inner.addLine(to: CGPoint(x: center.x - innerRadius, y: center.y))
            inner.close()
            UIColor(highlighted ? DemonTheme.greenCore : DemonTheme.neonGreen).setFill()
            inner.fill()

            UIColor(DemonTheme.metalHighlight).setStroke()
            diamond.lineWidth = 1.5
            diamond.stroke()
        }
    }
}
