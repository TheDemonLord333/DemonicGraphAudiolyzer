import Accessibility
import CoreGraphics
import Foundation
import SwiftUI

/// Interactive coordinate system: draws the curve, animates the playback point from the
/// audio clock, supports pinch zoom, panning and double tap to reset.
struct GraphView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var appearance: GraphAppearance

    @State private var dragBase: GraphViewport?
    @State private var magnifyBase: GraphViewport?

    /// Seconds per cycle of the clearly labelled slow-motion waveform cursor.
    static let slowMotionCycle = 2.0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30.0 : nil, paused: model.phase != .playing)) { _ in
                let snapshot = model.playbackSnapshot()
                let overlay = overlayState(for: snapshot)
                Canvas { context, size in
                    GraphRenderer.draw(in: &context, size: size, curve: model.curve, viewport: model.viewport,
                                       appearance: appearance, overlay: overlay)
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture(size: geometry.size))
            .simultaneousGesture(zoomGesture(size: geometry.size))
            .onTapGesture(count: 2) { model.resetView() }
            .onAppear { model.updatePlotWidth(geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in model.updatePlotWidth(width) }
        }
        .clipShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Graph von f(x) = \(model.formulaDisplayBody)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Mit zwei Fingern zoomen, mit einem Finger verschieben, doppeltippen setzt die Ansicht zurück.")
        .accessibilityChartDescriptor(GraphChartDescriptor(title: "f(x) = \(model.formulaDisplayBody)",
                                                           curve: model.curve, viewport: model.viewport))
        .accessibilityIdentifier("graphCanvas")
    }

    private func overlayState(for snapshot: PlaybackSnapshot?) -> GraphOverlayState {
        let settings = model.settings
        var overlay = GraphOverlayState()
        switch settings.mode {
        case .graph:
            overlay.playRange = settings.playXMin...max(settings.playXMax, settings.playXMin + 1e-9)
        case .waveform:
            overlay.section = settings.sectionStart...max(settings.sectionEnd, settings.sectionStart + 1e-9)
        }
        guard let snapshot else { return overlay }
        switch snapshot.mode {
        case .graph:
            overlay.curve = .progressive(startX: settings.playXMin, currentX: snapshot.readout.x)
            overlay.cursorX = snapshot.readout.x
            if let y = snapshot.readout.y {
                overlay.point = GraphPoint(x: snapshot.readout.x, y: y)
            }
        case .waveform:
            overlay.sectionIsSounding = !snapshot.isPaused
            if model.slowMotionWaveform {
                let phase = (snapshot.time / Self.slowMotionCycle).truncatingRemainder(dividingBy: 1)
                let x = settings.sectionStart + (settings.sectionEnd - settings.sectionStart) * phase
                overlay.cursorX = x
                if let compiled = model.parsedFormula?.compiled(parameters: model.parameters) {
                    let y = compiled(x)
                    if !y.isNaN { overlay.point = GraphPoint(x: x, y: y) }
                }
            }
        }
        return overlay
    }

    private var accessibilityValue: String {
        if let snapshot = model.playbackSnapshot(), snapshot.mode == .graph {
            let x = NumberText.decimal(snapshot.readout.x, fractionDigits: 2)
            guard let y = snapshot.readout.y else { return "x \(x), Definitionslücke, stumm" }
            let frequency = snapshot.readout.frequency.map { NumberText.frequency($0) } ?? "stumm"
            return "x \(x), y \(NumberText.decimal(y, fractionDigits: 2)), \(frequency)"
        }
        let viewport = model.viewport
        return "x von \(NumberText.compact(viewport.xMin)) bis \(NumberText.compact(viewport.xMax)), y von \(NumberText.compact(viewport.yMin)) bis \(NumberText.compact(viewport.yMax))"
    }

    // MARK: Gestures

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard magnifyBase == nil else { return }
                let base = dragBase ?? model.viewport
                if dragBase == nil { dragBase = base }
                let rect = GraphRenderer.plotRect(in: size)
                let dx = -Double(value.translation.width / rect.width) * base.width
                let dy = Double(value.translation.height / rect.height) * base.height
                model.pan(dxData: dx, dyData: dy, from: base)
            }
            .onEnded { _ in dragBase = nil }
    }

    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = magnifyBase ?? model.viewport
                if magnifyBase == nil { magnifyBase = base }
                let transform = PlotTransform(viewport: base, rect: GraphRenderer.plotRect(in: size))
                let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                model.zoom(scale: Double(value.magnification), anchorX: transform.dataX(anchor.x),
                           anchorY: transform.dataY(anchor.y), from: base)
            }
            .onEnded { _ in
                magnifyBase = nil
                dragBase = nil
            }
    }
}

/// VoiceOver "Audiograph" description of the visible curve.
struct GraphChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let curve: SampledCurve
    let viewport: GraphViewport

    func makeChartDescriptor() -> AXChartDescriptor {
        let points = curve.segments.flatMap(\.points).filter { $0.x >= viewport.xMin && $0.x <= viewport.xMax }
        let stride = max(1, points.count / 120)
        let sampled = Swift.stride(from: 0, to: points.count, by: stride).map { points[$0] }
        let xAxis = AXNumericDataAxisDescriptor(title: "x", range: viewport.xMin...viewport.xMax, gridlinePositions: []) { value in
            NumberText.compact(value)
        }
        let yAxis = AXNumericDataAxisDescriptor(title: "y", range: viewport.yMin...viewport.yMax, gridlinePositions: []) { value in
            NumberText.compact(value)
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: true,
                                            dataPoints: sampled.map { AXDataPoint(x: $0.x, y: $0.y) })
        return AXChartDescriptor(title: title,
                                 summary: "Funktionsgraph im sichtbaren Ausschnitt",
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
