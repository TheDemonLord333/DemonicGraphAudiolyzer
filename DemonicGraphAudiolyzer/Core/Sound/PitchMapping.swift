import Foundation

/// The y interval [yLow, yHigh] that is mapped onto [fLow, fHigh].
/// Independent of the visible graph area.
struct PitchRange: Equatable, Sendable {
    var low: Double
    var high: Double
    /// The function is constant over the played x range (then u = 0.5).
    var isConstant: Bool = false
    /// False if the function has no defined value in the played range (silence).
    var hasDefinedValues: Bool = true
    /// The range was determined automatically before the pass.
    var isAutomatic: Bool = false
    /// Automatic mode ignored extreme outliers (1 %/99 % quantiles).
    var ignoredOutliers: Bool = false
}

enum PitchMapper {
    static let automaticSampleCount = 4096

    /// Determines the pitch range automatically from the played x range.
    /// Constant functions get a symmetric range around their value (→ middle pitch);
    /// extreme outliers (e.g. near poles) are ignored via quantiles.
    static func automaticRange(for function: CompiledFormula, xMin: Double, xMax: Double,
                               sampleCount: Int = automaticSampleCount) -> PitchRange {
        guard xMax > xMin, sampleCount >= 2 else {
            return PitchRange(low: -1, high: 1, isConstant: true, hasDefinedValues: false, isAutomatic: true)
        }
        var values: [Double] = []
        values.reserveCapacity(sampleCount + 1)
        let step = (xMax - xMin) / Double(sampleCount)
        for index in 0...sampleCount {
            let y = function(xMin + Double(index) * step)
            if !y.isNaN { values.append(y) }
        }
        guard !values.isEmpty else {
            return PitchRange(low: -1, high: 1, isConstant: true, hasDefinedValues: false, isAutomatic: true)
        }
        values.sort()
        let minimum = values.first!
        let maximum = values.last!
        let tolerance = 1e-9 * max(1, abs(minimum), abs(maximum))
        if maximum - minimum <= tolerance {
            let center = 0.5 * (minimum + maximum)
            return PitchRange(low: center - 1, high: center + 1, isConstant: true, hasDefinedValues: true, isAutomatic: true)
        }
        if let robust = RobustRange.estimate(values), robust.lowerBound > minimum || robust.upperBound < maximum {
            return PitchRange(low: robust.lowerBound, high: robust.upperBound, isConstant: false,
                              hasDefinedValues: true, isAutomatic: true, ignoredOutliers: true)
        }
        return PitchRange(low: minimum, high: maximum, isConstant: false, hasDefinedValues: true, isAutomatic: true)
    }

    /// u = clamp((y − yLow) / (yHigh − yLow), 0, 1)
    @inline(__always)
    static func normalizedPosition(of y: Double, in range: PitchRange) -> Double {
        let span = range.high - range.low
        guard span > 0, y.isFinite else { return 0.5 }
        return min(max((y - range.low) / span, 0), 1)
    }

    /// frequency = fLow · (fHigh / fLow)^u
    @inline(__always)
    static func frequency(forY y: Double, range: PitchRange, low: Double, high: Double) -> Double {
        let u = normalizedPosition(of: y, in: range)
        return low * pow(high / low, u)
    }
}
