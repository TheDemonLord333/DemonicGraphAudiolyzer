import SwiftUI

/// Panel with concave corner cuts and small blade spikes in the middle of both sides –
/// the outline language of the icon's crest.
struct DemonPanelShape: Shape {
    var cornerCut: CGFloat = DemonTheme.cornerCut
    /// Width of the side blades (drawn inside the rect).
    var spike: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let c = min(cornerCut, rect.width / 4, rect.height / 4)
        let s = min(spike, rect.width / 10)
        let left = rect.minX + s
        let right = rect.maxX - s
        let top = rect.minY
        let bottom = rect.maxY
        let midY = rect.midY
        let blade = min(s * 2.2, rect.height / 6)
        let bend: CGFloat = 0.72

        var path = Path()
        path.move(to: CGPoint(x: left + c, y: top))
        path.addLine(to: CGPoint(x: right - c, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + c), control: CGPoint(x: right - c * bend, y: top + c * bend))
        if s > 0 {
            path.addLine(to: CGPoint(x: right, y: midY - blade))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            path.addLine(to: CGPoint(x: right, y: midY + blade))
        }
        path.addLine(to: CGPoint(x: right, y: bottom - c))
        path.addQuadCurve(to: CGPoint(x: right - c, y: bottom), control: CGPoint(x: right - c * bend, y: bottom - c * bend))
        path.addLine(to: CGPoint(x: left + c, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - c), control: CGPoint(x: left + c * bend, y: bottom - c * bend))
        if s > 0 {
            path.addLine(to: CGPoint(x: left, y: midY + blade))
            path.addLine(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: left, y: midY - blade))
        }
        path.addLine(to: CGPoint(x: left, y: top + c))
        path.addQuadCurve(to: CGPoint(x: left + c, y: top), control: CGPoint(x: left + c * bend, y: top + c * bend))
        path.closeSubpath()
        return path
    }
}

/// A curved demon horn. The base sits on the bottom edge of the rect, the tip points up and
/// outwards (to the left unless `mirrored`).
struct DemonHornShape: Shape {
    var mirrored = false

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let px = mirrored ? rect.maxX - x * w : rect.minX + x * w
            return CGPoint(x: px, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.42, 1.0))
        // Outer edge sweeping outwards and up to the tip.
        path.addCurve(to: p(0.10, 0.0), control1: p(0.02, 0.82), control2: p(-0.04, 0.30))
        // Inner edge curving back down to the base.
        path.addCurve(to: p(1.0, 1.0), control1: p(0.34, 0.30), control2: p(0.52, 0.86))
        path.closeSubpath()
        return path
    }
}

/// Small light highlight along the outer edge of a horn (metallic bevel).
struct DemonHornHighlightShape: Shape {
    var mirrored = false

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let px = mirrored ? rect.maxX - x * w : rect.minX + x * w
            return CGPoint(x: px, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.38, 0.92))
        path.addCurve(to: p(0.12, 0.06), control1: p(0.08, 0.76), control2: p(0.02, 0.32))
        return path
    }
}

/// Elongated blade with pointed ends (like the diamond tips of the icon's axes).
/// Used for the "Graph abspielen" button.
struct DemonBladeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        let tip = min(h * 0.55, rect.width / 4)
        let midY = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tip, y: rect.minY), control: CGPoint(x: rect.minX + tip * 0.62, y: rect.minY + h * 0.34))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: midY), control: CGPoint(x: rect.maxX - tip * 0.62, y: rect.minY + h * 0.34))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - tip, y: rect.maxY), control: CGPoint(x: rect.maxX - tip * 0.62, y: rect.maxY - h * 0.34))
        path.addLine(to: CGPoint(x: rect.minX + tip, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: midY), control: CGPoint(x: rect.minX + tip * 0.62, y: rect.maxY - h * 0.34))
        path.closeSubpath()
        return path
    }
}

/// Compact hexagonal "rune" with pointed left and right ends for secondary buttons.
struct DemonRuneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width * 0.22, rect.height * 0.32)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Rhombus (axis tips, bullets, indicators).
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Upward crown spike with concave flanks (top centre of the icon's crest).
struct CrownSpikeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.maxY - rect.height * 0.25))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.maxY - rect.height * 0.25))
        path.closeSubpath()
        return path
    }
}

/// Slanted almond eye – the glowing green eyes of the icon.
struct DemonEyeShape: Shape {
    var mirrored = false

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let px = mirrored ? rect.maxX - x * rect.width : rect.minX + x * rect.width
            return CGPoint(x: px, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0, 0.15))
        path.addQuadCurve(to: p(1, 0.85), control: p(0.65, 0.05))
        path.addQuadCurve(to: p(0, 0.15), control: p(0.35, 1.05))
        path.closeSubpath()
        return path
    }
}
