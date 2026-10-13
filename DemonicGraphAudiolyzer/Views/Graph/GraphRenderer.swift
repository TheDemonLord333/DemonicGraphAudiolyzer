import CoreGraphics
import Foundation
import SwiftUI

/// Visual style of the plot area. The light mode only changes the graph surface.
struct GraphAppearance: Equatable {
    var isLight = false
    var showGrid = true
    var showPreview = true
    var showCursorLine = true

    var background: Color { isLight ? DemonTheme.paper : DemonTheme.screen }
    var grid: Color { isLight ? Color.black.opacity(0.10) : DemonTheme.blurple.opacity(0.16) }
    var axis: Color { isLight ? DemonTheme.ink : Color(hex: 0x7F87FF) }
    var axisTip: Color { isLight ? DemonTheme.ink : Color(hex: 0x9EA4FF) }
    var label: Color { isLight ? Color.black.opacity(0.75) : DemonTheme.textSecondary }
    var curve: Color { isLight ? DemonTheme.ink : DemonTheme.green }
    var preview: Color { isLight ? Color.black.opacity(0.22) : DemonTheme.green.opacity(0.26) }
    var glow: Color? { isLight ? nil : DemonTheme.neonGreen }
    var highlightBand: Color { isLight ? Color.black.opacity(0.06) : DemonTheme.blurple.opacity(0.14) }
}

/// What to draw on top of the coordinate system.
struct GraphOverlayState {
    enum Curve {
        /// Idle: the whole curve is shown brightly.
        case full
        /// Running: bright up to `x`, preview (or nothing) afterwards.
        case progressive(startX: Double, currentX: Double)
    }

    var curve: Curve = .full
    /// Current point on the curve (nil = hidden, e.g. at a definition gap).
    var point: GraphPoint?
    /// Vertical position line.
    var cursorX: Double?
    /// Played x range (graph mode) shown as faint brackets.
    var playRange: ClosedRange<Double>?
    /// Highlighted section (waveform mode).
    var section: ClosedRange<Double>?
    /// The section is cycled faster than the display can show.
    var sectionIsSounding = false
}

/// Converts data coordinates into view coordinates.
struct PlotTransform {
    let viewport: GraphViewport
    let rect: CGRect

    func x(_ value: Double) -> CGFloat {
        rect.minX + CGFloat((value - viewport.xMin) / viewport.width) * rect.width
    }

    func y(_ value: Double) -> CGFloat {
        let raw = rect.maxY - CGFloat((value - viewport.yMin) / viewport.height) * rect.height
        // Keep far off-screen values bounded (poles) so Core Graphics stays precise.
        return min(max(raw, rect.minY - rect.height * 4), rect.maxY + rect.height * 4)
    }

    func point(_ p: GraphPoint) -> CGPoint {
        CGPoint(x: x(p.x), y: y(p.y))
    }

    func dataX(_ viewX: CGFloat) -> Double {
        viewport.xMin + Double((viewX - rect.minX) / max(rect.width, 1)) * viewport.width
    }

    func dataY(_ viewY: CGFloat) -> Double {
        viewport.yMin + Double((rect.maxY - viewY) / max(rect.height, 1)) * viewport.height
    }
}

