import Foundation

/// Immutable snapshot of everything that determines the generated audio.
/// Preview and export are created from the same configuration type.
struct RenderConfiguration: Equatable, Sendable {
    var formula: ParsedFormula
    var parameters: FormulaParameters
    var settings: SoundSettings
    var sampleRate: Double

    init(formula: ParsedFormula, parameters: FormulaParameters, settings: SoundSettings, sampleRate: Double = 44_100) {
        self.formula = formula
        self.parameters = parameters
        self.settings = settings.clamped()
        self.sampleRate = sampleRate
    }

    /// Number of mono frames of one complete pass.
    var frameCount: Int {
        max(1, Int((settings.duration * sampleRate).rounded()))
    }

    /// Same configuration at another sample rate (e.g. 48 kHz export).
    func withSampleRate(_ rate: Double) -> RenderConfiguration {
        var copy = self
        copy.sampleRate = rate
        return copy
    }
}

/// Values shown while playing.
struct PlaybackReadout: Equatable, Sendable {
    var time: Double
    var progress: Double
    var x: Double
    /// nil if f is undefined at x.
    var y: Double?
    /// Audible frequency (target without glide) or nil while muted.
    var frequency: Double?
}

/// Band-limited single-cycle table built from the function for the waveform mode.
struct WaveformTable: Sendable {
    /// Table used for playback (DC-free, normalised to peak 1, band-limited for the base frequency).
    let table: WavetableData
    /// Down-sampled version for display (one period, values −1 … 1).
    let displayPeriod: [Float]
    /// Fraction of the section where f is undefined (treated as 0).
    let undefinedFraction: Double
    /// Size of the jump between the end and the start of the section, relative to the peak (0 … 2).
    let boundaryJump: Double
    /// Number of harmonics kept by the band limitation.
    let harmonicCount: Int
    /// The section contains no usable signal (constant or undefined) – output is silent.
    let isSilent: Bool
    /// Extreme outliers were softly limited before normalisation.
    let limitedOutliers: Bool
}

enum SoundPlanError: Error, Equatable, Sendable {
    case invalidSettings(String)

    var message: String {
        switch self {
        case .invalidSettings(let text): return text
        }
    }
}

/// Everything needed to render a configuration. Created once (off the main thread) per pass.
struct SoundPlan: Sendable {
    static let tableSize = 4096

    let configuration: RenderConfiguration
    let function: CompiledFormula
    let pitchRange: PitchRange
    let timbreBank: BandLimitedWavetableBank?
    let waveform: WaveformTable?

    var frameCount: Int { configuration.frameCount }
    var sampleRate: Double { configuration.sampleRate }
    var settings: SoundSettings { configuration.settings }

    init(configuration: RenderConfiguration) throws {
        if let issue = configuration.settings.validationIssue {
            throw SoundPlanError.invalidSettings(issue)
        }
        self.configuration = configuration
        let settings = configuration.settings
        let function = configuration.formula.compiled(parameters: configuration.parameters)
        self.function = function

        switch settings.mode {
        case .graph:
            switch settings.pitchRangeMode {
            case .automatic:
                pitchRange = PitchMapper.automaticRange(for: function, xMin: settings.playXMin, xMax: settings.playXMax)
            case .manual:
                pitchRange = PitchRange(low: settings.manualYLow, high: settings.manualYHigh)
            }
            switch settings.timbre {
            case .sine: timbreBank = nil
            case .triangle: timbreBank = TimbreBankCache.shared.bank(for: .triangle, sampleRate: configuration.sampleRate)
            case .rich: timbreBank = TimbreBankCache.shared.bank(for: .rich, sampleRate: configuration.sampleRate)
            }
            waveform = nil
        case .waveform:
            pitchRange = PitchRange(low: -1, high: 1)
            timbreBank = nil
            waveform = Self.makeWaveformTable(function: function,
                                              start: settings.sectionStart,
                                              end: settings.sectionEnd,
                                              baseFrequency: settings.baseFrequency,
                                              sampleRate: configuration.sampleRate)
        }
    }

