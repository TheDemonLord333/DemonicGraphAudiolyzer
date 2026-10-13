import Foundation

struct GraphPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// A connected piece of the curve. Segments are separated by poles, jumps or gaps.
struct GraphSegment: Equatable, Sendable {
    var points: [GraphPoint]
}

/// Result of sampling a function over an x interval.
struct SampledCurve: Equatable, Sendable {
    var xRange: ClosedRange<Double>
    var segments: [GraphSegment]
    /// Range of the finite y values of the uniform base samples.
    var finiteYRange: ClosedRange<Double>?
    /// Outlier-robust y range (1 % / 99 % quantiles if there are extreme outliers).
    var robustYRange: ClosedRange<Double>?
    /// Fraction of base samples that are undefined.
    var undefinedFraction: Double

    static let empty = SampledCurve(xRange: 0...1, segments: [], finiteYRange: nil, robustYRange: nil, undefinedFraction: 1)

    var pointCount: Int { segments.reduce(0) { $0 + $1.points.count } }
}

/// Adaptive function sampler.
///
/// 1. Evaluates the function on a uniform grid (resolution ≈ 2 samples per pixel).
/// 2. Between neighbours with a suspiciously large jump it bisects recursively.
///    If the jump shrinks the function is steep but continuous and the extra points are
///    inserted; if it persists down to the smallest interval it is a discontinuity
///    (pole, step) and the curve is split instead of drawing a false vertical line.
/// 3. At the border of the domain (e.g. sqrt at 0, asin at ±1) the exact edge is located by
///    bisection so that the curve ends at the right place.
enum GraphSampler {
    struct Options: Sendable {
        var baseSamples: Int = 800
        var maximumDepth: Int = 12
        var maximumExtraPoints: Int = 20_000
        /// Jumps larger than this fraction of the visible height are inspected.
        var jumpFraction: Double = 0.08
        /// Visible y range. Derived from the samples (robust range) if nil.
        var visibleYRange: ClosedRange<Double>?
    }

    static func sample(_ function: (Double) -> Double, over xRange: ClosedRange<Double>, options: Options = Options()) -> SampledCurve {
        let lower = xRange.lowerBound
        let upper = xRange.upperBound
        guard lower.isFinite, upper.isFinite, upper > lower else {
            return SampledCurve(xRange: xRange, segments: [], finiteYRange: nil, robustYRange: nil, undefinedFraction: 1)
        }
        let count = max(16, options.baseSamples)
        let step = (upper - lower) / Double(count)
        var xs = [Double](repeating: 0, count: count + 1)
        var ys = [Double](repeating: 0, count: count + 1)
        for index in 0...count {
            let x = index == count ? upper : lower + Double(index) * step
            xs[index] = x
            ys[index] = finite(function(x))
        }

        let finiteValues = ys.filter { !$0.isNaN }
        let finiteRange: ClosedRange<Double>? = finiteValues.isEmpty ? nil : (finiteValues.min()!...finiteValues.max()!)
        let robustRange = RobustRange.estimate(finiteValues)
        let undefinedFraction = 1 - Double(finiteValues.count) / Double(ys.count)

        // Refinement only matters near the visible band: two points that are both far above
        // (or both far below) the visible area are off-screen and simply connected. Without this
        // rule every interval next to a pole would look like a jump at any resolution.
        let reference = options.visibleYRange ?? robustRange ?? (-1...1)
        var height = reference.upperBound - reference.lowerBound
        if !(height > 0) || !height.isFinite { height = 1 }
        let band = Band(low: reference.lowerBound - height, high: reference.upperBound + height,
                        threshold: height * options.jumpFraction)

        var builder = SegmentBuilder()
        var budget = options.maximumExtraPoints
        let minimumWidth = step / Double(1 << options.maximumDepth)

        for index in 0...count {
            let x = xs[index]
            let y = ys[index]
            if index == 0 {
                if !y.isNaN { builder.add(GraphPoint(x: x, y: y)) }
                continue
            }
            let previousX = xs[index - 1]
            let previousY = ys[index - 1]
            switch (previousY.isNaN, y.isNaN) {
            case (false, false):
                if band.needsRefinement(previousY, y) {
                    refine(function, x0: previousX, y0: previousY, x1: x, y1: y, band: band,
                           minimumWidth: minimumWidth, depth: 0, maximumDepth: options.maximumDepth,
                           budget: &budget, builder: &builder)
                }
                builder.add(GraphPoint(x: x, y: y))
            case (false, true):
                // Leaving the domain: locate the last defined point.
                if let edge = domainEdge(function, defined: previousX, undefined: x) {
                    builder.add(edge)
                }
                builder.breakSegment()
            case (true, false):
                // Entering the domain: locate the first defined point.
                builder.breakSegment()
                if let edge = domainEdge(function, defined: x, undefined: previousX) {
                    builder.add(edge)
                }
                builder.add(GraphPoint(x: x, y: y))
            case (true, true):
                builder.breakSegment()
            }
        }
        builder.breakSegment()
        return SampledCurve(xRange: xRange,
                            segments: builder.segments,
                            finiteYRange: finiteRange,
                            robustYRange: robustRange,
                            undefinedFraction: undefinedFraction)
    }

