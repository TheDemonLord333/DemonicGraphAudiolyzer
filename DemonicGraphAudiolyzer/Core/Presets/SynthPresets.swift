import Foundation

/// Editable presets of the formula synthesizer, the sequencers, the generators and their
/// combinations. All values (formulas, units, triggers, parameters) can be changed after loading.
///
/// The presets are inspired by mathematical music videos; they implement the described
/// structures with explicit formula roles and do not claim to reproduce any original recording.
enum SynthPresets {
    static let formulas: [SoundPreset] = [
        kickRoll, slide808, reverseBass, quantizedSine, shapeshifter, drumPattern, staircase, saturation,
        fractalSum, chirp, stutter, dampedSpring, reese, hoover, hyperbolicDrop, callAndResponse, wobble,
        tanScreech, fourierSquare, walsh
    ]
    static let sequencers: [SoundPreset] = [fibonacciBass, pascalTriangle, circleOfFifths, tritone]
    static let generators: [SoundPreset] = [pendulums, endlessRiser, accelerating]
    static let combinations: [SoundPreset] = [kickRollCowbell, tritoneHoover, bassDrums, dropScreech, finalBoss]

    static let all: [SoundPreset] = formulas + sequencers + generators + combinations

    // MARK: - Helpers

    private static func presetID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "6D3C8E8A-1F7B-4C1E-9E1A-%012X", 0x100 + number))!
    }

    private static func voiceID(_ preset: Int, _ voice: Int) -> UUID {
        UUID(uuidString: String(format: "6D3C8E8A-1F7B-4C1E-9E1B-%06X%06X", preset, voice))!
    }

    private static func voice(_ preset: Int, _ index: Int, _ name: String, _ color: VoiceColor,
                              _ configure: (inout SynthVoice) -> Void) -> SynthVoice {
        var voice = SynthVoice(name: name, color: color)
        voice.id = voiceID(preset, index)
        configure(&voice)
        return voice
    }

    private static func preset(_ number: Int, _ name: String, _ summary: String, mode: SoundMode = .synthesizer,
                               category: PresetCategory, tempo: TempoSettings, xMapping: XMapping = .beats,
                               voices: [SynthVoice], definitions: String = "", parameters: [SynthParameter] = [],
                               displayCurves: [DisplayCurve] = [], level: Double = -3) -> SoundPreset {
        var project = SynthProject(tempo: tempo, xMapping: xMapping, voices: voices, definitions: definitions, displayCurves: displayCurves)
        project.parameters = parameters
        project.masterLevelDecibels = level
        var settings = SoundSettings()
        settings.mode = mode
        settings.duration = min(SoundSettings.durationRange.upperBound, max(SoundSettings.durationRange.lowerBound, tempo.duration))
        let formula = voices.first.map { $0.source.kind.usesSignalFormula ? $0.source.signalFormula : $0.pitch.formula } ?? "0"
        return SoundPreset(id: presetID(number), name: name, summary: summary, formula: formula,
                           settings: settings, project: project, category: category)
    }

    private static func perBar(_ name: String, _ values: [Double], _ minimum: Double = 0, _ maximum: Double = 10) -> SynthParameter {
        SynthParameter(name: name, mode: .perBar, values: values, minimum: minimum, maximum: maximum)
    }

    private static func constant(_ name: String, _ value: Double, _ minimum: Double = 0, _ maximum: Double = 10) -> SynthParameter {
        SynthParameter(name: name, value: value, minimum: minimum, maximum: maximum)
    }

    // MARK: - 9.1 Kick Roll

    private static func kickRollVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Kick Roll", .green) { v in
            v.summary = "Tonhöhe in Oktaven über 55 Hz: Bei jedem Neustart von mod(x, period) fällt sie exponentiell. Abschnittsweise: period = 1, 0.5, 0.25 mit k = 7, 14, 28."
            v.source.kind = .oscillator
            v.source.waveform = .sine
            v.pitch = PitchControl(formula: "-1.6 + 5exp(-kmod(x, period))", unit: .octaves, baseFrequency: 55)
            v.amplitude = AmplitudeControl(formula: "exp(-0.5*k*mod(x, period))")
            v.parameters = [perBar("period", [1, 0.5, 0.25, 0.25], 0.0625, 2), perBar("k", [7, 14, 28, 28], 1, 64)]
            v.volumeDecibels = -2
        }
    }

    static let kickRoll = preset(
        1, "Kick Roll",
        "Periodisch neu gestarteter, exponentieller Tonhöhenabfall: −1,6 + 5·e^(−k·mod(x, period)) in Oktaven. Takt für Takt werden die Abstände kürzer (Beats → Achtel → Sechzehntel), die eigene Amplitudenhüllkurve klingt mit ab.",
        category: .formulas, tempo: TempoSettings(bpm: 128, beatsPerBar: 4, bars: 4),
        voices: [kickRollVoice(1, 0)])

    // MARK: - 9.2 808 Slide

    static let slide808 = preset(
        2, "808 Slide",
        "Ein 808-Bass gleitet je Takt von f1 nach f2: u = clip((localTime − t0)/T, 0, 1), smooth = 3u² − 2u³, Frequenz = f1·(f2/f1)^smooth. Vor dem Übergang klingt f1, danach f2 – die Phase bleibt durchgehend.",
        category: .formulas, tempo: TempoSettings(bpm: 90, beatsPerBar: 4, bars: 2), xMapping: .seconds,
        voices: [
            voice(2, 0, "808", .amber) { v in
                v.summary = "Tonhöhe in Hz. Startnote f1, Zielnote f2, Startzeit t0 und Slide-Dauer T sind Parameter; die Klangfarbe stellst du beim Oszillator ein."
                v.source.waveform = .sine
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 4
                v.definitions = "u = clip((localTime - t0)/T, 0, 1)\nsmooth = 3u^2 - 2u^3"
                v.parameters = [constant("f1", 55, 20, 400), constant("f2", 82.41, 20, 400),
                                constant("t0", 0.4, 0, 2), constant("T", 0.35, 0.01, 2)]
                v.pitch = PitchControl(formula: "f1*(f2/f1)^smooth", unit: .hertz, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "exp(-0.9*localTime)")
                v.volumeDecibels = -1
            }
        ])

    // MARK: - 9.3 Reverse Bass

    static let reverseBass = preset(
        3, "Reverse Bass",
        "Anschwellende Hüllkurve A = exp((localTime − T)/τ) mit τ = 0,09 s: Sie wächst bis zum Ereignisende auf 1, danach ist die Stimme stumm. Rhythmisch neu gestartet und mit einem Bassoszillator kombiniert. Es wird kein Sample rückwärts abgespielt.",
        category: .formulas, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2), xMapping: .seconds,
        voices: [
            voice(3, 0, "Reverse Bass", .magenta) { v in
                v.summary = "Amplitude (linear): exp((localTime − T)/tau) für 0 ≤ localTime ≤ T, sonst 0. Ereignislänge T = 0,45 s, tau = 0,09 s."
                v.source.waveform = .sawtooth
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 1
                v.parameters = [constant("T", 0.45, 0.05, 2), constant("tau", 0.09, 0.01, 0.5)]
                v.definitions = "notes = [0, 0, 3, -2]"
                v.pitch = PitchControl(formula: "notes[mod(bar*4 + floor(beatInBar), len(notes))]", unit: .semitones, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "if(localTime <= T, exp((localTime - T)/tau), 0)")
            }
        ])

    // MARK: - 9.4 Quantized Sine

    static let quantizedSine = preset(
        4, "Quantized Sine",
        "Eine Mischung zweier Sinusfunktionen wird numerisch mit round gerundet (ganze Halbtöne). Die zweite, stumm geschaltete Stimme zeigt den Unterschied: Sie lässt die Formel ungerundet und quantisiert musikalisch auf eine Skala (Pentatonik, wählbar Chromatisch, Dur, Natürlich Moll).",
        category: .formulas, tempo: TempoSettings(bpm: 110, beatsPerBar: 4, bars: 4),
        voices: [
            voice(4, 0, "Gerundet", .cyan) { v in
                v.summary = "Numerische Rundung: round(…) liefert ganze Halbtöne, unabhängig von einer Tonart."
                v.source.waveform = .triangle
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 0.5
                v.pitch = PitchControl(formula: "round(5*(sin(pi*x/4) + 0.4sin(3pi*x/4)))", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-3*localTime)")
            },
            voice(4, 1, "Skala", .violet) { v in
                v.summary = "Skalenquantisierung: dieselbe Mischung ohne round, auf die Töne der Pentatonik gezogen. Zum Vergleichen Solo einschalten."
                v.isMuted = true
                v.source.waveform = .triangle
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 0.5
                v.pitch = PitchControl(formula: "5*(sin(pi*x/4) + 0.4sin(3pi*x/4))", unit: .semitones, baseFrequency: 220, quantization: .pentatonic)
                v.amplitude = AmplitudeControl(formula: "exp(-3*localTime)")
            }
        ])

    // MARK: - 9.5 Shapeshifter

    static let shapeshifter = preset(
        5, "Shapeshifter",
        "Eine Wellenformel wechselt per Fallunterscheidung Takt für Takt zwischen Sägezahn, Dreieck und exponentiell abklingendem Pluck. Jeder Abschnitt ist als Hilfsfunktion editierbar; Oversampling verhindert Aliasing.",
        category: .formulas, tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 3),
        voices: [
            voice(5, 0, "Shapeshifter", .lime) { v in
                v.summary = "Audiosignal (Wellenformel, x läuft je Periode von 0 bis 1): piecewise wählt saw, tri oder pluck nach mod(bar, 3)."
                v.source.kind = .periodicFormula
                v.source.sectionStart = 0
                v.source.sectionEnd = 1
                v.source.oversampling = 4
                v.definitions = "saw(p) = 2*frac(p) - 1\ntri(p) = 1 - 4*abs(frac(p) - 0.5)\npluck(p) = exp(-6*localBeat)*sin(2*pi*p)"
                v.source.signalFormula = "piecewise(mod(bar, 3) == 0, saw(x), mod(bar, 3) == 1, tri(x), pluck(x))"
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 1
                v.definitions += "\nnotes = [0, 3, 7, 5]"
                v.pitch = PitchControl(formula: "notes[mod(n, len(notes))]", unit: .semitones, baseFrequency: 110)
                v.amplitude = AmplitudeControl(formula: "0.9")
            }
        ])

    // MARK: - 9.6 Drum Pattern

    private static func drumVoices(_ preset: Int, offset: Int = 0, swing: Bool = false) -> [SynthVoice] {
        [
            voice(preset, offset, "Kick", .crimson) { v in
                v.summary = "Synthetische Kick: Sinus mit Tonhöhenabfall und Hüllkurve, samplegenau nach Muster ausgelöst."
                v.source.kind = .drum
                v.source.drum = .kick
                v.source.decayMilliseconds = 420
                v.source.tone = 0.4
                v.trigger.kind = .pattern
                v.trigger.pattern = "x...x...x.x.x..."
                v.trigger.stepBeats = 0.25
                v.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 48)
                v.amplitude = AmplitudeControl(formula: "1")
                v.volumeDecibels = -2
            },
            voice(preset, offset + 1, "Snare", .amber) { v in
                v.summary = "Snare: kurzer Ton plus bandgefiltertes Rauschen (Seed gespeichert, Vorschau = Export)."
                v.source.kind = .drum
                v.source.drum = .snare
                v.source.decayMilliseconds = 220
                v.source.tone = 0.65
                v.trigger.kind = .pattern
                v.trigger.pattern = "....X.......X..x"
                v.trigger.stepBeats = 0.25
                v.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 190)
                v.amplitude = AmplitudeControl(formula: "1")
                v.volumeDecibels = -5
            },
            voice(preset, offset + 2, "Hi-Hat", .cyan) { v in
                v.summary = "Hi-Hat: hochpassgefiltertes Rauschen. Die Amplitude betont mathematisch jeden vierten Schlag: 0,55 + 0,45·(mod(n, 4) == 0)."
                v.source.kind = .drum
                v.source.drum = .hihat
                v.source.decayMilliseconds = 70
                v.source.tone = 0.5
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 0.25
                v.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 440)
                v.amplitude = AmplitudeControl(formula: "0.55 + 0.45*(mod(n, 4) == 0)")
                v.volumeDecibels = -11
                v.pan = 0.25
            }
        ]
    }

    static let drumPattern = preset(
        6, "Drum Pattern",
        "Ein mathematisch gesteuerter Beat aus Kick, Snare und Hi-Hat. Jede Stimme ist ein eigenes synthetisiertes Instrument mit Rauschanteil und Hüllkurve – eine bloße Tonhöhenkurve wäre kein Schlagzeug.",
        category: .formulas, tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 2),
        voices: drumVoices(6))

    // MARK: - 9.7 Staircase

    private static func staircaseVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Staircase", .blurple) { v in
            v.summary = "Index = floor(abs(mod(2x, 8) − 4)) läuft 4, 3, 2, 1, 0, 1, 2, 3 – auf und ab durch die Arpeggio-Liste; transpose wechselt pro Takt."
            v.source.waveform = .rich
            v.trigger.kind = .pattern
            v.trigger.pattern = "x"
            v.trigger.stepBeats = 0.5
            v.definitions = "arp = [0, 3, 7, 10, 12]"
            v.parameters = [perBar("transpose", [0, 5, 7, 3], -12, 12)]
            v.pitch = PitchControl(formula: "arp[floor(abs(mod(2x, 8) - 4))] + transpose", unit: .semitones, baseFrequency: 110)
            v.amplitude = AmplitudeControl(formula: "exp(-4*localTime)")
        }
    }

    static let staircase = preset(
        7, "Staircase",
        "Ein auf- und absteigendes Arpeggio aus abs und floor; eine transponierende Liste verschiebt es pro Takt.",
        category: .formulas, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 4),
        voices: [staircaseVoice(7, 0)])

    // MARK: - 9.8 Saturation

    static let saturation = preset(
        8, "Saturation",
        "atan(s·sin(4πx))/atan(s) sättigt einen Sinus immer stärker: s = 0,5; 2; 8; 40 pro Takt. Für s = 0 wäre der Ausdruck 0/0 – dort gilt der Grenzwert sin(4πx). Achtfaches Oversampling begrenzt das Aliasing der steilen Flanken.",
        category: .formulas, tempo: TempoSettings(bpm: 90, beatsPerBar: 4, bars: 4),
        voices: [
            voice(8, 0, "Sättigung", .crimson) { v in
                v.summary = "Audiosignal (Wellenformel), eine Periode von sin(4πx) ist x = 0 … 0,5."
                v.source.kind = .periodicFormula
                v.source.sectionStart = 0
                v.source.sectionEnd = 0.5
                v.source.oversampling = 8
                v.parameters = [perBar("s", [0.5, 2, 8, 40], 0, 60)]
                v.source.signalFormula = "if(abs(s) < 0.000001, sin(4pi*x), atan(s*sin(4pi*x))/atan(s))"
                v.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 110)
                v.amplitude = AmplitudeControl(formula: "0.8")
            }
        ])

    // MARK: - 9.9 Fractal sum

    static let fractalSum = preset(
        9, "Fraktale Summe",
        "1 + 0,75·Σ 0,55^k·cos(3^k·π·x/2) für k = 0 … N: Mit jedem Takt kommt ein Glied hinzu und die Kurve wird zackiger (Weierstraß-artig). N ist auf 5 begrenzt; bei 55 Hz liegt der höchste Partialton dann unter 14 kHz.",
        category: .formulas, tempo: TempoSettings(bpm: 96, beatsPerBar: 4, bars: 4),
        voices: [
            voice(9, 0, "Fraktal-Tonhöhe", .violet) { v in
                v.summary = "Tonhöhe in Halbtönen: 4·W(x) mit x in Beats."
                v.source.waveform = .triangle
                v.definitions = "W(u) = 1 + 0.75sum(k, 0, N, 0.55^kcos(3^kpiu/2))"
                v.parameters = [perBar("N", [1, 2, 3, 5], 0, 5)]
                v.pitch = PitchControl(formula: "4*W(x)", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "0.7")
                v.volumeDecibels = -9
            },
            voice(9, 1, "Fraktal-Welle", .cyan) { v in
                v.summary = "Dieselbe Summe als Wellenformel: eine Periode ist x = 0 … 4."
                v.source.kind = .periodicFormula
                v.source.sectionStart = 0
                v.source.sectionEnd = 4
                v.source.oversampling = 4
                v.definitions = "W(u) = 1 + 0.75sum(k, 0, N, 0.55^kcos(3^kpiu/2))"
                v.parameters = [perBar("N", [1, 2, 3, 5], 0, 5)]
                v.source.signalFormula = "W(x)"
                v.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "0.8")
            }
        ])

    // MARK: - 9.10 Chirp

    static let chirp = preset(
        10, "Chirp",
        "Oben die quantisierte Kurve 1 + (5/12)·(floor((1 + p/8)·sin(πp²/4)) + 1) mit p = x + 8 als Tonhöhe in Oktaven. Dazu ein echter Audio-Chirp: Die Frequenz f(t) = f0·(f1/f0)^(t/D) wird zur Phase integriert – nicht sin(2π·f(t)·t).",
        category: .formulas, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2),
        voices: [
            voice(10, 0, "Quantisierter Chirp", .lime) { v in
                v.summary = "Tonhöhe in Oktaven über 110 Hz (Schritte von 5/12 Oktave = 5 Halbtöne)."
                v.source.waveform = .square
                v.definitions = "p = x + 8"
                v.pitch = PitchControl(formula: "1 + (5/12)*(floor((1+p/8)sin(pip^2/4))+1)", unit: .octaves, baseFrequency: 110)
                v.amplitude = AmplitudeControl(formula: "0.6")
                v.volumeDecibels = -10
            },
            voice(10, 1, "Audio-Chirp", .amber) { v in
                v.summary = "Frequenz in Hz, exponentiell von f0 nach f1 in D Sekunden; der Oszillator integriert die Phase."
                v.source.waveform = .sine
                v.parameters = [constant("f0", 80, 20, 2000), constant("f1", 1600, 20, 8000), constant("D", 4, 0.5, 30)]
                v.pitch = PitchControl(formula: "f0*(f1/f0)^(t/D)", unit: .hertz, baseFrequency: 80)
                v.amplitude = AmplitudeControl(formula: "0.8")
            }
        ])

    // MARK: - 9.11 Stutter

    static let stutter = preset(
        11, "Stutter",
        "exp(−13·mod(localBeat, 2^(−k))) wiederholt das Ereignis 2-, 4-, 8- oder 16-mal pro Beat (k = 1 … 4 pro Takt). Mit nurLetzter = 1 stottert nur der letzte Beat jedes Takts.",
        category: .formulas, tempo: TempoSettings(bpm: 110, beatsPerBar: 4, bars: 4),
        voices: [
            voice(11, 0, "Stutter", .magenta) { v in
                v.summary = "Amplitude: Fallunterscheidung zwischen Stotter-Hüllkurve und normalem Abklingen."
                v.source.waveform = .sawtooth
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 1
                v.parameters = [perBar("k", [1, 2, 3, 4], 0, 6), constant("nurLetzter", 1, 0, 1)]
                v.definitions = "notes = [0, 3, 5, 7]"
                v.pitch = PitchControl(formula: "notes[mod(n, len(notes))]", unit: .semitones, baseFrequency: 110)
                v.amplitude = AmplitudeControl(formula: "if((nurLetzter == 0) or (beatInBar >= beatsPerBar - 1), exp(-13*mod(localBeat, 2^(-k))), exp(-4*localBeat))")
            }
        ])

    // MARK: - 9.12 Damped spring

    static let dampedSpring = preset(
        12, "Damped Spring",
        "basePitch + 1,3·e^(−2,4·localTime)·cos(6π·localTime): eine gedämpfte Schwingung als Tonhöhenmodulation, bei jedem Anschlag neu gespannt. Ein allgemeiner Differentialgleichungslöser ist dafür nicht nötig.",
        category: .formulas, tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 2), xMapping: .seconds,
        voices: [
            voice(12, 0, "Feder", .green) { v in
                v.summary = "Tonhöhe in Halbtönen über 220 Hz; depth skaliert die Federauslenkung."
                v.source.waveform = .triangle
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 2
                v.parameters = [constant("basePitch", 0, -12, 12)]
                v.pitch = PitchControl(formula: "basePitch + 1.3exp(-2.4localTime)cos(6pi*localTime)", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-1.2*localTime)")
            }
        ])

    // MARK: - 9.13 Reese

    private static func reeseVoices(_ preset: Int) -> [SynthVoice] {
        [
            voice(preset, 0, "Oszillator f", .cyan) { v in
                v.summary = "sin(2π·f·t): Frequenz f in Hz (Projekt-Parameter)."
                v.source.waveform = .sine
                v.pitch = PitchControl(formula: "f", unit: .hertz, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "0.8")
                v.volumeDecibels = -4
            },
            voice(preset, 1, "Oszillator f + delta", .magenta) { v in
                v.summary = "sin(2π·(f + delta)·t): leicht verstimmt; delta wechselt pro Takt (1, 2, 4, 8 Hz)."
                v.source.waveform = .sine
                v.pitch = PitchControl(formula: "f + delta", unit: .hertz, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "0.8")
                v.volumeDecibels = -4
            }
        ]
    }

    static let reese = preset(
        13, "Reese / Schwebung",
        "Zwei leicht verstimmte Oszillatoren sin(2πft) + sin(2π(f + delta)t) werden als getrennte Signale addiert. Die Summe schwebt mit delta Hz: 2·|cos(π·delta·t)| ist die Schwebungshüllkurve (nur Anzeige).",
        category: .formulas, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 4), xMapping: .seconds,
        voices: reeseVoices(13),
        parameters: [constant("f", 55, 20, 400), perBar("delta", [1, 2, 4, 8], 0, 20)],
        displayCurves: [DisplayCurve(name: "Schwebungshüllkurve", formula: "2*abs(cos(pi*delta*t))", color: .lime, unit: .gain)])

    // MARK: - 9.14 Hoover

    private static func hooverVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Hoover", .violet) { v in
            v.summary = "Drei bandbegrenzte Sägezähne, ±22 Cent verstimmt; jede Note beginnt 2 Halbtöne tiefer und schwenkt hoch (Pitch-Scoop)."
            v.source.waveform = .sawtooth
            v.source.unison = 3
            v.source.detuneCents = 22
            v.trigger.kind = .pattern
            v.trigger.pattern = "x.x.x..x"
            v.trigger.stepBeats = 0.5
            v.definitions = "notes = [0, 0, 3, -2]"
            v.pitch = PitchControl(formula: "notes[mod(n, len(notes))] - 2*exp(-localTime/0.06)", unit: .semitones, baseFrequency: 110, glideMilliseconds: 12)
            v.amplitude = AmplitudeControl(formula: "0.85*exp(-1.5*localTime)")
            v.volumeDecibels = -6
        }
    }

    static let hoover = preset(
        14, "Hoover",
        "Der klassische Rave-Hoover: drei gegeneinander verstimmte, bandbegrenzte Sägezahn-Oszillatoren mit kurzem Pitch-Scoop pro Note. Die Verstimmung ist am Oszillator einstellbar.",
        category: .formulas, tempo: TempoSettings(bpm: 140, beatsPerBar: 4, bars: 2),
        voices: [hooverVoice(14, 0)])

    // MARK: - 9.15 Hyperbolic drop

    private static func hyperbolicVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Hyperbolic Drop", .amber) { v in
            v.summary = "Tonhöhe in Halbtönen: 24/(1 + 6·mod(x, 2)) − 12 fällt alle 2 Beats von +12 auf etwa −10 Halbtöne."
            v.source.waveform = .rich
            v.pitch = PitchControl(formula: "24/(1+6*mod(x,2))-12", unit: .semitones, baseFrequency: 110)
            v.amplitude = AmplitudeControl(formula: "exp(-0.9*mod(x, 2))")
            v.volumeDecibels = -5
        }
    }

    static let hyperbolicDrop = preset(
        15, "Hyperbolic Drop",
        "Eine Hyperbel als ausdrücklich konfigurierte Tonhöhensteuerung (Halbtöne relativ zu 110 Hz): schneller Absturz am Anfang jeder Periode, dann langsames Auslaufen.",
        category: .formulas, tempo: TempoSettings(bpm: 128, beatsPerBar: 4, bars: 2),
        voices: [hyperbolicVoice(15, 0)])

    // MARK: - 9.16 Call and response

    static let callAndResponse = preset(
        16, "Call and Response",
        "Innerhalb eines achtschlägigen Musters wählt piecewise zwischen zwei Melodiephrasen: Beats 0 – 3 der Ruf, Beats 4 – 7 die Antwort.",
        category: .formulas, tempo: TempoSettings(bpm: 116, beatsPerBar: 4, bars: 4),
        voices: [
            voice(16, 0, "Ruf und Antwort", .green) { v in
                v.summary = "Tonhöhe: piecewise(mod(beat, 8) < 4, call[…], response[…]) – Achtel-Index floor(2·mod(beat, 4))."
                v.source.waveform = .square
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 0.5
                v.definitions = "call = [0, 3, 5, 7, 5, 3, 0, -2]\nresponse = [7, 10, 12, 10, 7, 5, 3, 5]\ni = floor(2*mod(beat, 4))"
                v.pitch = PitchControl(formula: "piecewise(mod(beat, 8) < 4, call[i], response[i])", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-5*localTime)")
                v.volumeDecibels = -8
            }
        ])

    // MARK: - 9.17 Wobble

    static let wobble = preset(
        17, "Wobble",
        "Ein Bass wird mit wachsender Tiefe moduliert; die Wobble-Rate ist beat-synchron und wechselt pro Takt: 1, 2, 4 und 8 Schwingungen pro Beat.",
        category: .formulas, tempo: TempoSettings(bpm: 140, beatsPerBar: 4, bars: 4),
        voices: [
            voice(17, 0, "Wobble-Bass", .blurple) { v in
                v.summary = "Amplitude: 1 − depth·(0,5 − 0,5·cos(2π·rate·beat)); depth wächst von 0 auf 1."
                v.source.waveform = .sawtooth
                v.source.unison = 2
                v.source.detuneCents = 8
                v.parameters = [perBar("rate", [1, 2, 4, 8], 0.25, 16)]
                v.definitions = "depth = min(1, (beat + 1)/(4*beatsPerBar))"
                v.pitch = PitchControl(formula: "[0, 0, -2, 3][mod(bar, 4)]", unit: .semitones, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "1 - depth*(0.5 - 0.5cos(2pi*rate*beat))")
                v.volumeDecibels = -4
            }
        ])

    // MARK: - 9.18 Tan screech

    private static func tanScreechVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Tan Screech", .crimson) { v in
            v.summary = "Tonhöhe in Halbtönen: clip(3·tan(π(frac(x) − 0,5)), −12, 24). Die Polstellen werden durch clip stabil begrenzt."
            v.source.waveform = .sawtooth
            v.pitch = PitchControl(formula: "clip(3tan(pi(frac(x)-0.5)), -12, 24)", unit: .semitones, baseFrequency: 330)
            v.amplitude = AmplitudeControl(formula: "0.7")
            v.volumeDecibels = -10
        }
    }

    static let tanScreech = preset(
        18, "Tan Screech",
        "Der Tangens kreischt durch seine Polstellen – begrenzt mit clip. Als Tonhöhe stabil; die zweite (stumme) Stimme nutzt dieselbe Kurve als direktes Audiosignal mit 8-fachem Oversampling und Tiefpass.",
        category: .formulas, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2),
        voices: [
            tanScreechVoice(18, 0),
            voice(18, 1, "Tan als Audiosignal", .amber) { v in
                v.summary = "Direktes Signal: dieselbe Funktion 110-mal pro Sekunde durchlaufen. Ohne Bandbegrenzung entstünde starkes Aliasing."
                v.isMuted = true
                v.source.kind = .directSignal
                v.source.oversampling = 8
                v.source.signalFormula = "clip(3tan(pi*(frac(110*t)-0.5)), -12, 24)"
                v.amplitude = AmplitudeControl(formula: "0.6")
                v.volumeDecibels = -12
            }
        ])

    // MARK: - 9.19 Fourier square

    static let fourierSquare = preset(
        19, "Fourier Square",
        "Σ sin((2k − 1)·ω·t)/(2k − 1) für k = 1 … N mit ω = 2π·baseFrequency nähert ein Rechteck an; N = 2, 4, 8, 64 pro Takt. Hörbar werden nur Partialtöne unter der Nyquist-Grenze: K = min(N, floor((nyquist/baseFrequency + 1)/2)).",
        category: .formulas, tempo: TempoSettings(bpm: 90, beatsPerBar: 4, bars: 4), xMapping: .seconds,
        voices: [
            voice(19, 0, "Fourier-Rechteck", .green) { v in
                v.summary = "Direktes Audiosignal, ausdrücklich bandbegrenzt durch K; daher kein Oversampling nötig."
                v.source.kind = .directSignal
                v.source.oversampling = 1
                v.source.normalization = .none
                v.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 110)
                v.parameters = [perBar("N", [2, 4, 8, 64], 1, 64)]
                v.definitions = "omega = 2pibaseFrequency\nK = min(N, floor((nyquist/baseFrequency + 1)/2))"
                v.source.signalFormula = "(4/pi)*sum(k, 1, K, sin((2k-1)omegat)/(2k-1))"
                v.amplitude = AmplitudeControl(formula: "0.7")
            }
        ],
        displayCurves: [
            DisplayCurve(name: "1. Partialton", formula: "(4/pi)*sin(2pi*110*t)", color: .cyan, unit: .signal),
            DisplayCurve(name: "3. Partialton", formula: "(4/pi)*sin(3*2pi*110*t)/3", color: .amber, unit: .signal),
            DisplayCurve(name: "5. Partialton", formula: "(4/pi)*sin(5*2pi*110*t)/5", color: .magenta, unit: .signal)
        ])

    // MARK: - 9.20 Walsh / Rademacher

    static let walsh = preset(
        20, "Walsh / Rademacher",
        "Rademacher-Funktionen r(k, x) = (−1)^floor(2^k·x) springen zwischen −1 und 1; ihr Produkt ist eine Walsh-Funktion. 6·(1 + Π r(k, x)) wechselt zwischen 0 und 12 Halbtönen. Die Potenz von −1 wird für ganzzahlige Exponenten exakt berechnet.",
        category: .formulas, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 4),
        voices: [
            voice(20, 0, "Walsh", .cyan) { v in
                v.summary = "Tonhöhe in Halbtönen; K (Anzahl der Faktoren − 1) steigt pro Takt."
                v.source.waveform = .square
                v.trigger.kind = .pattern
                v.trigger.pattern = "x"
                v.trigger.stepBeats = 0.25
                v.definitions = "r(k,x) = (-1)^floor(2^kx)"
                v.parameters = [perBar("K", [0, 1, 2, 3], 0, 6)]
                v.pitch = PitchControl(formula: "6(1+prod(k, 0, K, r(k,x/2)))", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-6*localTime)")
                v.volumeDecibels = -9
            }
        ])

    // MARK: - 10 Sequencers

    static let fibonacciBass = preset(
        21, "Fibonacci-Bass",
        "Fibonacci-Reste modulo 4 (0, 1, 1, 2, 3, 1, …) wählen Töne aus einer Notenliste. Die Folge wird direkt modulo m berechnet – große Fibonacci-Zahlen entstehen nie. Rhythmus (8 Schritte) und Notenliste (4 Töne) haben verschiedene Längen.",
        category: .sequencers, tempo: TempoSettings(bpm: 124, beatsPerBar: 4, bars: 4),
        voices: [
            voice(21, 0, "Fibonacci mod 4", .green) { v in
                v.summary = "Sequencer-Einstellungen statt Formel: Modul m, Notenliste, Rhythmus. Die Tonhöhenformel note gibt den Ton des Ereignisses weiter."
                v.source.waveform = .sawtooth
                v.trigger.kind = .sequencer
                v.trigger.sequencer.kind = .fibonacci
                v.trigger.sequencer.modulus = 4
                v.trigger.sequencer.notes = [0, 3, 7, 10]
                v.trigger.sequencer.rhythm = "x.xx.x.x"
                v.trigger.sequencer.stepBeats = 0.25
                v.pitch = PitchControl(formula: "note", unit: .semitones, baseFrequency: 55)
                v.amplitude = AmplitudeControl(formula: "exp(-7*localTime)")
                v.volumeDecibels = -4
            }
        ])

    static let pascalTriangle = preset(
        22, "Pascal-Dreieck",
        "Zeile für Zeile des Pascalschen Dreiecks erklingen die Positionen mit ungeradem Binomialkoeffizienten – das Sierpinski-Muster. Die Parität wird mit Bitlogik bestimmt (k & n = k), ohne Fakultäten. Zeilen und gleichzeitige Stimmen sind begrenzt.",
        category: .sequencers, tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 4),
        voices: [
            voice(22, 0, "Pascal mod 2", .violet) { v in
                v.summary = "Polyphon (4 Stimmen): Position k → Ton notes[k mod 5] + 12·⌊k/5⌋."
                v.source.waveform = .triangle
                v.polyphony = 4
                v.trigger.kind = .sequencer
                v.trigger.sequencer.kind = .pascal
                v.trigger.sequencer.rows = 16
                v.trigger.sequencer.maximumVoices = 4
                v.trigger.sequencer.notes = [0, 2, 4, 7, 9]
                v.trigger.sequencer.stepBeats = 0.5
                v.trigger.noteLengthBeats = 0.5
                v.pitch = PitchControl(formula: "note", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-4*localTime)")
                v.volumeDecibels = -8
            }
        ])

    static let circleOfFifths = preset(
        23, "Quintenzirkel",
        "Zwei verschiedene Verfahren: Der chromatische Quintenzirkel durchläuft mit Tonklasse = mod(7n, 12) alle zwölf Töne; die diatonische Quintfolge springt mit Stufe = mod(4n, 7) durch die sieben Stufen der Durtonleiter. Zum Vergleich ist die zweite Stimme stumm – Solo schaltet um.",
        category: .sequencers, tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 3),
        voices: [
            voice(23, 0, "Quintenzirkel mod(7n, 12)", .amber) { v in
                v.source.waveform = .triangle
                v.trigger.kind = .sequencer
                v.trigger.sequencer.kind = .circleOfFifths
                v.trigger.sequencer.stepBeats = 1
                v.pitch = PitchControl(formula: "note", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-2.5*localTime)")
                v.pan = -0.3
            },
            voice(23, 1, "Diatonisch mod(4n, 7)", .cyan) { v in
                v.isMuted = true
                v.source.waveform = .triangle
                v.trigger.kind = .sequencer
                v.trigger.sequencer.kind = .diatonicFifths
                v.trigger.sequencer.stepBeats = 1
                v.pitch = PitchControl(formula: "note", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-2.5*localTime)")
                v.pan = 0.3
            }
        ])

    private static func tritoneVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Tritonus", .crimson) { v in
            v.summary = "Wechselt zwischen f0 und f0·√2 (6 Halbtöne); die Glättung von 90 ms ist der exponentielle Slide."
            v.source.waveform = .rich
            v.trigger.kind = .sequencer
            v.trigger.sequencer.kind = .tritone
            v.trigger.sequencer.stepBeats = 1
            v.pitch = PitchControl(formula: "note", unit: .semitones, baseFrequency: 55, glideMilliseconds: 90)
            v.amplitude = AmplitudeControl(formula: "0.9*exp(-0.8*localTime)")
            v.volumeDecibels = -4
        }
    }

    static let tritone = preset(
        24, "Tritonus",
        "Der „Teufelston“: Wechsel zwischen f0 und f0·√2, optional mit exponentiellem Slide (Glättung der Tonhöhe auf der logarithmischen Frequenzskala).",
        category: .sequencers, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 2),
        voices: [tritoneVoice(24, 0)])

    // MARK: - 11 Pendulums

    static let pendulumNotes: [Double] = [0, 2, 4, 7, 9, 12]
    static let pendulumColors: [VoiceColor] = [.green, .cyan, .blurple, .violet, .magenta, .amber]

    static let pendulums = preset(
        25, "Sechs Pendel",
        "Sechs Pendel mit position = cos(2π·N·beat/16), N = 6 … 11. Beim Mitteldurchgang erklingt ihre Note; nach 16 Beats sind alle wieder in Ausgangsphase. Die Auslösezeitpunkte werden analytisch berechnet – samplegenau und unabhängig von der Bildrate.",
        mode: .pendulum, category: .generators, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 8),
        voices: (0..<6).map { index in
            voice(25, index, "Pendel N = \(6 + index)", pendulumColors[index]) { v in
                v.source.waveform = .sine
                v.trigger.kind = .pendulum
                v.trigger.pendulumCycles = 6 + index
                v.trigger.pendulumPeriodBeats = 16
                v.trigger.pendulumBothDirections = true
                v.pitch = PitchControl(formula: "\(FormulaNumber.literal(pendulumNotes[index]))", unit: .semitones, baseFrequency: 330)
                v.amplitude = AmplitudeControl(formula: "exp(-3*localTime)")
                v.volumeDecibels = -9
                v.pan = -0.6 + 0.24 * Double(index)
            }
        })

    // MARK: - 12 Endless riser

    private static func riserVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Endless Riser", .blurple) { v in
            v.summary = "Acht Teiltöne im Oktavabstand steigen gemeinsam; jeder wird unten weich ein- und oben weich ausgeblendet und beginnt dann wieder unten."
            v.source.kind = .riser
            v.source.riserPartials = 8
            v.source.riserLowestFrequency = 30
            v.source.riserCycleBeats = 4
            v.source.riserRising = true
            v.amplitude = AmplitudeControl(formula: "0.9")
            v.volumeDecibels = -4
        }
    }

    static let endlessRiser = preset(
        26, "Endless Riser",
        "Shepard-/Risset-Riser: mehrere über Oktaven verteilte Stimmen mit weichen Pegelhüllkurven. Es entsteht der psychoakustische Eindruck eines endlos steigenden Klangs – die Frequenzen selbst steigen nicht unbegrenzt.",
        category: .generators, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 8),
        voices: [riserVoice(26, 0)])

    // MARK: - 13 Accelerating repetition

    static let accelerating = preset(
        27, "Beschleunigte Wiederholung",
        "Die Wiederholrate verdoppelt sich mit jedem Takt (2^(beat/beatsPerBar) Ereignisse pro Beat). Die Phase ist das Integral der Rate; ein Ereignis entsteht bei jedem ganzzahligen Phasendurchgang. Über 24 Ereignissen pro Sekunde wird die Rate sichtbar begrenzt.",
        category: .generators, tempo: TempoSettings(bpm: 120, beatsPerBar: 4, bars: 4),
        voices: [
            voice(27, 0, "Beschleunigung", .lime) { v in
                v.summary = "Trigger „Beschleunigung“: Rate in Ereignissen pro Beat; kurzer Pluck pro Ereignis."
                v.source.waveform = .triangle
                v.trigger.kind = .rate
                v.trigger.rateFormula = "2^(beat/beatsPerBar)"
                v.trigger.maximumEventsPerSecond = 24
                v.pitch = PitchControl(formula: "12*min(1, beat/16)", unit: .semitones, baseFrequency: 220)
                v.amplitude = AmplitudeControl(formula: "exp(-25*localTime)")
                v.volumeDecibels = -6
            }
        ])

    // MARK: - 14 Combinations

    private static func cowbellVoice(_ preset: Int, _ index: Int) -> SynthVoice {
        voice(preset, index, "Cowbell", .amber) { v in
            v.summary = "Synthetische Cowbell: zwei Rechteckschwingungen (1 : 1,48) durch einen Bandpass, kurze Hüllkurve. Die Notenfolge notes ist editierbar."
            v.source.kind = .drum
            v.source.drum = .cowbell
            v.source.decayMilliseconds = 260
            v.trigger.kind = .pattern
            v.trigger.pattern = "x..x..x...x.x..."
            v.trigger.stepBeats = 0.25
            v.definitions = "notes = [0, 0, 7, 5]"
            v.pitch = PitchControl(formula: "notes[mod(n, len(notes))]", unit: .semitones, baseFrequency: 540)
            v.amplitude = AmplitudeControl(formula: "1")
            v.volumeDecibels = -10
            v.pan = 0.3
        }
    }

    static let kickRollCowbell = preset(
        28, "Kick Roll + Cowbell",
        "Der Kick Roll mit einer synthetisierten Cowbell und ihrer eigenen Notenfolge. Mute, Solo, Lautstärke und Graphsichtbarkeit sind pro Stimme einstellbar.",
        category: .combinations, tempo: TempoSettings(bpm: 128, beatsPerBar: 4, bars: 4),
        voices: [kickRollVoice(28, 0), cowbellVoice(28, 1)])

    static let tritoneHoover = preset(
        29, "Tritone Bass + Hoover",
        "Tritonus-Bass (f0 ↔ f0·√2 mit Slide) unter dem verstimmten Hoover – zwei Stimmen, als Signale gemischt.",
        category: .combinations, tempo: TempoSettings(bpm: 140, beatsPerBar: 4, bars: 2),
        voices: [tritoneVoice(29, 0), hooverVoice(29, 1)])

    static let bassDrums = preset(
        30, "Bass + Drum Pattern",
        "Das Staircase-Arpeggio als Bass über dem mathematischen Drum Pattern.",
        category: .combinations, tempo: TempoSettings(bpm: 100, beatsPerBar: 4, bars: 4),
        voices: {
            var bass = staircaseVoice(30, 0)
            bass.pitch.baseFrequency = 55
            bass.source.waveform = .sawtooth
            bass.volumeDecibels = -7
            return [bass] + drumVoices(30, offset: 1)
        }())

    static let dropScreech = preset(
        31, "Hyperbolic Drop + Tan Screech",
        "Der hyperbolische Absturz und der begrenzte Tangens-Kreischer laufen gleichzeitig – getrennte Bahnen, gemeinsamer Zeitcursor.",
        category: .combinations, tempo: TempoSettings(bpm: 128, beatsPerBar: 4, bars: 2),
        voices: [hyperbolicVoice(31, 0), tanScreechVoice(31, 1)])

    static let finalBoss = preset(
        32, "Final Boss",
        "Alles zusammen: Drums, Kick Roll, Tritonus-Bass, Hoover, Tan Screech und ein Endless Riser – acht Takte. Headroom und weicher Begrenzer halten die Summe sauber; mit Mute und Solo lassen sich die Schichten einzeln anhören.",
        category: .combinations, tempo: TempoSettings(bpm: 140, beatsPerBar: 4, bars: 8),
        voices: {
            var kick = kickRollVoice(32, 3)
            kick.volumeDecibels = -6
            var screech = tanScreechVoice(32, 6)
            screech.volumeDecibels = -16
            var riser = riserVoice(32, 7)
            riser.volumeDecibels = -12
            var bass = tritoneVoice(32, 4)
            bass.volumeDecibels = -7
            var lead = hooverVoice(32, 5)
            lead.volumeDecibels = -11
            return drumVoices(32) + [kick, bass, lead, screech, riser]
        }())
}
