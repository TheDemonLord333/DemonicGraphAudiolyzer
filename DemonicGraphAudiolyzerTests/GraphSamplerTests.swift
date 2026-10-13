import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Graphabtastung")
struct GraphSamplerTests {
    private func compiled(_ text: String, parameters: FormulaParameters = FormulaParameters()) throws -> CompiledFormula {
        switch ParsedFormula.parse(text) {
        case .success(let formula): return formula.compiled(parameters: parameters)
        case .failure(let error): throw error
        }
    }

    @Test("Stetige Funktion bildet ein einziges Segment")
    func continuousFunction() throws {
        let f = try compiled("sin(x)")
        let curve = GraphSampler.sample({ f($0) }, over: -10...10)
        #expect(curve.segments.count == 1)
        #expect(curve.undefinedFraction == 0)
        #expect(curve.pointCount >= 800)
        let range = try #require(curve.finiteYRange)
        #expect(range.lowerBound > -1.0001 && range.lowerBound < -0.99)
        #expect(range.upperBound < 1.0001 && range.upperBound > 0.99)
    }

    @Test("Polstellen werden nicht verbunden")
    func polesAreSplit() throws {
        let f = try compiled("1/x")
        let curve = GraphSampler.sample({ f($0) }, over: -1...1, options: .init(baseSamples: 801))
        #expect(curve.segments.count == 2)
        let tan = try compiled("tan(x)")
        let tanCurve = GraphSampler.sample({ tan($0) }, over: -5...5, options: .init(baseSamples: 400, visibleYRange: -5...5))
        // tan has poles at ±π/2 and ±3π/2 inside [-5, 5] → 5 branches.
        #expect(tanCurve.segments.count == 5)
        for segment in tanCurve.segments {
            for pair in zip(segment.points, segment.points.dropFirst()) {
                // No segment may contain a jump from a large positive to a large negative value.
                #expect(!(pair.0.y > 50 && pair.1.y < -50))
            }
        }
    }

    @Test("Sprungstellen (floor) werden als Stufen ohne senkrechte Linien gezeichnet")
    func stepsAreSplit() throws {
        let f = try compiled("floor(x)")
        let curve = GraphSampler.sample({ f($0) }, over: -3.5...3.5, options: .init(baseSamples: 300))
        // Steps at -3, -2, -1, 0, 1, 2, 3 → 8 constant pieces.
        #expect(curve.segments.count == 8)
        for segment in curve.segments {
            let ys = Set(segment.points.map(\.y))
            #expect(ys.count == 1)
        }
    }

    @Test("Viele kleine Stufen werden auch ohne vorgegebenen Sichtbereich getrennt",
          arguments: [(-6.6...6.6, 14), (-20.5...20.5, 42), (-0.5...30.5, 32)])
    func manySmallSteps(range: ClosedRange<Double>, pieces: Int) throws {
        let f = try compiled("floor(x)")
        let curve = GraphSampler.sample({ f($0) }, over: range)
        #expect(curve.segments.count == pieces)
        for segment in curve.segments {
            #expect(Set(segment.points.map(\.y)).count == 1, "Kein senkrechter Verbindungsstrich")
        }
        // Smooth functions must stay in one piece.
        for text in ["sin(x)", "x^3 - 4x", "exp(x/5)", "abs(x)", "sqrt(abs(x))", "sin(4*x)exp(-0.2abs(x))"] {
            let g = try compiled(text)
            #expect(GraphSampler.sample({ g($0) }, over: range).segments.count == 1, "\(text)")
        }
    }

    @Test("Definitionsränder werden genau gefunden")
    func domainEdges() throws {
        let f = try compiled("sqrt(x)")
        let curve = GraphSampler.sample({ f($0) }, over: -2...2, options: .init(baseSamples: 101))
        #expect(curve.segments.count == 1)
        let first = try #require(curve.segments.first?.points.first)
        #expect(abs(first.x) < 1e-6)
        #expect(curve.undefinedFraction > 0.45 && curve.undefinedFraction < 0.55)

        let asin = try compiled("asin(x)")
        let arc = GraphSampler.sample({ asin($0) }, over: -3...3, options: .init(baseSamples: 97))
        #expect(arc.segments.count == 1)
        let points = try #require(arc.segments.first?.points)
        #expect(abs(points.first!.x + 1) < 1e-6)
        #expect(abs(points.last!.x - 1) < 1e-6)
    }

    @Test("Vollständig undefinierte Funktion liefert keine Segmente")
    func fullyUndefined() throws {
        let f = try compiled("sqrt(-1-x^2)")
        let curve = GraphSampler.sample({ f($0) }, over: -5...5)
        #expect(curve.segments.isEmpty)
        #expect(curve.undefinedFraction == 1)
        #expect(curve.finiteYRange == nil)
    }

    @Test("Ausreißer verzerren den robusten y-Bereich nicht")
    func robustRange() throws {
        let f = try compiled("tan(x)")
        let curve = GraphSampler.sample({ f($0) }, over: -10...10)
        let robust = try #require(curve.robustYRange)
        let full = try #require(curve.finiteYRange)
        #expect(robust.upperBound - robust.lowerBound < (full.upperBound - full.lowerBound) / 3)
    }

    @Test("Achsenteilung mit runden Werten")
    func axisTicks() {
        let ticks = AxisTicks.make(lower: -10, upper: 10, targetCount: 8)
        #expect(ticks.step == 2 || ticks.step == 2.5 || ticks.step == 5 || ticks.step == 1)
        #expect(ticks.values.contains(0))
        let small = AxisTicks.make(lower: -1.2, upper: 1.2, targetCount: 6)
        #expect(small.step == 0.5)
        #expect(small.fractionDigits == 1)
        #expect(small.values == [-1, -0.5, 0, 0.5, 1])
    }

    @Test("Zoom und Verschieben des Sichtbereichs")
    func viewportZoomAndPan() {
        let viewport = GraphViewport.standard
        let zoomed = viewport.zoomed(xScale: 2, yScale: 1, anchorX: 0, anchorY: 0)
        #expect(abs(zoomed.width - 10) < 1e-12)
        #expect(abs(zoomed.xMin + 5) < 1e-12)
        #expect(zoomed.height == viewport.height)
        let panned = zoomed.panned(dx: 1, dy: -0.5)
        #expect(abs(panned.xMin + 4) < 1e-12)
        #expect(abs(panned.yMin - (viewport.yMin - 0.5)) < 1e-12)
        let extreme = viewport.zoomed(xScale: 1e30, yScale: 1e-30, anchorX: 0, anchorY: 0)
        #expect(extreme.width >= GraphViewport.minimumExtent)
        #expect(extreme.height <= GraphViewport.maximumExtent)
    }

    @Test("y-Bereich einer konstanten Funktion")
    func fitConstant() throws {
        let f = try compiled("3")
        let curve = GraphSampler.sample({ f($0) }, over: -1...1)
        let range = GraphViewport.fittedYRange(for: curve)
        #expect(range.lowerBound < 3 && range.upperBound > 3)
    }
}
