import Foundation

/// One period of a waveform with a guard sample for interpolation (`samples[size] == samples[0]`).
struct WavetableData: Sendable, Equatable {
    let size: Int
    let samples: [Float]

    init(period: [Double]) {
        size = period.count
        var values = period.map { Float($0) }
        values.append(values.first ?? 0)
        samples = values
    }

    /// Linear interpolation; `phase` in cycles, 0 ≤ phase < 1.
    @inline(__always)
    func value(atPhase phase: Double) -> Float {
        let position = phase * Double(size)
        let index = Int(position)
        let fraction = Float(position - Double(index))
        let safeIndex = min(max(index, 0), size - 1)
        let a = samples[safeIndex]
        let b = samples[safeIndex + 1]
        return a + (b - a) * fraction
    }
}

/// Band-limited wavetables for a fixed harmonic spectrum, one table per third of an octave.
///
/// Each table only contains harmonics that stay below `nyquistLimit` for the *highest*
/// fundamental of its band, so playback is alias-free. Between neighbouring tables the
/// oscillator crossfades so the timbre changes smoothly while the pitch glides.
struct BandLimitedWavetableBank: Sendable {
    static let tableSize = 4096
    static let lowestFundamental = 16.0
    static let bandsPerOctave = 3.0

    let sampleRate: Double
    let nyquistLimit: Double
    /// Upper fundamental frequency covered by each table.
    let bandEdges: [Double]
    let tables: [WavetableData]

    /// - Parameter amplitude: amplitude (cosine, sine) of harmonic n ≥ 1.
    init(sampleRate: Double, amplitude: (Int) -> (cosine: Double, sine: Double)) {
        self.sampleRate = sampleRate
        self.nyquistLimit = 0.45 * sampleRate
        let fft = FFT(size: Self.tableSize)
        var edges: [Double] = []
        var tables: [WavetableData] = []
        var edge = Self.lowestFundamental * pow(2, 1 / Self.bandsPerOctave)
        let maxHarmonicInTable = Self.tableSize / 2 - 1
        while true {
            let harmonicCount = min(maxHarmonicInTable, max(1, Int(nyquistLimit / edge)))
            var cosine = [Double](repeating: 0, count: harmonicCount + 1)
            var sine = [Double](repeating: 0, count: harmonicCount + 1)
            for n in 1...harmonicCount {
                let value = amplitude(n)
                cosine[n] = value.cosine
                sine[n] = value.sine
            }
            var period = fft.synthesize(cosine: cosine, sine: sine)
            let peak = period.reduce(0) { max($0, abs($1)) }
            if peak > 0 {
                period = period.map { $0 / peak }
            }
            edges.append(edge)
            tables.append(WavetableData(period: period))
            if harmonicCount == 1 { break }
            edge *= pow(2, 1 / Self.bandsPerOctave)
        }
        self.bandEdges = edges
        self.tables = tables
    }

    /// Selects the two tables used for `frequency` and the crossfade weight of the upper one.
    ///
    /// Table i is alias-free for fundamentals up to bandEdges[i] = lowest·2^((i+1)/bandsPerOctave).
    /// With q = log2(f/lowest)·bandsPerOctave − 1, every table with index ≥ q is valid.
    /// `lower` is the richest valid table (⌈q⌉); the weight moves continuously towards
    /// the next table so that the switch at band edges has no timbre jump.
    @inline(__always)
    func lookup(frequency: Double) -> (lower: Int, upper: Int, weight: Float) {
        let position = log2(max(frequency, Self.lowestFundamental) / Self.lowestFundamental) * Self.bandsPerOctave
        let q = max(0, position - 1)
        let lower = min(Int(q.rounded(.up)), tables.count - 1)
        let upper = min(lower + 1, tables.count - 1)
        let weight = Float(min(max(1 - (Double(lower) - q), 0), 1))
        return (lower, upper, weight)
    }

    @inline(__always)
    func value(phase: Double, frequency: Double) -> Float {
        let selection = lookup(frequency: frequency)
        let lowerValue = tables[selection.lower].value(atPhase: phase)
        if selection.upper == selection.lower || selection.weight == 0 {
            return lowerValue
        }
        let upperValue = tables[selection.upper].value(atPhase: phase)
        return lowerValue + (upperValue - lowerValue) * selection.weight
    }

    /// Highest harmonic frequency that can occur when playing `frequency` (for tests).
    func highestHarmonicFrequency(forFundamental frequency: Double) -> Double {
        let index = lookup(frequency: frequency).lower
        let harmonics = min(Self.tableSize / 2 - 1, max(1, Int(nyquistLimit / bandEdges[index])))
        return Double(harmonics) * frequency
    }

    // MARK: Timbres

    /// Band-limited triangle wave (odd harmonics, 1/n², alternating sign).
    static func triangle(sampleRate: Double) -> BandLimitedWavetableBank {
        BandLimitedWavetableBank(sampleRate: sampleRate) { n in
            guard n % 2 == 1 else { return (0, 0) }
            let sign: Double = ((n - 1) / 2) % 2 == 0 ? 1 : -1
            return (0, sign / Double(n * n))
        }
    }

    /// Overtone-rich "demonic" synthesizer timbre: sawtooth-like 1/n spectrum with
    /// slightly weaker even harmonics and a gentle high-frequency roll-off.
    static func rich(sampleRate: Double) -> BandLimitedWavetableBank {
        BandLimitedWavetableBank(sampleRate: sampleRate) { n in
            let evenFactor = n % 2 == 0 ? 0.6 : 1.0
            let rolloff = 1.0 / (1.0 + Double(n) / 48.0)
            return (0, evenFactor * rolloff / Double(n))
        }
    }
}
