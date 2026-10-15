import Foundation
import Testing
@testable import DemonicGraphAudiolyzer

@Suite("Formel-Synthesizer: Renderkern, Presets und Mixing")
struct SynthRenderTests {
    // MARK: Helpers

    private func plan(_ project: SynthProject, sampleRate: Double = 44_100) throws -> SynthPlan {
        do {
            return try SynthPlan(configuration: SynthRenderConfiguration(project: project, sampleRate: sampleRate))
        } catch let error as SynthPlanError {
            Issue.record("Plan: \(error.message)")
            throw error
        }
    }

    private func render(_ project: SynthProject, sampleRate: Double = 44_100, seconds: Double? = nil) throws -> (left: [Float], right: [Float]) {
        let renderer = SynthRenderer(plan: try plan(project, sampleRate: sampleRate))
        guard let seconds else { return renderer.renderAll() }
        let count = min(renderer.totalFrames, Int(seconds * sampleRate))
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                _ = renderer.render(left: l.baseAddress!, right: r.baseAddress!, capacity: count)
            }
        }
        return (left, right)
    }

    private func sineVoice(_ name: String, hertz: Double, volume: Double = 0) -> SynthVoice {
        var voice = SynthVoice(name: name, color: .green)
        voice.source.waveform = .sine
        voice.pitch = PitchControl(formula: FormulaNumber.literal(hertz), unit: .hertz, baseFrequency: hertz)
        voice.amplitude = AmplitudeControl(formula: "1")
        voice.volumeDecibels = volume
        return voice
    }

    /// Magnitude spectrum (Hann window) of a segment with a power-of-two length.
    private func spectrum(_ samples: ArraySlice<Float>) -> [Double] {
        let size = samples.count
        let fft = FFT(size: size)
        var real = samples.enumerated().map { index, value in
            Double(value) * (0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(size)))
        }
        var imaginary = [Double](repeating: 0, count: size)
        fft.transform(real: &real, imaginary: &imaginary)
        return (0...(size / 2)).map { (real[$0] * real[$0] + imaginary[$0] * imaginary[$0]).squareRoot() }
    }

    /// Frequency from upward zero crossings in a window (interpolated).
    private func zeroCrossingFrequency(_ samples: [Float], from start: Int, to end: Int, sampleRate: Double) -> Double {
        var crossings: [Double] = []
        for index in (start + 1)..<end where samples[index - 1] < 0 && samples[index] >= 0 {
            let a = Double(samples[index - 1])
            let b = Double(samples[index])
            crossings.append(Double(index - 1) + a / (a - b))
        }
        guard crossings.count >= 2 else { return .nan }
        return Double(crossings.count - 1) / ((crossings.last! - crossings.first!) / sampleRate)
    }

    // MARK: Presets

    @Test("Alle Presets kompilieren ohne Fehler und Mehrdeutigkeiten und erzeugen saubere Signale")
    func allPresetsRender() throws {
        #expect(SynthPresets.formulas.count == 20)
        for preset in SynthPresets.all {
            let project = try #require(preset.project, "\(preset.name)")
            let compilation = SynthCompilation(project: project, sampleRate: 22_050)
            #expect(compilation.issues.isEmpty, "\(preset.name): \(compilation.issues.map(\.message))")
            #expect(compilation.voices.allSatisfy { $0.warnings.isEmpty }, "\(preset.name): Warnungen \(compilation.voices.flatMap(\.warnings).map(\.message))")
            #expect(compilation.voices.allSatisfy { $0.autoParameters.isEmpty }, "\(preset.name): unbekannte Namen \(compilation.voices.flatMap(\.autoParameters))")
            #expect(project.voices.count <= SynthProject.maximumVoices)
            #expect(!preset.summary.isEmpty)
            let audio = try render(project, sampleRate: 22_050, seconds: 3)
            let peak = zip(audio.left, audio.right).reduce(Float(0)) { max($0, abs($1.0), abs($1.1)) }
            let energy = audio.left.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, audio.left.count))
            #expect(audio.left.allSatisfy(\.isFinite) && audio.right.allSatisfy(\.isFinite), "\(preset.name)")
            #expect(peak <= 1.0, "\(preset.name): Spitze \(peak)")
            #expect(energy.squareRoot() > 1e-3, "\(preset.name) ist still")
        }
        #expect(Set(BuiltInPresets.all.map(\.id)).count == BuiltInPresets.all.count)
    }

    @Test("808 Slide erreicht Start- und Zielfrequenz, Phase kontinuierlich")
    func slide808Endpoints() throws {
        let project = try #require(SynthPresets.slide808.project)
        let compilation = SynthCompilation(project: project, sampleRate: 44_100)
        let voice = try #require(compilation.voices.first)
        let pitch = try #require(voice.pitch?.program)
        let buffer = EvaluationBuffer(capacity: voice.slotCount)
        func frequency(localTime: Double) -> Double {
            buffer[.localTime] = localTime
            return buffer.evaluate(pitch)
        }
        // f1 = 55, f2 = 82.41, t0 = 0.4, T = 0.35
        #expect(frequency(localTime: 0) == 55)
        #expect(frequency(localTime: 0.4) == 55)
        #expect(abs(frequency(localTime: 0.75) - 82.41) < 1e-9)
        #expect(abs(frequency(localTime: 2) - 82.41) < 1e-9)
        let middle = frequency(localTime: 0.575)
        #expect(abs(middle - 55 * pow(82.41 / 55, 0.5)) < 1e-9, "smoothstep(0,5) = 0,5")

        // Rendered audio: measured pitch before and after the slide.
        var solo = project
        solo.masterLevelDecibels = -6
        let audio = try render(solo, sampleRate: 44_100, seconds: 2)
        let before = zeroCrossingFrequency(audio.left, from: Int(0.05 * 44_100), to: Int(0.38 * 44_100), sampleRate: 44_100)
        let after = zeroCrossingFrequency(audio.left, from: Int(0.85 * 44_100), to: Int(1.9 * 44_100), sampleRate: 44_100)
        #expect(abs(before - 55) / 55 < 0.01, "vorher \(before) Hz")
        #expect(abs(after - 82.41) / 82.41 < 0.01, "nachher \(after) Hz")
        // Continuous phase: no sample-to-sample jump larger than the slope of the sine allows.
        let maximumStep = audio.left.indices.dropFirst().map { abs(audio.left[$0] - audio.left[$0 - 1]) }.max() ?? 1
        #expect(maximumStep < 0.05)
    }

    @Test("Reverse-Bass-Hüllkurve erreicht am Ereignisende den Zielpegel 1")
    func reverseBassEnvelope() throws {
        let preset = try #require(SynthPresets.reverseBass.project)
        let compilation = SynthCompilation(project: preset, sampleRate: 44_100)
        let voice = try #require(compilation.voices.first)
        let amplitude = try #require(voice.amplitude?.program)
        let buffer = EvaluationBuffer(capacity: voice.slotCount)
        func gain(_ localTime: Double) -> Double {
            buffer[.localTime] = localTime
            return buffer.evaluate(amplitude)
        }
        #expect(gain(0.45) == 1, "A(T) = exp(0) = 1")
        #expect(abs(gain(0.45 - 0.09) - exp(-1)) < 1e-12, "eine Zeitkonstante vorher 1/e")
        #expect(abs(gain(0) - exp(-0.45 / 0.09)) < 1e-12)
        #expect(gain(0.46) == 0, "nach dem Ereignis stumm")

        // Rendered with a 1 kHz sine: the level just before T equals the voice gain.
        var project = preset
        var test = project.voices[0]
        test.source.waveform = .sine
        test.pitch = PitchControl(formula: "1000", unit: .hertz, baseFrequency: 1000)
        test.volumeDecibels = 0
        project.voices = [test]
        project.masterLevelDecibels = -6
        let master = pow(10, -6.0 / 20)
        let audio = try render(project, sampleRate: 44_100, seconds: 1)
        let end = Int(0.45 * 44_100)
        let peak = audio.left[(end - 132)..<end].reduce(Float(0)) { max($0, abs($1)) }
        #expect(abs(Double(peak) - master) / master < 0.03, "Pegel vor T: \(peak), erwartet \(master)")
        let silent = audio.left[(end + 220)..<(end + 2_000)].reduce(Float(0)) { max($0, abs($1)) }
        #expect(silent < 1e-3, "nach T stumm: \(silent)")
    }

    // MARK: Mixing

    @Test("Stimmen werden als Signale addiert, nicht als Frequenzen; Headroom 1/√N")
    func multiVoiceMixing() throws {
        var project = SynthProject(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 1), voices: [
            sineVoice("A", hertz: 220, volume: -6), sineVoice("B", hertz: 330, volume: -6)
        ])
        project.masterLevelDecibels = -6
        let both = try render(project)
        var onlyA = project
        onlyA.voices[0].isSolo = true
        var onlyB = project
        onlyB.voices[1].isSolo = true
        let a = try render(onlyA)
        let b = try render(onlyB)
        var maximumError: Float = 0
        for index in both.left.indices {
            // N = 2 → headroom 1/√2; solo renders have N = 1.
            let expected = (a.left[index] + b.left[index]) / 2.0.squareRoot().floatValue
            maximumError = max(maximumError, abs(both.left[index] - expected))
        }
        #expect(maximumError < 1e-5, "Mix = Summe der Einzelsignale · 1/√2 (\(maximumError))")

        let window = Array(both.left[8_192..<(8_192 + 16_384)])
        let magnitudes = spectrum(window[...])
        let binWidth = 44_100.0 / 16_384
        func level(_ hertz: Double) -> Double {
            let bin = Int((hertz / binWidth).rounded())
            return magnitudes[(bin - 2)...(bin + 2)].max() ?? 0
        }
        #expect(level(220) > 100 * level(550), "keine Summenfrequenz 220 + 330")
        #expect(level(330) > 100 * level(550))
    }

    @Test("Panorama mit konstanter Leistung, Mute und Solo")
    func panAndMute() throws {
        var voice = sineVoice("A", hertz: 440)
        voice.pan = -1
        var project = SynthProject(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 1), voices: [voice])
        let hardLeft = try render(project, seconds: 0.5)
        #expect(hardLeft.right.allSatisfy { abs($0) < 1e-6 })
        #expect(hardLeft.left.contains { abs($0) > 0.3 })
        project.voices[0].isMuted = true
        project.voices.append(sineVoice("B", hertz: 330))
        let muted = try render(project, seconds: 0.5)
        let single = try render(SynthProject(tempo: project.tempo, voices: [sineVoice("B", hertz: 330)]), seconds: 0.5)
        #expect(muted.left == single.left, "stumme Stimmen tragen nichts bei und zählen nicht zum Headroom")
    }

    @Test("Weicher Begrenzer: Ausgang nie über 0 dBFS")
    func limiter() throws {
        let loud = (0..<8).map { sineVoice("V\($0)", hertz: 110, volume: 6) }
        var project = SynthProject(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 1), voices: loud)
        project.masterLevelDecibels = 0
        let plan = try plan(project)
        let renderer = SynthRenderer(plan: plan)
        let audio = renderer.renderAll()
        let peak = audio.left.reduce(Float(0)) { max($0, abs($1)) }
        #expect(peak <= 1)
        #expect(peak > 0.95)
        #expect(renderer.limitedFrames > 0)
        #expect(SynthRenderer.limit(0.5).0 == 0.5, "unterhalb der Schwelle unverändert")
        #expect(SynthRenderer.limit(1000).0 <= 1)
        #expect(SynthRenderer.limit(0.95).0 < 0.95, "oberhalb von −1 dBFS weich begrenzt")
    }

    // MARK: Determinism

    @Test("Vorschau = Export: identisch bei jeder Blockgröße (unabhängig von Bildrate und Puffern)")
    func blockSizeIndependence() throws {
        let project = try #require(SynthPresets.finalBoss.project)
        let plan = try plan(project, sampleRate: 22_050)
        let reference = SynthRenderer(plan: plan).renderAll()
        for chunk in [1, 333, 997, 4_096] {
            let renderer = SynthRenderer(plan: plan)
            var left = [Float](repeating: 0, count: renderer.totalFrames)
            var right = [Float](repeating: 0, count: renderer.totalFrames)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    var offset = 0
                    while offset < renderer.totalFrames {
                        offset += renderer.render(left: l.baseAddress! + offset, right: r.baseAddress! + offset,
                                                  capacity: min(chunk, renderer.totalFrames - offset))
                    }
                }
            }
            #expect(left == reference.left, "Blockgröße \(chunk)")
            #expect(right == reference.right, "Blockgröße \(chunk)")
            if chunk == 333 { break }  // one small and one odd size are enough for the long project
        }
    }

    @Test("Rauschen ist über den gespeicherten Seed reproduzierbar")
    func seededNoise() throws {
        var project = try #require(SynthPresets.drumPattern.project)
        let first = try render(project, sampleRate: 22_050, seconds: 2)
        let second = try render(project, sampleRate: 22_050, seconds: 2)
        #expect(first.left == second.left)
        project.noiseSeed &+= 1
        let other = try render(project, sampleRate: 22_050, seconds: 2)
        #expect(first.left != other.left)
    }

    // MARK: Band limitation

    @Test("Bandbegrenzung: Sägezahn, Fourier-Rechteck und Sättigung ohne Aliasing")
    func bandLimitation() throws {
        let sampleRate = 44_100.0
        let size = 16_384
        let binWidth = sampleRate / Double(size)

        /// Ratio (dB) of the strongest component off the harmonic grid of `fundamental` to the strongest harmonic.
        func aliasLevel(_ samples: [Float], fundamental: Double) -> Double {
            let magnitudes = spectrum(samples[8_192..<(8_192 + size)])
            var harmonicPeak = 0.0
            var aliasPeak = 0.0
            for (bin, magnitude) in magnitudes.enumerated() where bin > 3 {
                let frequency = Double(bin) * binWidth
                let nearest = (frequency / fundamental).rounded()
                let distance = abs(frequency - nearest * fundamental)
                if nearest >= 1, distance < 4 * binWidth {
                    harmonicPeak = max(harmonicPeak, magnitude)
                } else if distance > 8 * binWidth {
                    aliasPeak = max(aliasPeak, magnitude)
                }
            }
            return 20 * log10(max(aliasPeak, 1e-12) / harmonicPeak)
        }

        var saw = SynthVoice(name: "Saw", color: .green)
        saw.source.waveform = .sawtooth
        saw.pitch = PitchControl(formula: "3520", unit: .hertz, baseFrequency: 3520)
        let sawAudio = try render(SynthProject(tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 1), voices: [saw]))
        #expect(aliasLevel(sawAudio.left, fundamental: 3520) < -60, "Sägezahn bei 3520 Hz")

        var fourier = try #require(SynthPresets.fourierSquare.project)
        fourier.voices[0].pitch.baseFrequency = 2_000
        fourier.voices[0].parameters = [SynthParameter(name: "N", value: 64, minimum: 1, maximum: 64)]
        let fourierAudio = try render(fourier, seconds: 1)
        #expect(aliasLevel(fourierAudio.left, fundamental: 2_000) < -60, "Fourier-Rechteck: nur Partialtöne unter Nyquist")

        var saturation = try #require(SynthPresets.saturation.project)
        // A per-bar list keeps the formula time-dependent → oversampled formula path (not a static table).
        saturation.voices[0].parameters = [SynthParameter(name: "s", mode: .perBar, values: [40, 40, 40, 40], minimum: 0, maximum: 60)]
        saturation.voices[0].pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 1_760)
        let oversampled = try render(saturation, seconds: 1)
        var naive = saturation
        naive.voices[0].source.oversampling = 1
        let plain = try render(naive, seconds: 1)
        let withFilter = aliasLevel(oversampled.left, fundamental: 1_760)
        let without = aliasLevel(plain.left, fundamental: 1_760)
        #expect(withFilter < without - 10, "Oversampling senkt Aliasing: \(withFilter) dB statt \(without) dB")
        #expect(withFilter < -45)
    }

    @Test("Formelsignale sind trotz Tiefpass samplegenau ausgerichtet")
    func formulaSignalAlignment() throws {
        var direct = SynthVoice(name: "Direkt", color: .green)
        direct.source.kind = .directSignal
        direct.source.signalFormula = "sin(2*pi*441*t)"
        direct.source.oversampling = 4
        direct.source.normalization = .none
        direct.volumeDecibels = 0
        let oscillator = sineVoice("Oszillator", hertz: 441)
        let tempo = TempoSettings(bpm: 120, beatsPerBar: 4, bars: 1)
        let a = try render(SynthProject(tempo: tempo, voices: [direct]), seconds: 0.5)
        let b = try render(SynthProject(tempo: tempo, voices: [oscillator]), seconds: 0.5)
        func correlation(lag: Int) -> Double {
            var sum = 0.0
            for index in 4_000..<20_000 { sum += Double(a.left[index]) * Double(b.left[index + lag]) }
            return sum
        }
        #expect(correlation(lag: 0) > correlation(lag: 1))
        #expect(correlation(lag: 0) > correlation(lag: -1))
    }

    @Test("Shepard-Riser: Teiltöne im Oktavabstand, Pegel an den Rändern null, Summe konstant")
    func shepardRiser() {
        let riser = ShepardRiser(partials: 8, lowestFrequency: 30, cycleSeconds: 2, rising: true)
        for time in stride(from: 0.0, to: 20.0, by: 0.37) {
            let frequencies = (0..<8).map { riser.frequency(partial: $0, time: time) }.sorted()
            for pair in zip(frequencies, frequencies.dropFirst()) {
                #expect(abs(pair.1 / pair.0 - 2) < 1e-9)
            }
            let levels = (0..<8).map { riser.level(partial: $0, time: time) }
            #expect(abs(levels.reduce(0, +) - riser.levelSum) < 1e-9)
            #expect(frequencies.first! >= 30 - 1e-9 && frequencies.last! < 30 * 256)
        }
        #expect(riser.level(partial: 0, time: 0) == 0, "Einblenden bei der tiefsten Lage")
        // Rising: the frequency of a partial grows until it wraps.
        #expect(riser.frequency(partial: 3, time: 1) > riser.frequency(partial: 3, time: 0.5))
    }

    @Test("Parameter pro Takt und Einheiten der Tonhöhe")
    func parametersAndUnits() throws {
        let project = try #require(SynthPresets.kickRoll.project)
        let compilation = SynthCompilation(project: project, sampleRate: 44_100)
        let voice = try #require(compilation.voices.first)
        let pitch = try #require(voice.pitch?.program)
        let buffer = EvaluationBuffer(capacity: voice.slotCount)
        // bar 1: period = 0.5, k = 14 → at x = 4.25 (mod = 0.25): −1.6 + 5·e^(−3.5)
        buffer[.bar] = 1
        buffer[.x] = 4.25
        #expect(abs(buffer.evaluate(pitch) - (-1.6 + 5 * exp(-3.5))) < 1e-12)
        buffer[.bar] = 0
        buffer[.x] = 0.25
        #expect(abs(buffer.evaluate(pitch) - (-1.6 + 5 * exp(-1.75))) < 1e-12)

        let maximum = 20_000.0
        #expect(PitchConversion.frequency(value: 12, unit: .semitones, baseFrequency: 110, quantization: .none, normalized: nil, maximum: maximum) == 220)
        #expect(PitchConversion.frequency(value: -1, unit: .octaves, baseFrequency: 110, quantization: .none, normalized: nil, maximum: maximum) == 55)
        #expect(PitchConversion.frequency(value: 440, unit: .hertz, baseFrequency: 110, quantization: .none, normalized: nil, maximum: maximum) == 440)
        #expect(PitchConversion.frequency(value: -5, unit: .hertz, baseFrequency: 110, quantization: .none, normalized: nil, maximum: maximum) == nil)
        #expect(PitchConversion.quantize(semitones: 5.4, scale: .chromatic) == 5)
        #expect(PitchConversion.quantize(semitones: 5.4, scale: .major) == 5)
        #expect(PitchConversion.quantize(semitones: 5.4, scale: .pentatonic) == 4)
        #expect(PitchConversion.quantize(semitones: 1.2, scale: .naturalMinor) == 2)
        #expect(PitchConversion.quantize(semitones: -1.2, scale: .pentatonic) == 0)
        #expect(PitchConversion.quantize(semitones: -2, scale: .pentatonic) == -3)
        #expect(PitchConversion.gain(value: -0.5, scale: .linear) == 0)
        #expect(PitchConversion.gain(value: -6, scale: .decibels) == pow(10, -0.3))
        #expect(PitchConversion.gain(value: -150, scale: .decibels) == 0)
    }

    @Test("x-Zuordnung pro Projekt: Sekunden, Beats oder freier Durchlauf")
    func xMapping() {
        var project = SynthProject()
        project.tempo = TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2)
        let clock = MusicalClock(tempo: project.tempo, sampleRate: 1_000)
        project.xMapping = .seconds
        #expect(XMappingFunction(project: project, clock: clock).x(atFrame: 1_500) == 1.5)
        project.xMapping = .beats
        #expect(XMappingFunction(project: project, clock: clock).x(atFrame: 1_500) == 3)
        project.xMapping = .freeRange
        project.freeXMin = -10
        project.freeXMax = 10
        #expect(XMappingFunction(project: project, clock: clock).x(atFrame: 2_000) == 0)
    }

    @Test("Fehler werden der richtigen Stimme und Rolle zugeordnet und blockieren nur hörbare Stimmen")
    func issues() throws {
        var broken = SynthVoice(name: "Kaputt", color: .crimson)
        broken.amplitude.formula = "exp(-localTim)"
        broken.useAdvancedEditor = true
        var project = SynthProject(tempo: TempoSettings(), voices: [sineVoice("Gut", hertz: 220), broken])
        var compilation = SynthCompilation(project: project, sampleRate: 44_100)
        #expect(compilation.issues.count == 1)
        #expect(compilation.issues.first?.field == .amplitude)
        #expect(compilation.issues.first?.voiceID == broken.id)
        #expect(compilation.blockingIssue?.contains("Kaputt") == true)
        project.voices[1].isMuted = true
        compilation = SynthCompilation(project: project, sampleRate: 44_100)
        #expect(compilation.blockingIssue == nil, "stumme Stimme mit Fehler blockiert nicht")

        // Simple editor: unknown names become parameters (value 1) instead of errors.
        project.voices[1].isMuted = false
        project.voices[1].useAdvancedEditor = false
        project.voices[1].amplitude.formula = "depth*0.5"
        compilation = SynthCompilation(project: project, sampleRate: 44_100)
        #expect(compilation.issues.isEmpty)
        #expect(compilation.voice(broken.id)?.autoParameters == ["depth"])

        // Duplicate names across project and voice definitions are reported at the voice.
        project.definitions = "k = 2"
        project.voices[1].definitions = "k = 3"
        compilation = SynthCompilation(project: project, sampleRate: 44_100)
        #expect(compilation.issues.first?.field == .voiceDefinitions)
        #expect(compilation.issues.first?.error.kind == .duplicateDefinition)
    }

    @Test("Projekte bleiben über JSON lesbar, fehlende Felder erhalten Standardwerte")
    func codable() throws {
        let project = try #require(SynthPresets.finalBoss.project)
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(SynthProject.self, from: data) == project)
        let minimal = Data(#"{"voices":[{"name":"Alt"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(SynthProject.self, from: minimal)
        #expect(decoded.voices.first?.name == "Alt")
        #expect(decoded.voices.first?.amplitude.formula == "1")
        #expect(decoded.tempo == TempoSettings())
        #expect(decoded.xMapping == .beats)
    }
}

private extension Double {
    var floatValue: Float { Float(self) }
}
