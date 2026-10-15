import CoreGraphics
import Foundation
import SwiftUI

/// Options of the synthesizer graph.
struct SynthGraphOptions: Equatable {
    var showTrails = true
    var showSnippet = true
    var showGrid = true
    /// Length of the audio snippet window in milliseconds.
    var snippetMilliseconds: Double = 30
}

/// Data for the audio snippet lane (per-voice signals of the rendered preview).
struct SnippetSource {
    var stems: [(color: VoiceColor, name: String, samples: [Int16])]
    var sampleRate: Double
    /// Audio-rate display curves (unit "Signal"): evaluated at the window's times.
    var displaySignals: [(color: VoiceColor, name: String, value: (Double) -> Double)]
}

/// Draws all lanes of the synthesizer graph into a canvas.
enum SynthGraphRenderer {
    static let titleHeight: CGFloat = 16
    static let leftMargin: CGFloat = 44
    static let laneSpacing: CGFloat = 6

    /// Rectangles of the lanes (and the snippet lane, if any) for a canvas size.
    static func laneRects(count: Int, snippet: Bool, size: CGSize) -> [CGRect] {
        let total = count + (snippet ? 1 : 0)
        guard total > 0 else { return [] }
        let available = size.height - laneSpacing * CGFloat(total - 1)
        let snippetShare: CGFloat = snippet ? 0.8 : 0
        let unit = available / (CGFloat(count) + snippetShare)
        var rects: [CGRect] = []
        var y: CGFloat = 0
        for index in 0..<total {
            let height = (snippet && index == total - 1) ? unit * snippetShare : unit
            rects.append(CGRect(x: 0, y: y, width: size.width, height: height))
            y += height + laneSpacing
        }
        return rects
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, data: SynthGraphData, clock: MusicalClock,
                     cursorFrame: Double?, isPlaying: Bool, appearance: GraphAppearance, options: SynthGraphOptions,
                     snippet: SnippetSource?) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(appearance.background))
        let hasSnippet = options.showSnippet && snippet != nil
        let rects = laneRects(count: data.lanes.count, snippet: hasSnippet, size: size)
        let xRange = data.xRange
        let cursorX = cursorFrame.map { data.mapping.x(atFrame: $0) }

        for (index, lane) in data.lanes.enumerated() {
            let rect = rects[index]
            drawLane(lane, in: &context, rect: rect, data: data, clock: clock, xRange: xRange, cursorX: cursorX,
                     cursorFrame: cursorFrame, isPlaying: isPlaying, appearance: appearance, options: options)
        }
        if hasSnippet, let snippet, let rect = rects.last {
            drawSnippet(snippet, in: &context, rect: rect, cursorFrame: cursorFrame ?? 0, clock: clock,
                        appearance: appearance, options: options)
        }
        if data.lanes.isEmpty && !hasSnippet {
            let text = context.resolve(Text("Keine sichtbare Stimme").font(.callout).foregroundStyle(appearance.label))
            context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
        }
    }

    // MARK: Lanes

    private static func plotRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + leftMargin, y: rect.minY + titleHeight,
               width: max(1, rect.width - leftMargin - 6), height: max(1, rect.height - titleHeight - 4))
    }

    private static func drawLane(_ lane: GraphLane, in context: inout GraphicsContext, rect: CGRect, data: SynthGraphData,
                                 clock: MusicalClock, xRange: ClosedRange<Double>, cursorX: Double?, cursorFrame: Double?,
                                 isPlaying: Bool, appearance: GraphAppearance, options: SynthGraphOptions) {
        let plot = plotRect(rect)
        context.fill(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6),
                     with: .color(appearance.isLight ? Color.black.opacity(0.03) : DemonTheme.blurple.opacity(0.05)))

        // Title
        let title = context.resolve(Text(lane.title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(appearance.isLight ? DemonTheme.ink : DemonTheme.blurpleText))
        context.draw(title, at: CGPoint(x: rect.minX + 6, y: rect.minY + 2), anchor: .topLeading)

        let viewport = GraphViewport(xMin: xRange.lowerBound, xMax: xRange.upperBound, yMin: lane.yRange.lowerBound, yMax: lane.yRange.upperBound)
        let transform = PlotTransform(viewport: viewport, rect: plot)

        drawMusicalGrid(in: &context, plot: plot, data: data, clock: clock, transform: transform, cursorFrame: cursorFrame,
                        isPlaying: isPlaying, appearance: appearance, options: options)

        switch lane.kind {
        case .events:
            drawEvents(in: &context, plot: plot, data: data, clock: clock, transform: transform, cursorFrame: cursorFrame, appearance: appearance)
        case .riser(let voiceID):
            drawRiser(voiceID, in: &context, plot: plot, data: data, clock: clock, appearance: appearance)
        default:
            drawYAxis(lane, in: &context, plot: plot, transform: transform, appearance: appearance)
            for curve in lane.curves {
                drawCurve(curve, in: &context, plot: plot, transform: transform, cursorX: cursorX, isPlaying: isPlaying,
                          appearance: appearance, options: options)
            }
        }

        if let cursorX, cursorX >= xRange.lowerBound, cursorX <= xRange.upperBound {
            var line = Path()
            let px = transform.x(cursorX)
            line.move(to: CGPoint(x: px, y: plot.minY))
            line.addLine(to: CGPoint(x: px, y: plot.maxY))
            context.stroke(line, with: .color(appearance.curve.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private static func drawMusicalGrid(in context: inout GraphicsContext, plot: CGRect, data: SynthGraphData, clock: MusicalClock,
                                        transform: PlotTransform, cursorFrame: Double?, isPlaying: Bool,
                                        appearance: GraphAppearance, options: SynthGraphOptions) {
        let perBar = clock.tempo.beatsPerBar
        let totalBeats = Int(clock.totalBeats.rounded())
        let beatWidth = plot.width / CGFloat(max(1, totalBeats))
        // Highlight of the active bar while playing.
        if let cursorFrame, isPlaying || cursorFrame > 0 {
            let bar = floor(clock.beat(atFrame: cursorFrame) / Double(perBar))
            let start = transform.x(data.mapping.x(atFrame: Double(clock.frame(atBeat: bar * Double(perBar)))))
            let end = transform.x(data.mapping.x(atFrame: Double(clock.frame(atBeat: (bar + 1) * Double(perBar)))))
            context.fill(Path(CGRect(x: start, y: plot.minY, width: max(0, end - start), height: plot.height)),
                         with: .color(appearance.isLight ? Color.black.opacity(0.05) : DemonTheme.green.opacity(0.07)))
        }
        guard options.showGrid else { return }
        var beats = Path()
        var bars = Path()
        for beat in 0...totalBeats {
            let isBar = beat % perBar == 0
            if !isBar && beatWidth < 5 { continue }
            let px = transform.x(data.mapping.x(atFrame: Double(clock.frame(atBeat: Double(beat)))))
            if isBar {
                bars.move(to: CGPoint(x: px, y: plot.minY))
                bars.addLine(to: CGPoint(x: px, y: plot.maxY))
            } else {
                beats.move(to: CGPoint(x: px, y: plot.minY))
                beats.addLine(to: CGPoint(x: px, y: plot.maxY))
            }
        }
        context.stroke(beats, with: .color(appearance.grid), lineWidth: 0.5)
        context.stroke(bars, with: .color(appearance.axis.opacity(0.45)), lineWidth: 1)
        // Bar numbers along the top of the plot (1-based like a score, bar = index + 1).
        let barWidth = beatWidth * CGFloat(perBar)
        if barWidth > 22 {
            for bar in 0..<max(1, clock.tempo.bars) {
                let px = transform.x(data.mapping.x(atFrame: Double(clock.frame(atBeat: Double(bar * perBar)))))
                let label = context.resolve(Text("\(bar + 1)").font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(appearance.label.opacity(0.7)))
                context.draw(label, at: CGPoint(x: px + 3, y: plot.maxY - 1), anchor: .bottomLeading)
            }
        }
    }

    private static func drawYAxis(_ lane: GraphLane, in context: inout GraphicsContext, plot: CGRect, transform: PlotTransform,
                                  appearance: GraphAppearance) {
        let ticks = AxisTicks.make(lower: lane.yRange.lowerBound, upper: lane.yRange.upperBound, targetCount: max(2, Int(plot.height / 28)))
        var lines = Path()
        for value in ticks.values {
            let py = transform.y(value)
            guard py >= plot.minY - 0.5, py <= plot.maxY + 0.5 else { continue }
            lines.move(to: CGPoint(x: plot.minX, y: py))
            lines.addLine(to: CGPoint(x: plot.maxX, y: py))
            let text: String
            if lane.isLogFrequency {
                text = NumberText.compact(exp2(value), maximumFractionDigits: 0)
            } else {
                text = NumberText.decimal(value, fractionDigits: ticks.fractionDigits)
            }
            let label = context.resolve(Text(text).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(appearance.label))
            context.draw(label, at: CGPoint(x: plot.minX - 4, y: py), anchor: .trailing)
        }
        context.stroke(lines, with: .color(appearance.grid), lineWidth: 0.5)
        let unit = context.resolve(Text(lane.unitLabel).font(.system(size: 9, weight: .heavy)).foregroundStyle(appearance.axisTip))
        context.draw(unit, at: CGPoint(x: plot.minX - 4, y: plot.minY - 2), anchor: .bottomTrailing)
    }

    private static func drawCurve(_ curve: LaneCurve, in context: inout GraphicsContext, plot: CGRect, transform: PlotTransform,
                                  cursorX: Double?, isPlaying: Bool, appearance: GraphAppearance, options: SynthGraphOptions) {
        let color = appearance.isLight ? DemonTheme.ink : curve.color.color
        let path = GraphRenderer.curvePath(curve.curve, transform: transform)
        var clipped = context
        clipped.clip(to: Path(plot.insetBy(dx: -1, dy: -2)))
        let dash: [CGFloat] = curve.isDisplayOnly ? [5, 4] : []
        if let cursorX, isPlaying || cursorX > transform.viewport.xMin {
            // Progressive drawing: preview after the cursor, bright up to it.
            clipped.stroke(path, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round, dash: dash))
            let right = transform.x(cursorX)
            var played = clipped
            played.clip(to: Path(CGRect(x: plot.minX, y: plot.minY - 4, width: max(0, right - plot.minX), height: plot.height + 8)))
            played.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: dash))
            // Short glowing trail behind the point.
            if options.showTrails, !appearance.isLight {
                let trail = plot.width * 0.08
                var glow = clipped
                glow.clip(to: Path(CGRect(x: right - trail, y: plot.minY - 4, width: trail, height: plot.height + 8)))
                glow.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4))
                    layer.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            if let y = curve.curve.value(atX: cursorX) {
                let point = CGPoint(x: right, y: min(max(transform.y(y), plot.minY), plot.maxY))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.7), .clear]), center: point, startRadius: 0, endRadius: 9))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(DemonTheme.greenCore))
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(color), lineWidth: 1.2)
            }
        } else {
            if !appearance.isLight {
                clipped.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.stroke(path, with: .color(color.opacity(0.4)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            clipped.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: dash))
        }
    }

    private static func drawEvents(in context: inout GraphicsContext, plot: CGRect, data: SynthGraphData, clock: MusicalClock,
                                   transform: PlotTransform, cursorFrame: Double?, appearance: GraphAppearance) {
        let rows = max(1, data.voiceOrder.count)
        let rowHeight = plot.height / CGFloat(rows)
        let flashFrames = 0.12 * clock.sampleRate
        for (row, voice) in data.voiceOrder.enumerated() {
            guard let events = data.voiceEvents[voice.id] else { continue }
            let y = plot.minY + rowHeight * (CGFloat(row) + 0.5)
            let color = appearance.isLight ? DemonTheme.ink : voice.color.color
            var ticks = Path()
            var flashing = Path()
            for event in events {
                let px = transform.x(data.mapping.x(atFrame: Double(event.frame)))
                let height = rowHeight * 0.32 * CGFloat(max(0.4, event.velocity))
                if let cursorFrame, Double(event.frame) <= cursorFrame, cursorFrame - Double(event.frame) < flashFrames {
                    flashing.addRect(CGRect(x: px - 2, y: y - height, width: 4, height: height * 2))
                } else {
                    ticks.move(to: CGPoint(x: px, y: y - height))
                    ticks.addLine(to: CGPoint(x: px, y: y + height))
                }
            }
            context.stroke(ticks, with: .color(color.opacity(0.75)), lineWidth: 1.4)
            context.fill(flashing, with: .color(DemonTheme.greenCore))
            let label = context.resolve(Text(voice.name).font(.system(size: 9, weight: .bold)).foregroundStyle(color))
            context.draw(label, at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing)
            if let limitedBeat = data.rateLimited[voice.id] {
                let px = transform.x(data.mapping.x(atFrame: clock.framesPerBeat * limitedBeat))
                let note = context.resolve(Text("Rate begrenzt").font(.system(size: 9, weight: .heavy)).foregroundStyle(DemonTheme.danger))
                context.draw(note, at: CGPoint(x: min(px + 3, plot.maxX - 60), y: y - rowHeight * 0.45), anchor: .topLeading)
            }
        }
    }

    private static func drawRiser(_ voiceID: UUID, in context: inout GraphicsContext, plot: CGRect, data: SynthGraphData,
                                  clock: MusicalClock, appearance: GraphAppearance) {
        guard let settings = data.riserSettings[voiceID] else { return }
        let riser = ShepardRiser(partials: settings.partials, lowestFrequency: settings.lowest,
                                 cycleSeconds: settings.cycleBeats * clock.tempo.secondsPerBeat, rising: settings.rising)
        let steps = 240
        let duration = clock.duration
        let color = appearance.isLight ? DemonTheme.ink : settings.color.color
        for partial in 0..<riser.partials {
            var previous: CGPoint?
            for step in 0...steps {
                let time = duration * Double(step) / Double(steps)
                let position = riser.position(partial: partial, time: time)
                let point = CGPoint(x: plot.minX + plot.width * CGFloat(step) / CGFloat(steps),
                                    y: plot.maxY - plot.height * CGFloat(position))
                if let previous, point.y < previous.y + plot.height * 0.5 {
                    var segment = Path()
                    segment.move(to: previous)
                    segment.addLine(to: point)
                    let level = riser.level(partial: partial, time: time)
                    context.stroke(segment, with: .color(color.opacity(0.12 + 0.88 * level)), lineWidth: 1 + 2 * CGFloat(level))
                }
                previous = point
            }
        }
        let low = context.resolve(Text(NumberText.frequency(settings.lowest)).font(.system(size: 9, weight: .semibold)).foregroundStyle(appearance.label))
        context.draw(low, at: CGPoint(x: plot.minX - 4, y: plot.maxY), anchor: .trailing)
        let high = context.resolve(Text(NumberText.frequency(settings.lowest * exp2(Double(riser.partials)))).font(.system(size: 9, weight: .semibold)).foregroundStyle(appearance.label))
        context.draw(high, at: CGPoint(x: plot.minX - 4, y: plot.minY + 6), anchor: .trailing)
    }

    // MARK: Snippet

    private static func drawSnippet(_ snippet: SnippetSource, in context: inout GraphicsContext, rect: CGRect, cursorFrame: Double,
                                    clock: MusicalClock, appearance: GraphAppearance, options: SynthGraphOptions) {
        let plot = plotRect(rect)
        context.fill(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6),
                     with: .color(appearance.isLight ? Color.black.opacity(0.03) : DemonTheme.green.opacity(0.04)))
        let title = context.resolve(Text("AUDIO-AUSSCHNITT").font(.caption2.weight(.heavy)).foregroundStyle(appearance.isLight ? DemonTheme.ink : DemonTheme.blurpleText))
        context.draw(title, at: CGPoint(x: rect.minX + 6, y: rect.minY + 2), anchor: .topLeading)

        let windowSeconds = options.snippetMilliseconds / 1000
        let windowFrames = max(8, Int(windowSeconds * snippet.sampleRate))
        let start = max(0, Int(cursorFrame) - windowFrames)
        // Time axis in milliseconds.
        var axis = Path()
        axis.move(to: CGPoint(x: plot.minX, y: plot.midY))
        axis.addLine(to: CGPoint(x: plot.maxX, y: plot.midY))
        context.stroke(axis, with: .color(appearance.axis.opacity(0.5)), lineWidth: 0.8)
        let stepMs = options.snippetMilliseconds <= 15 ? 2.5 : (options.snippetMilliseconds <= 40 ? 5 : 10)
        var tick = 0.0
        while tick <= options.snippetMilliseconds + 1e-9 {
            let px = plot.minX + plot.width * CGFloat(tick / options.snippetMilliseconds)
            let label = context.resolve(Text("\(NumberText.decimal(tick, fractionDigits: tick == tick.rounded() ? 0 : 1)) ms").font(.system(size: 8, weight: .semibold).monospacedDigit()).foregroundStyle(appearance.label))
            context.draw(label, at: CGPoint(x: px, y: plot.maxY + 1), anchor: .bottom)
            tick += stepMs
        }
        let halfHeight = plot.height * 0.42
        if snippet.stems.isEmpty && snippet.displaySignals.isEmpty {
            let text = context.resolve(Text("Nach dem ersten Abspielen zeigt dieser Bereich das erzeugte Signal (Millisekunden-Achse).")
                .font(.caption2).foregroundStyle(appearance.label))
            context.draw(text, in: plot.insetBy(dx: 8, dy: 8))
            return
        }
        let columns = max(1, Int(plot.width))
        var sum = [Double](repeating: 0, count: windowFrames)
        var sumValid = false
        for stem in snippet.stems {
            guard start + windowFrames <= stem.samples.count else { continue }
            sumValid = true
            for index in 0..<windowFrames {
                sum[index] += Double(stem.samples[start + index]) / 32_767
            }
            drawEnvelope(values: { Double(stem.samples[start + $0]) / 32_767 }, count: windowFrames, columns: columns, plot: plot,
                         halfHeight: halfHeight, color: appearance.isLight ? DemonTheme.ink.opacity(0.5) : stem.color.color.opacity(0.85),
                         lineWidth: 1.2, in: &context)
        }
        if sumValid, snippet.stems.count > 1 {
            let peak = max(1, sum.map(abs).max() ?? 1)
            drawEnvelope(values: { sum[$0] / peak }, count: windowFrames, columns: columns, plot: plot, halfHeight: halfHeight,
                         color: appearance.isLight ? DemonTheme.ink : DemonTheme.greenCore, lineWidth: 2, in: &context)
            let label = context.resolve(Text("Summe (normiert)").font(.system(size: 9, weight: .heavy)).foregroundStyle(appearance.isLight ? DemonTheme.ink : DemonTheme.greenCore))
            context.draw(label, at: CGPoint(x: plot.maxX - 2, y: plot.minY), anchor: .topTrailing)
        }
        for display in snippet.displaySignals {
            let startTime = Double(start) / snippet.sampleRate
            drawEnvelope(values: { display.value(startTime + Double($0) / snippet.sampleRate) }, count: windowFrames, columns: columns,
                         plot: plot, halfHeight: halfHeight, color: display.color.color.opacity(0.9), lineWidth: 1, dash: [3, 3], in: &context)
        }
    }

    /// Min/max per pixel column ("verdichtete" samples), drawn as a connected trace.
    private static func drawEnvelope(values: (Int) -> Double, count: Int, columns: Int, plot: CGRect, halfHeight: CGFloat,
                                     color: Color, lineWidth: CGFloat, dash: [CGFloat] = [], in context: inout GraphicsContext) {
        var path = Path()
        let perColumn = Double(count) / Double(columns)
        for column in 0..<columns {
            let first = Int(Double(column) * perColumn)
            let last = max(first, min(count - 1, Int(Double(column + 1) * perColumn) - 1))
            var low = Double.infinity
            var high = -Double.infinity
            for index in first...last {
                let value = values(index)
                guard value.isFinite else { continue }
                low = min(low, value)
                high = max(high, value)
            }
            guard low.isFinite else { continue }
            let x = plot.minX + CGFloat(column)
            let yHigh = plot.midY - CGFloat(min(max(high, -1.2), 1.2)) * halfHeight
            let yLow = plot.midY - CGFloat(min(max(low, -1.2), 1.2)) * halfHeight
            if column == 0 {
                path.move(to: CGPoint(x: x, y: yHigh))
            } else {
                path.addLine(to: CGPoint(x: x, y: yHigh))
            }
            if yLow - yHigh > 0.5 {
                path.addLine(to: CGPoint(x: x, y: yLow))
            }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round, dash: dash))
    }
}