    /// Builds the periodic, band-limited wavetable for "Formel als Klangwelle".
    ///
    /// 1. Sample f over [start, end) (one period, the end point equals the next start).
    /// 2. Undefined values → 0, DC removal (mean subtraction).
    /// 3. Extreme outliers (peak > 4 × 99.5 % quantile) are limited softly (tanh).
    /// 4. Fourier analysis; harmonics above 0.45·sampleRate / baseFrequency are removed and the
    ///    remaining ones weighted with Lanczos σ-factors. This band-limits the signal including
    ///    the jump between section end and start (which would otherwise alias strongly) and
    ///    keeps Gibbs ringing small.
    /// 5. Normalisation to peak 1 – the output can never clip.
    static func makeWaveformTable(function: CompiledFormula, start: Double, end: Double,
                                  baseFrequency: Double, sampleRate: Double) -> WaveformTable {
        let size = tableSize
        var raw = [Double](repeating: 0, count: size)
        var undefinedCount = 0
        let width = end - start
        for index in 0..<size {
            let value = function(start + width * Double(index) / Double(size))
            if value.isNaN {
                undefinedCount += 1
            } else {
                raw[index] = value
            }
        }
        let undefinedFraction = Double(undefinedCount) / Double(size)
        let endValue = function(end)
        let mean = raw.reduce(0, +) / Double(size)
        var centered = raw.map { $0 - mean }

        // Outlier limiting.
        let magnitudes = centered.map { abs($0) }.sorted()
        let peak = magnitudes.last ?? 0
        let robust = RobustRange.quantile(magnitudes, 0.995)
        var limited = false
        if robust > 0, peak > 4 * robust {
            let limit = 2 * robust
            centered = centered.map { limit * tanh($0 / limit) }
            limited = true
        }

        let fft = FFT(size: size)
        let spectrum = fft.harmonics(of: centered)
        let maximumHarmonic = min(size / 2 - 1, max(1, Int(0.45 * sampleRate / baseFrequency)))
        var cosine = [Double](repeating: 0, count: maximumHarmonic + 1)
        var sine = [Double](repeating: 0, count: maximumHarmonic + 1)
        for k in 1...maximumHarmonic {
            let ratio = Double(k) / Double(maximumHarmonic + 1)
            let sigma = sin(Double.pi * ratio) / (Double.pi * ratio)
            cosine[k] = spectrum.cosine[k] * sigma
            sine[k] = spectrum.sine[k] * sigma
        }
        var period = fft.synthesize(cosine: cosine, sine: sine)
        let bandLimitedPeak = period.reduce(0) { max($0, abs($1)) }
        let silent = bandLimitedPeak < 1e-9
        if !silent {
            period = period.map { $0 / bandLimitedPeak }
        } else {
            period = [Double](repeating: 0, count: size)
        }

        // Jump between section end and start relative to the signal amplitude.
        var boundaryJump = 0.0
        let firstValue = raw[0]
        if !endValue.isNaN, peak > 0, undefinedCount < size {
            boundaryJump = min(2, abs(endValue - firstValue) / max(peak, 1e-12))
        }

        let displayCount = 512
        let stride = size / displayCount
        let display = (0..<displayCount).map { Float(period[$0 * stride]) }

        return WaveformTable(table: WavetableData(period: period),
                             displayPeriod: display,
                             undefinedFraction: undefinedFraction,
                             boundaryJump: boundaryJump,
                             harmonicCount: maximumHarmonic,
                             isSilent: silent,
                             limitedOutliers: limited)
    }

    // MARK: Readout

    /// x(t) = xMin + (xMax − xMin) · t / D
    @inline(__always)
    func x(atFrame frame: Int) -> Double {
        let settings = configuration.settings
        let progress = Double(frame) / Double(frameCount)
        return settings.playXMin + (settings.playXMax - settings.playXMin) * progress
    }

    /// Phase p(t) = frac(baseFrequency · t) of the waveform mode.
    @inline(__always)
    func waveformPhase(atFrame frame: Int) -> Double {
        let cycles = configuration.settings.baseFrequency * Double(frame) / sampleRate
        return cycles - floor(cycles)
    }

    @inline(__always)
    func targetFrequency(forY y: Double) -> Double {
        let settings = configuration.settings
        let frequency = PitchMapper.frequency(forY: y, range: pitchRange, low: settings.frequencyLow, high: settings.frequencyHigh)
        return min(frequency, 0.45 * sampleRate)
    }

    func readout(atTime time: Double) -> PlaybackReadout {
        let duration = Double(frameCount) / sampleRate
        let clampedTime = min(max(time, 0), duration)
        let frame = min(frameCount, Int((clampedTime * sampleRate).rounded()))
        let progress = Double(frame) / Double(frameCount)
        switch configuration.settings.mode {
        case .graph:
            let x = x(atFrame: frame)
            let y = function(x)
            if y.isNaN || !pitchRange.hasDefinedValues {
                return PlaybackReadout(time: clampedTime, progress: progress, x: x, y: y.isNaN ? nil : y, frequency: nil)
            }
            return PlaybackReadout(time: clampedTime, progress: progress, x: x, y: y, frequency: targetFrequency(forY: y))
        case .waveform:
            let settings = configuration.settings
            let phase = waveformPhase(atFrame: frame)
            let x = settings.sectionStart + (settings.sectionEnd - settings.sectionStart) * phase
            let y = function(x)
            let silent = waveform?.isSilent ?? true
            return PlaybackReadout(time: clampedTime, progress: progress, x: x, y: y.isNaN ? nil : y,
                                   frequency: silent ? nil : settings.baseFrequency)
        }
    }
}

/// Caches the band-limited timbre tables per sample rate (built off the main thread,
/// the lock is never taken in the audio render path).
final class TimbreBankCache: @unchecked Sendable {
    static let shared = TimbreBankCache()

    private let lock = NSLock()
    private var banks: [String: BandLimitedWavetableBank] = [:]

    func bank(for timbre: Timbre, sampleRate: Double) -> BandLimitedWavetableBank? {
        let key = "\(timbre.rawValue)-\(Int(sampleRate))"
        lock.lock()
        if let cached = banks[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bank: BandLimitedWavetableBank?
        switch timbre {
        case .sine: bank = nil
        case .triangle: bank = BandLimitedWavetableBank.triangle(sampleRate: sampleRate)
        case .rich: bank = BandLimitedWavetableBank.rich(sampleRate: sampleRate)
        }
        if let bank {
            lock.lock()
            banks[key] = bank
            lock.unlock()
        }
        return bank
    }
}
