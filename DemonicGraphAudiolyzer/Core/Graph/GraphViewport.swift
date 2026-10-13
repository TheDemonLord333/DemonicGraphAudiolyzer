import Foundation

/// The visible part of the coordinate system. Independent of the played x range.
struct GraphViewport: Codable, Equatable, Sendable {
    var xMin: Double
    var xMax: Double
    var yMin: Double
    var yMax: Double

    static let standard = GraphViewport(xMin: -10, xMax: 10, yMin: -1.5, yMax: 1.5)

    /// Smallest allowed extent to avoid degenerate zoom levels.
    static let minimumExtent = 1e-6
    static let maximumExtent = 1e7

    var width: Double { xMax - xMin }
    var height: Double { yMax - yMin }

    var isValid: Bool {
        xMin.isFinite && xMax.isFinite && yMin.isFinite && yMax.isFinite && width > 0 && height > 0
    }

    /// Zooms around an anchor given in data coordinates. `scale > 1` zooms in.
    func zoomed(xScale: Double, yScale: Double, anchorX: Double, anchorY: Double) -> GraphViewport {
        func zoom(_ low: Double, _ high: Double, _ factor: Double, _ anchor: Double) -> (Double, Double) {
            guard factor.isFinite, factor > 0 else { return (low, high) }
            let extent = (high - low) / factor
            let clampedExtent = min(max(extent, Self.minimumExtent), Self.maximumExtent)
            let ratio = (high - low) > 0 ? (anchor - low) / (high - low) : 0.5
            let newLow = anchor - ratio * clampedExtent
            return (newLow, newLow + clampedExtent)
        }
        let (newXMin, newXMax) = zoom(xMin, xMax, xScale, anchorX)
        let (newYMin, newYMax) = zoom(yMin, yMax, yScale, anchorY)
        return GraphViewport(xMin: newXMin, xMax: newXMax, yMin: newYMin, yMax: newYMax)
    }

    func panned(dx: Double, dy: Double) -> GraphViewport {
        GraphViewport(xMin: xMin + dx, xMax: xMax + dx, yMin: yMin + dy, yMax: yMax + dy)
    }

    func withYRange(_ range: ClosedRange<Double>) -> GraphViewport {
        GraphViewport(xMin: xMin, xMax: xMax, yMin: range.lowerBound, yMax: range.upperBound)
    }

    /// Fits the y range to a curve (with margin). Constant curves get ±1 around the value.
    static func fittedYRange(for curve: SampledCurve, margin: Double = 0.12) -> ClosedRange<Double> {
        guard let range = curve.robustYRange ?? curve.finiteYRange else { return -1.5...1.5 }
        var low = range.lowerBound
        var high = range.upperBound
        let extent = high - low
        if extent < 1e-9 * max(1, abs(low)) {
            return (low - 1)...(high + 1)
        }
        low -= extent * margin
        high += extent * margin
        // Keep the x axis visible when it is close to the curve.
        if low > 0, low < extent * 0.5 { low = -extent * margin }
        if high < 0, -high < extent * 0.5 { high = extent * margin }
        return low...high
    }
}

/// "Nice" axis tick positions (1, 2, 5 × 10ⁿ).
struct AxisTicks: Equatable, Sendable {
    var step: Double
    var values: [Double]
    /// Number of fraction digits needed to print the tick labels.
    var fractionDigits: Int

    static func make(lower: Double, upper: Double, targetCount: Int) -> AxisTicks {
        guard lower.isFinite, upper.isFinite, upper > lower, targetCount > 0 else {
            return AxisTicks(step: 1, values: [], fractionDigits: 0)
        }
        let rawStep = (upper - lower) / Double(targetCount)
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let niceFactor: Double
        if normalized < 1.5 {
            niceFactor = 1
        } else if normalized < 3 {
            niceFactor = 2
        } else if normalized < 7 {
            niceFactor = 5
        } else {
            niceFactor = 10
        }
        let step = niceFactor * magnitude
        let first = ceil(lower / step)
        let last = floor(upper / step)
        var values: [Double] = []
        if last >= first, last - first < 1000 {
            var index = first
            while index <= last {
                let value = index * step
                values.append(abs(value) < step * 1e-9 ? 0 : value)
                index += 1
            }
        }
        let digits = max(0, Int(-floor(log10(step) + 1e-9)))
        return AxisTicks(step: step, values: values, fractionDigits: min(digits, 8))
    }
}
