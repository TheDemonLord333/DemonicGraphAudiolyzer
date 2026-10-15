import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Klangzuordnung und PCM-Erzeugung")
struct SoundSynthesisTests {
    private func formula(_ text: String) throws -> ParsedFormula {
        switch ParsedFormula.parse(text) {
        case .success(let formula): return formula
        case .failure(let error): throw error
        }
    }

    private func plan(_ text: String, sampleRate: Double = 44_100, parameters: FormulaParameters = FormulaParameters(),
                      configure: (inout SoundSettings) -> Void = { _ in }) throws -> SoundPlan {
        var settings = SoundSettings()
        configure(&settings)
        let configuration = RenderConfiguration(formula: try formula(text), parameters: parameters,
                                                settings: settings, sampleRate: sampleRate)
        return try SoundPlan(configuration: configuration)
    }

    /// Dominant frequency via zero crossings of a segment.
    private func zeroCrossingFrequency(_ samples: ArraySlice<Float>, sampleRate: Double) -> Double {
        var crossings = 0
        var previous = samples.first ?? 0
        for value in samples.dropFirst() {
            if previous < 0, value >= 0 { crossings += 1 }
            previous = value
        }
        return Double(crossings) / (Double(samples.count) / sampleRate)
    }

    // MARK: Frequency mapping

    @Test("Frequenzzuordnung: u = 0 → fLow, u = 1 → fHigh, exponentiell dazwischen")
    func frequencyMapping() {
        let range = PitchRange(low: -1, high: 1)
        #expect(abs(PitchMapper.frequency(forY: -1, range: range, low: 110, high: 880) - 110) < 1e-9)
        #expect(abs(PitchMapper.frequency(forY: 1, range: range, low: 110, high: 880) - 880) < 1e-9)
        // Middle of the range = geometric mean (one and a half octaves above 110 Hz).
        #expect(abs(PitchMapper.frequency(forY: 0, range: range, low: 110, high: 880) - sqrt(110 * 880)) < 1e-9)
        // Values outside the range are clamped.
        #expect(abs(PitchMapper.frequency(forY: 5, range: range, low: 110, high: 880) - 880) < 1e-9)
        #expect(abs(PitchMapper.frequency(forY: -5, range: range, low: 110, high: 880) - 110) < 1e-9)
        // Higher y → higher frequency (monotonic).
        var last = 0.0
        for step in -10...10 {
            let frequency = PitchMapper.frequency(forY: Double(step) / 10, range: range, low: 110, high: 880)
            #expect(frequency > last)
            last = frequency
        }
    }

    @Test("Automatischer Klangbereich: sin(x) → [-1, 1]")
    func automaticRangeSine() throws {
        let f = try formula("sin(x)").compiled(parameters: FormulaParameters())
        let range = PitchMapper.automaticRange(for: f, xMin: -10, xMax: 10)
        #expect(abs(range.low + 1) < 1e-3)
        #expect(abs(range.high - 1) < 1e-3)
        #expect(!range.isConstant)
    }

    @Test("Konstante Funktion → mittlere Tonhöhe")
    func constantFunction() throws {
        let p = try plan("2 + 0*x")
        #expect(p.pitchRange.isConstant)
        let readout = p.readout(atTime: 3)
        let frequency = try #require(readout.frequency)
        #expect(abs(frequency - sqrt(110 * 880)) < 1e-6)
    }

    @Test("Ausreißer (Polstellen) bestimmen den automatischen Bereich nicht")
    func outliersIgnored() throws {
        let f = try formula("tan(x)").compiled(parameters: FormulaParameters())
        let range = PitchMapper.automaticRange(for: f, xMin: -10, xMax: 10)
        #expect(range.ignoredOutliers)
        #expect(range.high < 1000)
    }

    @Test("Klangbereich ist unabhängig vom sichtbaren Ausschnitt und manuell einstellbar")
    func manualRange() throws {
        let p = try plan("x") { settings in
            settings.pitchRangeMode = .manual
            settings.manualYLow = 0
            settings.manualYHigh = 4
        }
        #expect(p.pitchRange.low == 0 && p.pitchRange.high == 4)
        #expect(abs(p.targetFrequency(forY: 4) - 880) < 1e-9)
        #expect(abs(p.targetFrequency(forY: -3) - 110) < 1e-9, "negative y values are valid and clamp to fLow")
    }