    @inline(__always)
    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : .nan
    }

    /// Recursive bisection between two defined points whose values differ strongly.
    /// Appends intermediate points (exclusive of both ends) or splits the segment.
    private static func refine(_ function: (Double) -> Double,
                               x0: Double, y0: Double, x1: Double, y1: Double,
                               band: Band, minimumWidth: Double,
                               depth: Int, maximumDepth: Int,
                               budget: inout Int, builder: inout SegmentBuilder) {
        if budget <= 0 { return }  // pathological functions: just connect
        if depth >= maximumDepth || (x1 - x0) <= minimumWidth {
            // The jump survives at the finest resolution: discontinuity.
            builder.breakSegment()
            return
        }
        let xm = 0.5 * (x0 + x1)
        let ym = finite(function(xm))
        budget -= 1
        if ym.isNaN {
            // A gap inside the interval.
            if let left = domainEdge(function, defined: x0, undefined: xm) {
                builder.add(left)
            }
            builder.breakSegment()
            if let right = domainEdge(function, defined: x1, undefined: xm) {
                builder.add(right)
            }
            return
        }
        if band.needsRefinement(y0, ym) {
            refine(function, x0: x0, y0: y0, x1: xm, y1: ym, band: band, minimumWidth: minimumWidth,
                   depth: depth + 1, maximumDepth: maximumDepth, budget: &budget, builder: &builder)
        }
        builder.add(GraphPoint(x: xm, y: ym))
        if band.needsRefinement(ym, y1) {
            refine(function, x0: xm, y0: ym, x1: x1, y1: y1, band: band, minimumWidth: minimumWidth,
                   depth: depth + 1, maximumDepth: maximumDepth, budget: &budget, builder: &builder)
        }
    }

    /// Bisection for the boundary between a defined and an undefined x.
    /// Returns the defined point closest to the boundary.
    private static func domainEdge(_ function: (Double) -> Double, defined: Double, undefined: Double) -> GraphPoint? {
        var good = defined
        var bad = undefined
        var goodY = finite(function(good))
        guard !goodY.isNaN else { return nil }
        for _ in 0..<40 {
            let mid = 0.5 * (good + bad)
            if mid == good || mid == bad { break }
            let value = finite(function(mid))
            if value.isNaN {
                bad = mid
            } else {
                good = mid
                goodY = value
            }
        }
        return GraphPoint(x: good, y: goodY)
    }
}

/// The y band in which jumps are examined.
private struct Band {
    var low: Double
    var high: Double
    var threshold: Double

    @inline(__always)
    func needsRefinement(_ a: Double, _ b: Double) -> Bool {
        if abs(b - a) <= threshold { return false }
        if a > high && b > high { return false }
        if a < low && b < low { return false }
        return true
    }
}

private struct SegmentBuilder {
    private(set) var segments: [GraphSegment] = []
    private var current: [GraphPoint] = []

    mutating func add(_ point: GraphPoint) {
        if let last = current.last, last.x >= point.x {
            return  // keep points strictly increasing in x
        }
        current.append(point)
    }

    mutating func breakSegment() {
        if !current.isEmpty {
            segments.append(GraphSegment(points: current))
            current.removeAll(keepingCapacity: true)
        }
    }
}

/// Outlier-robust value ranges.
enum RobustRange {
    /// Returns min…max, or the 1 %…99 % quantile range if the extremes are far outside it.
    static func estimate(_ values: [Double]) -> ClosedRange<Double>? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let minimum = sorted.first!
        let maximum = sorted.last!
        guard sorted.count >= 20 else { return minimum...maximum }
        let low = quantile(sorted, 0.01)
        let high = quantile(sorted, 0.99)
        let core = high - low
        if core > 0, (maximum - minimum) > 3 * core {
            return low...high
        }
        return minimum...maximum
    }

    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let position = q * Double(sorted.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(sorted.count - 1, lowerIndex + 1)
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] * (1 - fraction) + sorted[upperIndex] * fraction
    }
}