/// Draws coordinate system and curve into a SwiftUI `GraphicsContext`.
enum GraphRenderer {
    static let inset: CGFloat = 10

    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: inset, y: inset, width: max(1, size.width - 2 * inset), height: max(1, size.height - 2 * inset))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, curve: SampledCurve, viewport: GraphViewport,
                     appearance: GraphAppearance, overlay: GraphOverlayState) {
        let fullRect = CGRect(origin: .zero, size: size)
        let rect = plotRect(in: size)
        let transform = PlotTransform(viewport: viewport, rect: rect)

        // Background
        context.fill(Path(fullRect), with: .color(appearance.background))
        if !appearance.isLight {
            context.fill(Path(fullRect), with: .radialGradient(
                Gradient(colors: [DemonTheme.blurple.opacity(0.10), .clear]),
                center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endRadius: max(size.width, size.height) * 0.7))
        }

        let xTicks = AxisTicks.make(lower: viewport.xMin, upper: viewport.xMax, targetCount: max(3, Int(rect.width / 70)))
        let yTicks = AxisTicks.make(lower: viewport.yMin, upper: viewport.yMax, targetCount: max(3, Int(rect.height / 50)))

        // Grid
        if appearance.showGrid {
            var grid = Path()
            for value in xTicks.values {
                let px = transform.x(value)
                grid.move(to: CGPoint(x: px, y: rect.minY))
                grid.addLine(to: CGPoint(x: px, y: rect.maxY))
            }
            for value in yTicks.values {
                let py = transform.y(value)
                grid.move(to: CGPoint(x: rect.minX, y: py))
                grid.addLine(to: CGPoint(x: rect.maxX, y: py))
            }
            context.stroke(grid, with: .color(appearance.grid), lineWidth: 0.7)
        }

        // Section band (waveform mode) and play range brackets (graph mode)
        if let section = overlay.section {
            let band = CGRect(x: transform.x(section.lowerBound), y: rect.minY,
                              width: transform.x(section.upperBound) - transform.x(section.lowerBound), height: rect.height)
            context.fill(Path(band), with: .color(overlay.sectionIsSounding ? appearance.curve.opacity(appearance.isLight ? 0.10 : 0.12) : appearance.highlightBand))
            var edges = Path()
            edges.move(to: CGPoint(x: band.minX, y: rect.minY)); edges.addLine(to: CGPoint(x: band.minX, y: rect.maxY))
            edges.move(to: CGPoint(x: band.maxX, y: rect.minY)); edges.addLine(to: CGPoint(x: band.maxX, y: rect.maxY))
            context.stroke(edges, with: .color(appearance.axis.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        } else if let range = overlay.playRange {
            var brackets = Path()
            for value in [range.lowerBound, range.upperBound] where value > viewport.xMin && value < viewport.xMax {
                let px = transform.x(value)
                brackets.move(to: CGPoint(x: px, y: rect.minY))
                brackets.addLine(to: CGPoint(x: px, y: rect.maxY))
            }
            context.stroke(brackets, with: .color(appearance.axis.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
        }

        drawAxes(in: &context, rect: rect, transform: transform, viewport: viewport, xTicks: xTicks, yTicks: yTicks, appearance: appearance)

        // Curve
        let path = curvePath(curve, transform: transform)
        switch overlay.curve {
        case .full:
            strokeCurve(path, in: &context, appearance: appearance, bright: true)
        case .progressive(let startX, let currentX):
            if appearance.showPreview {
                context.stroke(path, with: .color(appearance.preview), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            let left = transform.x(max(startX, viewport.xMin - viewport.width))
            let right = transform.x(currentX)
            if right > left {
                var clipped = context
                clipped.clip(to: Path(CGRect(x: left, y: fullRect.minY, width: right - left, height: fullRect.height)))
                strokeCurve(path, in: &clipped, appearance: appearance, bright: true)
            }
        }

        // Position line and point
        if appearance.showCursorLine, let cursorX = overlay.cursorX, cursorX >= viewport.xMin, cursorX <= viewport.xMax {
            var line = Path()
            let px = transform.x(cursorX)
            line.move(to: CGPoint(x: px, y: rect.minY))
            line.addLine(to: CGPoint(x: px, y: rect.maxY))
            context.stroke(line, with: .color(appearance.curve.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        if let point = overlay.point {
            drawPoint(point, in: &context, transform: transform, rect: rect, viewport: viewport, appearance: appearance)
        }
    }

    static func curvePath(_ curve: SampledCurve, transform: PlotTransform) -> Path {
        var path = Path()
        for segment in curve.segments {
            guard let first = segment.points.first else { continue }
            if segment.points.count == 1 {
                let p = transform.point(first)
                path.addEllipse(in: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
                continue
            }
            path.move(to: transform.point(first))
            for point in segment.points.dropFirst() {
                path.addLine(to: transform.point(point))
            }
        }
        return path
    }

    private static func strokeCurve(_ path: Path, in context: inout GraphicsContext, appearance: GraphAppearance, bright: Bool) {
        if let glow = appearance.glow {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.stroke(path, with: .color(glow.opacity(0.55)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        context.stroke(path, with: .color(appearance.curve), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        if !appearance.isLight {
            context.stroke(path, with: .color(DemonTheme.greenCore.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawPoint(_ point: GraphPoint, in context: inout GraphicsContext, transform: PlotTransform,
                                  rect: CGRect, viewport: GraphViewport, appearance: GraphAppearance) {
        let raw = transform.point(point)
        let isInside = rect.insetBy(dx: -2, dy: -2).contains(raw)
        let position = CGPoint(x: min(max(raw.x, rect.minX), rect.maxX), y: min(max(raw.y, rect.minY), rect.maxY))
        if !isInside {
            // Edge marker pointing to the off-screen point.
            let marker = DiamondShape().path(in: CGRect(x: position.x - 6, y: position.y - 6, width: 12, height: 12))
            context.stroke(marker, with: .color(appearance.curve), lineWidth: 2)
            return
        }
        if appearance.isLight {
            context.fill(Path(ellipseIn: CGRect(x: position.x - 7, y: position.y - 7, width: 14, height: 14)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: position.x - 5, y: position.y - 5, width: 10, height: 10)), with: .color(DemonTheme.ink))
            return
        }
        context.fill(Path(ellipseIn: CGRect(x: position.x - 18, y: position.y - 18, width: 36, height: 36)),
                     with: .radialGradient(Gradient(colors: [DemonTheme.neonGreen.opacity(0.75), DemonTheme.green.opacity(0.25), .clear]),
                                           center: position, startRadius: 0, endRadius: 18))
        context.fill(Path(ellipseIn: CGRect(x: position.x - 6, y: position.y - 6, width: 12, height: 12)), with: .color(DemonTheme.greenCore))
        context.stroke(Path(ellipseIn: CGRect(x: position.x - 6, y: position.y - 6, width: 12, height: 12)),
                       with: .color(DemonTheme.neonGreen), lineWidth: 1.2)
    }

    private static func drawAxes(in context: inout GraphicsContext, rect: CGRect, transform: PlotTransform, viewport: GraphViewport,
                                 xTicks: AxisTicks, yTicks: AxisTicks, appearance: GraphAppearance) {
        // Axis positions: through the origin if visible, otherwise at the border.
        let xAxisY: CGFloat = (viewport.yMin...viewport.yMax).contains(0) ? transform.y(0) : (viewport.yMin > 0 ? rect.maxY : rect.minY)
        let yAxisX: CGFloat = (viewport.xMin...viewport.xMax).contains(0) ? transform.x(0) : (viewport.xMin > 0 ? rect.minX : rect.maxX)

        var axes = Path()
        axes.move(to: CGPoint(x: rect.minX, y: xAxisY))
        axes.addLine(to: CGPoint(x: rect.maxX, y: xAxisY))
        axes.move(to: CGPoint(x: yAxisX, y: rect.minY))
        axes.addLine(to: CGPoint(x: yAxisX, y: rect.maxY))
        context.stroke(axes, with: .color(appearance.axis), lineWidth: 1.5)

        // Diamond tips at the axis ends (motif of the icon).
        let tip: CGFloat = 7
        for center in [CGPoint(x: rect.minX, y: xAxisY), CGPoint(x: rect.maxX, y: xAxisY),
                       CGPoint(x: yAxisX, y: rect.minY), CGPoint(x: yAxisX, y: rect.maxY)] {
            let diamond = DiamondShape().path(in: CGRect(x: center.x - tip, y: center.y - tip / 1.6, width: tip * 2, height: tip * 1.25))
            context.fill(diamond, with: .color(appearance.axisTip))
        }

        // Ticks and labels
        let labelFont = Font.caption2.weight(.semibold).monospacedDigit()
        let labelsBelow = xAxisY < rect.maxY - 18
        var ticks = Path()
        var lastLabelMaxX = -CGFloat.infinity
        for value in xTicks.values where abs(value) > xTicks.step * 1e-6 || yAxisX < rect.minX + 1 || yAxisX > rect.maxX - 1 {
            let px = transform.x(value)
            guard px > rect.minX + 12, px < rect.maxX - 12 else { continue }
            ticks.move(to: CGPoint(x: px, y: xAxisY - 3))
            ticks.addLine(to: CGPoint(x: px, y: xAxisY + 3))
            let text = context.resolve(Text(NumberText.decimal(value, fractionDigits: xTicks.fractionDigits)).font(labelFont).foregroundStyle(appearance.label))
            let textSize = text.measure(in: CGSize(width: 200, height: 40))
            guard px - textSize.width / 2 > lastLabelMaxX + 4 else { continue }
            lastLabelMaxX = px + textSize.width / 2
            let anchor: UnitPoint = labelsBelow ? .top : .bottom
            context.draw(text, at: CGPoint(x: px, y: labelsBelow ? xAxisY + 5 : xAxisY - 5), anchor: anchor)
        }
        let labelsLeft = yAxisX > rect.minX + 34
        var lastLabelY = CGFloat.infinity
        for value in yTicks.values where abs(value) > yTicks.step * 1e-6 || xAxisY < rect.minY + 1 || xAxisY > rect.maxY - 1 {
            let py = transform.y(value)
            guard py > rect.minY + 10, py < rect.maxY - 10 else { continue }
            ticks.move(to: CGPoint(x: yAxisX - 3, y: py))
            ticks.addLine(to: CGPoint(x: yAxisX + 3, y: py))
            guard lastLabelY - py > 14 else { continue }
            lastLabelY = py
            let text = context.resolve(Text(NumberText.decimal(value, fractionDigits: yTicks.fractionDigits)).font(labelFont).foregroundStyle(appearance.label))
            context.draw(text, at: CGPoint(x: labelsLeft ? yAxisX - 6 : yAxisX + 6, y: py), anchor: labelsLeft ? .trailing : .leading)
        }
        context.stroke(ticks, with: .color(appearance.axis), lineWidth: 1)

        // Axis names
        let axisFont = Font.footnote.weight(.heavy).italic()
        let xName = context.resolve(Text("x").font(axisFont).foregroundStyle(appearance.axisTip))
        context.draw(xName, at: CGPoint(x: rect.maxX - 4, y: xAxisY + (labelsBelow ? 8 : -8)), anchor: labelsBelow ? .topTrailing : .bottomTrailing)
        let yName = context.resolve(Text("y").font(axisFont).foregroundStyle(appearance.axisTip))
        context.draw(yName, at: CGPoint(x: yAxisX + (labelsLeft ? -10 : 10), y: rect.minY + 2), anchor: labelsLeft ? .topTrailing : .topLeading)
    }
}