    // MARK: PCM

    @Test("Sampleanzahl entspricht der Dauer", arguments: [1.0, 2.5, 10.0])
    func sampleCount(duration: Double) throws {
        let p = try plan("sin(x)") { $0.duration = duration }
        let samples = PCMRenderer(plan: p).renderAll()
        #expect(samples.count == Int((duration * 44_100).rounded()))
    }

    @Test("Alle Samples sind endlich und begrenzt", arguments: ["sin(x)", "tan(x)", "1/x", "floor(x)", "sqrt(x)", "exp(x)", "asin(bx)+c"])
    func finiteAndBounded(text: String) throws {
        for timbre in Timbre.allCases {
            let p = try plan(text, parameters: FormulaParameters(a: 1, b: 0.3, c: 0)) {
                $0.duration = 2
                $0.timbre = timbre
            }
            let samples = PCMRenderer(plan: p).renderAll()
            let limit = Float(p.settings.linearLevel) + 1e-5
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= limit }, "\(text) \(timbre)")
        }
        let wave = try plan(text) {
            $0.mode = .waveform
            $0.duration = 1
            $0.sectionStart = -3
            $0.sectionEnd = 3
        }
        let waveSamples = PCMRenderer(plan: wave).renderAll()
        let limit = Float(wave.settings.linearLevel) + 1e-5
        #expect(waveSamples.allSatisfy { $0.isFinite && abs($0) <= limit }, "\(text) waveform")
    }

    @Test("Ein- und Ausblendung: erstes und letztes Sample sind still")
    func fades() throws {
        let p = try plan("sin(x)") { $0.duration = 1 }
        let samples = PCMRenderer(plan: p).renderAll()
        #expect(abs(samples.first!) < 1e-6)
        #expect(abs(samples.last!) < 1e-3)
        let middle = samples[20_000..<24_000].map { abs($0) }.max() ?? 0
        #expect(middle > 0.5)
    }

    @Test("Konstante Funktion klingt mit der mittleren Frequenz")
    func constantFunctionSound() throws {
        let p = try plan("0*x + 1") { $0.duration = 2 }
        let samples = PCMRenderer(plan: p).renderAll()
        let frequency = zeroCrossingFrequency(samples[10_000..<80_000], sampleRate: 44_100)
        #expect(abs(frequency - sqrt(110 * 880)) < 3)
    }

    @Test("Höhere y-Werte erzeugen höhere Töne")
    func risingPitch() throws {
        let p = try plan("x") { $0.duration = 4 }
        let samples = PCMRenderer(plan: p).renderAll()
        let low = zeroCrossingFrequency(samples[2_000..<12_000], sampleRate: 44_100)
        let high = zeroCrossingFrequency(samples[164_000..<174_000], sampleRate: 44_100)
        #expect(low < 130)
        #expect(high > 750)
    }

    @Test("Definitionslücken werden sanft stummgeschaltet")
    func gapsAreMuted() throws {
        // sqrt(x) is undefined for x < 0: first half silent, second half sounding.
        let p = try plan("sqrt(x)") { $0.duration = 2 }
        let samples = PCMRenderer(plan: p).renderAll()
        let firstHalfPeak = samples[0..<40_000].map { abs($0) }.max() ?? 1
        let secondHalfPeak = samples[50_000..<80_000].map { abs($0) }.max() ?? 0
        #expect(firstHalfPeak == 0)
        #expect(secondHalfPeak > 0.5)
        // The onset is a ramp, not a jump: the first non-zero samples are small.
        let onset = try #require(samples.firstIndex { $0 != 0 })
        #expect(abs(samples[onset]) < 0.01)
    }

    @Test("Blockweises Rendern ist identisch mit vollständigem Rendern (Vorschau = Export)")
    func chunkInvariance() throws {
        for mode in SoundMode.classic {
            let p = try plan("sin(4*x)exp(-0.2abs(x))") {
                $0.mode = mode
                $0.duration = 1.5
                $0.timbre = .rich
            }
            let reference = PCMRenderer(plan: p).renderAll()
            let renderer = PCMRenderer(plan: p)
            var chunked: [Float] = []
            var buffer = [Float](repeating: 0, count: 1_013)
            var sizes = [1, 7, 512, 1_013, 333]
            while !renderer.isFinished {
                let size = sizes.removeFirst()
                sizes.append(size)
                let written = buffer.withUnsafeMutableBufferPointer { renderer.render(into: $0.baseAddress!, capacity: size) }
                chunked.append(contentsOf: buffer[0..<written])
            }
            #expect(chunked == reference, "\(mode)")
        }
    }

    @Test("Gleiche Konfiguration erzeugt bitgleiche Ergebnisse")
    func deterministic() throws {
        let first = PCMRenderer(plan: try plan("sin(x)+0.5sin(2x)") { $0.timbre = .triangle; $0.duration = 1 }).renderAll()
        let second = PCMRenderer(plan: try plan("sin(x)+0.5sin(2x)") { $0.timbre = .triangle; $0.duration = 1 }).renderAll()
        #expect(first == second)
    }

    @Test("Bandbegrenzung: Obertöne bleiben unter der Nyquist-Grenze")
    func bandLimitedBank() {
        let bank = BandLimitedWavetableBank.rich(sampleRate: 44_100)
        for frequency in stride(from: 20.0, through: 9_000, by: 37) {
            #expect(bank.highestHarmonicFrequency(forFundamental: frequency) <= 0.45 * 44_100 + 1e-6, "\(frequency) Hz")
        }
        let triangle = BandLimitedWavetableBank.triangle(sampleRate: 48_000)
        #expect(triangle.highestHarmonicFrequency(forFundamental: 5_000) <= 0.45 * 48_000)
    }

    @Test("Klangwelle: periodisch, gleichanteilfrei, normalisiert")
    func waveformTable() throws {
        let p = try plan("x") {
            $0.mode = .waveform
            $0.sectionStart = 0
            $0.sectionEnd = 1
            $0.baseFrequency = 441
            $0.duration = 1
        }
        let waveform = try #require(p.waveform)
        #expect(!waveform.isSilent)
        #expect(waveform.boundaryJump > 0.9, "x over [0,1] jumps from 1 back to 0")
        let mean = waveform.table.samples.dropLast().reduce(0, +) / Float(waveform.table.size)
        #expect(abs(mean) < 1e-4)
        let peak = waveform.table.samples.map { abs($0) }.max() ?? 0
        #expect(abs(peak - 1) < 1e-4)
        #expect(waveform.harmonicCount == Int(0.45 * 44_100 / 441))
        // 441 Hz at 44.1 kHz: exactly 100 samples per period.
        let samples = PCMRenderer(plan: p).renderAll()
        for index in stride(from: 2_000, to: 40_000, by: 997) {
            #expect(abs(samples[index] - samples[index + 100]) < 1e-4)
        }
        let frequency = zeroCrossingFrequency(samples[5_000..<40_000], sampleRate: 44_100)
        #expect(abs(frequency - 441) < 3)
    }

    @Test("Klangwelle einer konstanten Funktion ist still")
    func silentWaveform() throws {
        let p = try plan("3 + 0*x") { $0.mode = .waveform; $0.duration = 1 }
        #expect(p.waveform?.isSilent == true)
        let samples = PCMRenderer(plan: p).renderAll()
        #expect(samples.allSatisfy { $0 == 0 })
    }

    @Test("Ungültige Bereiche werden gemeldet statt gerendert")
    func invalidSettings() throws {
        #expect(throws: SoundPlanError.self) {
            _ = try plan("x") { $0.playXMin = 5; $0.playXMax = 1 }
        }
        #expect(throws: SoundPlanError.self) {
            _ = try plan("x") { $0.mode = .waveform; $0.sectionStart = 2; $0.sectionEnd = 2 }
        }
    }

    @Test("Dauer wird auf 1 … 120 s begrenzt")
    func durationClamping() throws {
        let long = try plan("x") { $0.duration = 500 }
        #expect(long.frameCount == 120 * 44_100)
        let short = try plan("x") { $0.duration = 0.1 }
        #expect(short.frameCount == 44_100)
    }

    @Test("Ausleseposition folgt x(t) = xMin + (xMax − xMin)·t/D")
    func readout() throws {
        let p = try plan("x^2") { $0.duration = 10 }
        let start = p.readout(atTime: 0)
        #expect(start.x == -10)
        let middle = p.readout(atTime: 5)
        #expect(abs(middle.x) < 1e-9)
        #expect(abs((middle.y ?? 1)) < 1e-9)
        let end = p.readout(atTime: 10)
        #expect(abs(end.x - 10) < 1e-9)
    }
}
