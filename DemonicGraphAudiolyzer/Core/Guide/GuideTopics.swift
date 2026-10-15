import Foundation

/// Authored guide entries (structures, time, sound roles, generators). Every example is
/// evaluated by the tests with the real parser.
enum GuideTopics {
    private static func classic(_ input: String, _ result: String, value: Double?, x: Double = 0, note: String? = nil,
                                title: String) -> GuideExample {
        GuideExample(input: input, result: result, note: note, expectedValue: value, context: value == nil ? .none : .classic(x: x),
                     payload: .classic(title, input))
    }

    private static func synth(_ input: String, _ result: String, value: Double?, inputs: [String: Double] = [:],
                              note: String? = nil, payload: EditorPayload?) -> GuideExample {
        GuideExample(input: input, result: result, note: note, expectedValue: value,
                     context: value == nil ? .none : .synth(inputs: inputs), payload: payload)
    }

    static func variableExample(_ variable: FormulaVariable) -> GuideExample {
        switch variable {
        case .x:
            return classic("x^2", "9 bei x = 3", value: 9, x: 3, title: "x²")
        case .a, .b, .c:
            return GuideExample(input: "a*sin(b*x) + c", result: "1·sin(1·0) + 0 = 0 bei x = 0 (Standardwerte)", note: nil,
                                expectedValue: 0, context: .classic(x: 0),
                                payload: .classic("Parameter a, b, c", "a*sin(b*x) + c", parameters: FormulaParameters(a: 1.5, b: 2, c: 0)))
        case .t:
            return synth("220 + 20*sin(2*pi*t)", "240 bei t = 0,25 s", value: 240, inputs: ["t": 0.25],
                         note: "Als Tonhöhe in Hz: Vibrato mit 1 Hz.", payload: .synth("Vibrato über t", "220 + 20*sin(2*pi*t)", role: .pitch(.hertz)))
        case .beat:
            return synth("floor(beat)", "2 bei beat = 2,5", value: 2, inputs: ["beat": 2.5],
                         note: "Als Tonhöhe in Halbtönen: jeder Beat einen Halbton höher.", payload: .synth("Halbton pro Beat", "floor(beat)", role: .pitch(.semitones)))
        case .bar:
            return synth("[0, 5, 7, 3][mod(bar, 4)]", "7 im dritten Takt (bar = 2)", value: 7, inputs: ["bar": 2],
                         note: "Akkordfolge: ein Grundton pro Takt.", payload: .synth("Ton pro Takt", "[0, 5, 7, 3][mod(bar, 4)]", role: .pitch(.semitones)))
        case .beatInBar:
            return synth("if(beatInBar < 1, 12, 0)", "0 bei beatInBar = 1,5", value: 0, inputs: ["beatInBar": 1.5],
                         note: "Der erste Beat jedes Takts eine Oktave höher.", payload: .synth("Betonter erster Beat", "if(beatInBar < 1, 12, 0)", role: .pitch(.semitones)))
        case .localTime:
            return synth("exp(-6*localTime)", "1 direkt beim Trigger", value: 1, inputs: ["localTime": 0],
                         note: "Abklingende Hüllkurve, bei jedem Trigger neu.", payload: .synth("Abklingen", "exp(-6*localTime)", role: .amplitude(.linear)))
        case .localBeat:
            return synth("exp(-4*localBeat)", "e^(−1) ≈ 0,368 nach einem Viertelbeat", value: exp(-1), inputs: ["localBeat": 0.25],
                         payload: .synth("Abklingen in Beats", "exp(-4*localBeat)", role: .amplitude(.linear)))
        case .n:
            return synth("[0, 3, 7][mod(n, 3)]", "3 beim fünften Trigger (n = 4)", value: 3, inputs: ["n": 4],
                         note: "Notenliste zyklisch durchlaufen.", payload: .synth("Notenliste mit n", "[0, 3, 7][mod(n, 3)]", role: .pitch(.semitones)))
        case .note:
            return synth("note", "7, wenn der Sequencer Note 7 liefert", value: 7, inputs: ["note": 7],
                         payload: .preset(SynthPresets.fibonacciBass))
        case .velocity:
            return synth("velocity*exp(-5*localTime)", "0,5 bei einem leisen Schlag o", value: 0.5, inputs: ["velocity": 0.5, "localTime": 0],
                         payload: .synth("Anschlagstärke", "velocity*exp(-5*localTime)", role: .amplitude(.linear)))
        case .bpm:
            return synth("60/bpm", "0,5 s pro Beat bei 120 BPM", value: 0.5, inputs: ["bpm": 120], payload: nil)
        case .beatsPerBar:
            return synth("beatsPerBar - 1", "3 im 4/4-Takt (Index des letzten Beats)", value: 3, inputs: ["beatsPerBar": 4], payload: nil)
        case .baseFrequency:
            return synth("2*baseFrequency", "440 Hz bei 220 Hz Grundfrequenz", value: 440, inputs: ["baseFrequency": 220],
                         payload: .synth("Oktave über der Grundfrequenz", "2*baseFrequency", role: .pitch(.hertz)))
        case .nyquist:
            return synth("floor((nyquist/baseFrequency + 1)/2)", "100 ungerade Partialtöne bei 110 Hz und 44,1 kHz", value: 100,
                         inputs: ["nyquist": 22_050, "baseFrequency": 110], payload: .preset(SynthPresets.fourierSquare))
        }
    }

    static let entries: [GuideEntry] = structures + time + sound + generators

    // MARK: Structures

    static let structures: [GuideEntry] = [
        GuideEntry(id: "topic-loop-variables", category: .sums, title: "Lokale Laufvariablen", symbol: "Σᵢ",
                   commands: ["sum", "prod"],
                   explanation: "Die Laufvariable einer Summe oder eines Produkts gilt nur im Ausdruck (4. Argument). Start und Ende werden außerhalb berechnet; ein gleichnamiger äußerer Name wird im Ausdruck verdeckt und ist danach wieder sichtbar.",
                   syntax: "sum(i, 1, 3, sum(j, 1, i, 1))",
                   examples: [classic("sum(i, 1, 3, sum(j, 1, i, 1))", "1 + 2 + 3 = 6", value: 6, title: "Verschachtelte Summe"),
                              classic("sum(i, 1, 3, sum(i, 1, 2, i))", "9 – das innere i verdeckt das äußere", value: 9, title: "Verdeckte Laufvariable"),
                              classic("i = 4\nsum(i, 1, i, i)", "10 – das Ende verwendet die äußere Definition i = 4", value: 10, title: "Scoping von Start und Ende")],
                   notes: ["Nach der Summe ist die Laufvariable unbekannt: sum(k, 1, 3, k) + k ist ein Fehler.",
                           "Hilfsfunktionen sehen nur ihre eigenen Parameter, nicht die Laufvariable des Aufrufers."],
                   keywords: ["laufvariable", "scope", "gültigkeit", "verschachtelt"]),
        GuideEntry(id: "topic-cyclic-access", category: .lists, title: "Zyklischer Listenzugriff", symbol: "L[n mod len]",
                   commands: ["mod", "len"],
                   explanation: "Listen haben nullbasierte Indizes; außerhalb von 0 … len − 1 ist der Zugriff undefiniert. Für Wiederholung wird der Index ausdrücklich mit mod gefaltet – auch negative Indizes landen so im gültigen Bereich.",
                   syntax: "notes[mod(n, len(notes))]",
                   examples: [classic("notes = [0, 3, 7, 10]\nnotes[mod(5, len(notes))]", "3 (Index 1)", value: 3, title: "Zyklischer Zugriff"),
                              classic("notes = [0, 3, 7, 10]\nnotes[mod(-1, len(notes))]", "10 (letztes Element)", value: 10, title: "Negativer Index mit mod")],
                   keywords: ["zyklisch", "wiederholen", "index", "modulo", "liste"]),
        GuideEntry(id: "topic-helper-functions", category: .lists, title: "Hilfsfunktionen", symbol: "r(x) = …",
                   commands: ["="],
                   explanation: "Eigene Funktionen werden in einer eigenen Zeile definiert: name(parameter) = ausdruck. Sie dürfen mehrere Parameter haben und andere Definitionen verwenden, sich aber nicht selbst aufrufen.",
                   syntax: "r(x) = frac(2*x)",
                   examples: [classic("r(x) = frac(2*x)\nr(0.75)", "frac(1,5) = 0,5", value: 0.5, title: "Hilfsfunktion r"),
                              classic("r(k,x) = (-1)^floor(2^k*x)\nr(1, 0.3) + r(2, 0.3)", "1 + (−1) = 0", value: 0, title: "Zwei Parameter")],
                   notes: ["Rekursion und zyklische Definitionen werden als Fehler gemeldet.",
                           "Hilfsfunktionen werden beim Übersetzen eingesetzt; sehr große Verschachtelungen sind auf 20 000 Knoten begrenzt."],
                   keywords: ["funktion", "eigene funktion", "hilfsfunktion", "definition"]),
        GuideEntry(id: "topic-intermediate-values", category: .lists, title: "Zwischenwerte und mehrzeilige Formeln", symbol: "p = …",
                   commands: ["#"],
                   explanation: "Im erweiterten Editor steht jede Definition in einer Zeile. Ein Zwischenwert wird einmal pro Auswertung berechnet und darf beliebig oft verwendet werden. Die Ausgabe ist die Zeile ohne =. Kommentare beginnen mit #.",
                   syntax: "p = x + 8\n1 + (5/12)*(floor((1+p/8)*sin(pi*p^2/4))+1)",
                   examples: [classic("p = 2 + 3\np^2", "25", value: 25, title: "Zwischenwert"),
                              classic("# Beispiel\nk = 2\nf(u) = k*u\nf(3)", "6", value: 6, title: "Mehrzeilig mit Kommentar")],
                   graphExample: GuideExample(input: "p = x + 8\n1 + (5/12)*(floor((1+p/8)*sin(pi*p^2/4))+1)", result: "quantisierter Chirp",
                                              note: nil, expectedValue: nil, context: .none,
                                              payload: .classic("Chirp mit Zwischenwert", "p = x + 8\n1 + (5/12)*(floor((1+p/8)*sin(pi*p^2/4))+1)")),
                   notes: ["Die Reihenfolge der Zeilen ist frei.", "Höchstens 80 Zeilen und 4 000 Zeichen, jede Zeile höchstens 500 Zeichen."],
                   keywords: ["zwischenwert", "mehrzeilig", "kommentar", "erweiterter editor", "variable"]),
        GuideEntry(id: "topic-parameters", category: .lists, title: "Parameter: konstant oder pro Beat/Takt", symbol: "k = …",
                   commands: ["parameter"],
                   explanation: "Parameter einer Stimme oder des Projekts haben einen Schieberegler (konstant) oder eine Liste, die pro Beat bzw. pro Takt weiterschaltet. Intern entsteht daraus eine Definition: k = [7, 14, 28][mod(bar, 3)].",
                   syntax: "[1, 0.5, 0.25][mod(bar, 3)]",
                   examples: [synth("[1, 0.5, 0.25][mod(bar, 3)]", "0,5 im zweiten Takt (bar = 1)", value: 0.5, inputs: ["bar": 1],
                                    payload: .synth("Parameter pro Takt", "-1.6 + 5exp(-k*mod(x, period))", role: .pitch(.octaves),
                                                    parameters: [SynthParameter(name: "period", mode: .perBar, values: [1, 0.5, 0.25], minimum: 0.1, maximum: 2),
                                                                 SynthParameter(name: "k", mode: .perBar, values: [7, 14, 28], minimum: 1, maximum: 40)]))],
                   notes: ["Im einfachen Editor werden unbekannte Namen automatisch als Parameter mit dem Wert 1 erkannt; im erweiterten Editor sind sie ein Fehler."],
                   keywords: ["parameter", "regler", "liste pro takt", "liste pro beat", "automatisch"])
    ]

    // MARK: Time

    static let time: [GuideEntry] = [
        GuideEntry(id: "topic-seconds-beats", category: .time, title: "Sekunden und Beats", symbol: "t ↔ beat",
                   commands: ["t", "beat", "bpm"],
                   explanation: "Bei konstantem Tempo gilt beat = t · BPM / 60, bar = floor(beat / beatsPerBar) und beatInBar = mod(beat, beatsPerBar). Formeln in Beats bleiben bei Tempoänderungen musikalisch gleich, Formeln in Sekunden behalten ihre absolute Dauer.",
                   syntax: "beat = t*bpm/60",
                   examples: [synth("t*bpm/60", "3 Beats nach 1,5 s bei 120 BPM", value: 3, inputs: ["t": 1.5, "bpm": 120], payload: nil),
                              synth("floor(beat/beatsPerBar)", "2 bei beat = 9 im 4/4-Takt", value: 2, inputs: ["beat": 9, "beatsPerBar": 4], payload: nil)],
                   notes: ["Der Durchlauf hat genau Takte · Beats pro Takt Beats und ist höchstens 120 s lang.",
                           "Trigger werden samplegenau auf das erste Sample ab dem exakten Zeitpunkt gelegt – auch im Loop."],
                   keywords: ["tempo", "bpm", "beat", "takt", "sekunden", "zeit"]),
        GuideEntry(id: "topic-x-mapping", category: .time, title: "Bedeutung von x im Synthesizer", symbol: "x",
                   commands: ["x"],
                   explanation: "Pro Projekt wird ausdrücklich gewählt, was x bedeutet: Sekunden (x = t), Beats (x = beat) oder der bisherige freie x-Durchlauf von xMin bis xMax über die Dauer. Gespeicherte Projekte der Modi „Graph vertonen“ und „Formel als Klangwelle“ behalten ihre bisherige Bedeutung.",
                   syntax: "x", examples: [synth("mod(x, 1)", "0,5 bei x = beat = 2,5", value: 0.5, inputs: ["x": 2.5], payload: nil)],
                   notes: ["In einer Wellenformel (Audiosignal, periodisch) läuft x dagegen je Periode durch den Abschnitt."],
                   keywords: ["x", "zuordnung", "sekunden", "beats", "freier durchlauf"]),
        GuideEntry(id: "topic-triggers", category: .time, title: "Trigger und Ereignisse", symbol: "⟂",
                   commands: ["localTime", "n"],
                   explanation: "Jede Stimme hat eine Triggerquelle: Dauerton (ein Ereignis am Anfang), Rhythmusmuster, Beschleunigung, Pendel oder Sequencer. Bei jedem Ereignis beginnen localTime und localBeat wieder bei 0 und n zählt weiter. Alle Ereignisse werden vor der Wiedergabe samplegenau geplant – Vorschau, Export und Graph verwenden dieselbe Liste.",
                   syntax: "exp(-6*localTime)",
                   examples: [synth("exp(-6*localTime)", "1 beim Trigger, danach abklingend", value: 1, inputs: ["localTime": 0],
                                    payload: .synth("Hüllkurve pro Trigger", "exp(-6*localTime)", role: .amplitude(.linear)))],
                   notes: ["Polyphone Stimmen (z. B. Pascal) spielen mehrere Noten gleichzeitig; ihre Notenlänge ist einstellbar."],
                   keywords: ["trigger", "ereignis", "auslöser", "retrigger", "polyphonie"]),
        GuideEntry(id: "topic-rhythm", category: .time, title: "Rhythmusmuster", symbol: "x . x .",
                   commands: ["x", "o", "."], explanation: "Ein Muster aus x (Schlag), o (leiser Schlag, Anschlagstärke 0,5) und . oder - (Pause); Leerzeichen und | dienen nur der Übersicht. Jedes Zeichen dauert die eingestellte Schrittlänge in Beats; das Muster wiederholt sich.",
                   syntax: "x...x...x.x.x...",
                   examples: [synth("velocity", "0,5 bei o, sonst 1", value: 1, inputs: ["velocity": 1], payload: .preset(SynthPresets.drumPattern))],
                   notes: ["Rhythmusmuster sind Einstellungen der Triggerquelle, keine Formeln."],
                   keywords: ["muster", "rhythmus", "pattern", "schlagzeug", "step"], isGeneratorSetting: true)
    ]

    // MARK: Sound roles

    static let sound: [GuideEntry] = [
        GuideEntry(id: "topic-roles", category: .sound, title: "Graphvertonung oder Formel-Synthese?", symbol: "y → f",
                   commands: [], explanation: "„Graph vertonen“ liest eine Kurve y = f(x) ab und bildet sie auf einen Frequenzbereich ab. „Formel als Klangwelle“ spielt einen Abschnitt der Kurve als Wellenform. Im Formel-Synthesizer hat jede Formel eine ausdrückliche Rolle: Tonhöhe (Hz, Halbtöne, Oktaven oder die bisherige Abbildung), Amplitude (linear oder dB) oder Audiosignal. Anzeigekurven sind reine Visualisierung.",
                   syntax: "Rolle wählen: Tonhöhe · Amplitude · Audiosignal",
                   examples: [synth("-1.6 + 5exp(-7*mod(x, 1))", "Tonhöhe in Oktaven – derselbe Ausdruck wäre in Hz ein unhörbarer Bereich", value: 3.4, inputs: ["x": 0],
                                    payload: .synth("Kick als Tonhöhe", "-1.6 + 5exp(-7*mod(x, 1))", role: .pitch(.octaves)))],
                   notes: ["Werte aus Referenzen wie „m/12“ werden nie ungeprüft als Hz gelesen – die Einheit steht sichtbar am Editor.",
                           "Mehrere Stimmen werden als Audiosignale addiert, nicht ihre Frequenzen."],
                   keywords: ["rolle", "tonhöhe", "amplitude", "signal", "unterschied", "synthesizer", "graph vertonen"]),
        GuideEntry(id: "topic-pitch-units", category: .sound, title: "Hz, Halbtöne und Oktaven", symbol: "f = f₀·2^(s/12)",
                   commands: ["Hz", "Halbtöne", "Oktaven"],
                   explanation: "Eine Tonhöhenformel liefert entweder direkt die Frequenz in Hz, einen Halbtonabstand s zur Grundfrequenz (f = Grundfrequenz · 2^(s/12)) oder einen Oktavabstand o (f = Grundfrequenz · 2^o). 12 Halbtöne sind eine Oktave, also die doppelte Frequenz.",
                   syntax: "baseFrequency*2^(s/12)",
                   examples: [synth("baseFrequency*2^(12/12)", "440 Hz: 12 Halbtöne über 220 Hz", value: 440, inputs: ["baseFrequency": 220],
                                    payload: .synth("Halbtöne", "12", role: .pitch(.semitones))),
                              synth("baseFrequency*2^(-1)", "110 Hz: eine Oktave unter 220 Hz", value: 110, inputs: ["baseFrequency": 220],
                                    payload: .synth("Oktaven", "-1", role: .pitch(.octaves)))],
                   notes: ["Frequenzen werden auf 8 Hz … 0,45 · Abtastrate begrenzt; undefinierte oder nicht positive Hz-Werte schalten die Stimme stumm.",
                           "Die Glättung (Glide) gleitet exponentiell, also gleichmäßig auf der Halbtonskala."],
                   keywords: ["hz", "hertz", "halbton", "oktave", "grundfrequenz", "einheit"]),
        GuideEntry(id: "topic-frequency-formulas", category: .sound, title: "Frequenzformeln und Phase", symbol: "φ = ∫f dt",
                   commands: [], explanation: "Ist die Frequenz veränderlich, integriert der Oszillator sie Sample für Sample zur Phase – so bleibt der Klang ohne Sprünge. sin(2π·f(t)·t) ist kein allgemeiner Ersatz: Die Momentanfrequenz davon ist f(t) + t·f′(t), nicht f(t).",
                   syntax: "f0*(f1/f0)^(t/D)",
                   examples: [synth("80*(1600/80)^(2/4)", "≈ 357,8 Hz nach der Hälfte eines 4-s-Chirps", value: 80 * pow(20, 0.5), payload: .preset(SynthPresets.chirp))],
                   keywords: ["phase", "chirp", "integration", "frequenz", "kontinuierlich"]),
        GuideEntry(id: "topic-amplitude", category: .sound, title: "Amplitudenhüllkurven", symbol: "A(t)",
                   commands: ["linear", "dB"],
                   explanation: "Die Amplitudenformel steuert die Lautstärke einer Stimme. Standard ist eine nichtnegative lineare Verstärkung: 0 = stumm, 1 = voller Pegel der Stimme, negative Werte zählen als 0, Werte über 4 werden begrenzt. Im dB-Modus gilt Verstärkung = 10^(A/20): 0 dB = 1, −6 dB ≈ 0,5, ≤ −120 dB = stumm.",
                   syntax: "exp(-6*localTime)",
                   examples: [synth("exp((localTime - 0.45)/0.09)", "1 am Ereignisende (Reverse Bass)", value: 1, inputs: ["localTime": 0.45],
                                    payload: .preset(SynthPresets.reverseBass)),
                              synth("-6", "−6 dB ≈ 0,5-fache Amplitude", value: -6, payload: .synth("Pegel in dB", "-6", role: .amplitude(.decibels)))],
                   notes: ["Sprünge der Hüllkurve werden in etwa 1 ms geglättet, damit keine Klicks entstehen."],
                   keywords: ["amplitude", "hüllkurve", "lautstärke", "envelope", "dezibel", "db"]),
        GuideEntry(id: "topic-signal", category: .sound, title: "Direkte Audiosignale und Wellenformeln", symbol: "s(t)",
                   commands: [], explanation: "Als Audiosignal liefert eine Formel die Samples selbst (direkt, Funktion von t) oder eine periodische Wellenform (x läuft je Periode durch den Abschnitt, die Tonhöhe bestimmt die Wiederholrate). Der Gleichanteil wird entfernt, der Pegel automatisch normalisiert und die Bandbreite begrenzt: Zeitunabhängige Wellenformeln werden als bandbegrenzte Tabellen gespielt, alle anderen mit Oversampling (2-, 4- oder 8-fach) und Tiefpass berechnet.",
                   syntax: "sin(2*pi*220*t)",
                   examples: [synth("sin(2*pi*220*t)", "0 bei t = 0", value: 0, inputs: ["t": 0],
                                    payload: .synth("Direkter Sinus", "sin(2*pi*220*t)", role: .signal))],
                   notes: ["Unstetige Signale wie sign(sin(…)) oder tan erzeugen Obertöne bis ins Unendliche – ohne Oversampling entstünde Aliasing.",
                           "Die automatische Normalisierung schätzt die Spitze vor dem Abspielen aus bis zu 65 536 Stellen."],
                   keywords: ["audiosignal", "samples", "wellenform", "aliasing", "oversampling", "normalisierung", "gleichanteil"]),
        GuideEntry(id: "topic-quantization", category: .sound, title: "Rundung und Skalenquantisierung", symbol: "⌊x⌉ ≠ Skala",
                   commands: ["round", "floor"],
                   explanation: "Numerische Rundung (round, floor) macht aus einer Kurve ganze Zahlen – als Halbtöne also chromatische Schritte. Skalenquantisierung ist eine Einstellung der Tonhöhe: Sie zieht jeden Wert auf den nächsten Ton einer Tonleiter (Chromatisch, Dur, Natürlich Moll, Pentatonik) bezogen auf die Grundfrequenz.",
                   syntax: "round(5*sin(x))",
                   examples: [classic("round(5*sin(pi/4))", "4 (numerisch gerundet)", value: 4, title: "Gerundet")],
                   notes: ["Pentatonik: 0, 2, 4, 7, 9 Halbtöne; Dur: 0, 2, 4, 5, 7, 9, 11; natürlich Moll: 0, 2, 3, 5, 7, 8, 10."],
                   keywords: ["quantisieren", "skala", "tonleiter", "dur", "moll", "pentatonik", "chromatisch", "rundung"]),
        GuideEntry(id: "topic-mixing", category: .sound, title: "Mehrere Stimmen und Mischung", symbol: "Σ Stimmen",
                   commands: ["mute", "solo"],
                   explanation: "Jede Stimme wird als eigenes Signal erzeugt, mit Lautstärke und Panorama (konstante Leistung, Mitte ausgeglichen) gewichtet und addiert. Die Summe wird mit dem Projektpegel und dem Headroom-Faktor 1/√N (N hörbare Stimmen) skaliert; ein weicher Begrenzer ab −1 dBFS verhindert, dass der Ausgang je 0 dBFS überschreitet. Mute schaltet eine Stimme ab, Solo hört nur die Solo-Stimmen.",
                   syntax: "Lautstärke · Panorama · Mute · Solo",
                   examples: [classic("1/sqrt(4)", "0,5: Headroom-Faktor bei vier Stimmen", value: 0.5, title: "Headroom")],
                   notes: ["Bis zu 8 Stimmen pro Projekt.", "Vorschau und Export verwenden denselben Renderkern und denselben Pegel."],
                   keywords: ["stimme", "mix", "mischen", "headroom", "clipping", "panorama", "solo", "mute", "begrenzer"]),
        GuideEntry(id: "topic-display", category: .sound, title: "Anzeigekurven", symbol: "👁",
                   commands: [], explanation: "Anzeigekurven werden nur gezeichnet, nicht gehört – etwa die Schwebungshüllkurve 2·|cos(π·δ·t)| einer Reese-Bassline oder einzelne Partialtöne. Kurven mit der Einheit „Signal“ erscheinen im Audio-Ausschnitt mit Millisekunden-Achse.",
                   syntax: "2*abs(cos(pi*delta*t))",
                   examples: [synth("2*abs(cos(pi*2*t))", "2 bei t = 0", value: 2, inputs: ["t": 0], payload: .preset(SynthPresets.reese))],
                   keywords: ["anzeige", "visualisierung", "schwebung", "partialton"]),
        GuideEntry(id: "topic-limits", category: .sound, title: "Ressourcenlimits", symbol: "≤",
                   commands: [], explanation: "Damit die App flüssig bleibt, gelten feste Grenzen: Formeln höchstens 4 000 Zeichen, 80 Zeilen, Zeilen 500 Zeichen, Verschachtelung 64 Ebenen, 20 000 Knoten nach dem Einsetzen; Summen und Produkte höchstens 10 000 Durchläufe, zusammen 200 000 je Auswertung; Listen höchstens 1 024 Elemente; 8 Stimmen, 20 000 Ereignisse pro Stimme, Durchläufe höchstens 120 s; Pascal 32 Zeilen und 8 gleichzeitige Noten; Wiederholraten höchstens 64 Ereignisse pro Sekunde.",
                   syntax: "–", examples: [], keywords: ["grenzen", "limit", "maximal", "ressourcen"])
    ]

    // MARK: Generators

    static let generators: [GuideEntry] = [
        GuideEntry(id: "topic-formula-or-generator", category: .generators, title: "Formel oder Generator?", symbol: "ƒ / ⚙",
                   commands: [], explanation: "Frei eingebbare Formeln stehen in den Editoren (Tonhöhe, Amplitude, Audiosignal, Definitionen). Spezialisierte Generatoren – Rhythmusmuster, Sequencer (Fibonacci, Pascal, Quintenzirkel, Tritonus), Pendel, Beschleunigung und Endless Riser – sind Einstellungen der Triggerquelle bzw. Klangquelle. Sie liefern Ereignisse mit Notenwert note, den die Tonhöhenformel weiterverwenden kann.",
                   syntax: "note", examples: [synth("note + 12", "eine Oktave über dem Sequencerton", value: 19, inputs: ["note": 7], payload: .preset(SynthPresets.fibonacciBass))],
                   keywords: ["generator", "sequencer", "einstellung", "formel"], isGeneratorSetting: true),
        GuideEntry(id: "topic-808", category: .generators, title: "808 Slide", symbol: "f₁ → f₂",
                   commands: ["smooth"], explanation: "u = clip((localTime − t0)/T, 0, 1) läuft während des Slides von 0 nach 1; smooth = 3u² − 2u³ macht Anfang und Ende weich. Die Frequenz f1·(f2/f1)^smooth gleitet so exponentiell von f1 nach f2 (positive Frequenzen in Hz, T > 0). Vor t0 klingt f1, nach t0 + T genau f2; die Phase bleibt durchgehend.",
                   syntax: "u = clip((localTime-t0)/T, 0, 1)\nsmooth = 3u^2 - 2u^3\nf1*(f2/f1)^smooth",
                   examples: [classic("u = 0.5\n3u^2 - 2u^3", "0,5 – die Mitte des Slides", value: 0.5, title: "Smoothstep"),
                              synth("55*(82.41/55)^1", "82,41 Hz am Ende", value: 82.41, payload: .preset(SynthPresets.slide808))],
                   keywords: ["808", "slide", "glide", "bass", "smoothstep"]),
        GuideEntry(id: "topic-reverse-bass", category: .generators, title: "Reverse Bass", symbol: "e^((t−T)/τ)",
                   commands: ["tau"], explanation: "Die Hüllkurve A = exp((localTime − T)/τ) gilt für 0 ≤ localTime ≤ T und wächst bis zum Ereignisende genau auf 1; danach ist die Stimme stumm. Standard τ = 0,09 s. Das ist eine anschwellende Hüllkurve – es wird kein Sample rückwärts abgespielt.",
                   syntax: "if(localTime <= T, exp((localTime - T)/tau), 0)",
                   examples: [synth("if(localTime <= 0.45, exp((localTime - 0.45)/0.09), 0)", "1 bei localTime = T = 0,45", value: 1, inputs: ["localTime": 0.45],
                                    payload: .preset(SynthPresets.reverseBass))],
                   keywords: ["reverse", "rückwärts", "anschwellen", "hüllkurve", "tau"]),
        GuideEntry(id: "topic-pendulum", category: .generators, title: "Pendel", symbol: "cos(2πN·beat/16)",
                   commands: ["N"], explanation: "Sechs Pendel schwingen mit position = cos(2π · N · beat / 16), N = 6 … 11. Beim Mitteldurchgang (position = 0, also bei beat = (4 + 8m)/N) erklingt die Note des Pendels und es leuchtet kurz auf. Nach 16 Beats sind alle wieder in der Ausgangsphase. Wahlweise lösen beide Mitteldurchgänge oder nur eine Bewegungsrichtung aus.",
                   syntax: "cos(2*pi*N*beat/16)",
                   examples: [synth("cos(2*pi*6*(4/6)/16)", "0 – erster Mitteldurchgang von N = 6", value: 0, payload: .preset(SynthPresets.pendulums))],
                   notes: ["Die Auslösezeitpunkte werden analytisch berechnet: Bildaussetzer können keinen Trigger verschlucken oder doppelt auslösen."],
                   keywords: ["pendel", "pendulum", "mitteldurchgang", "phase"], isGeneratorSetting: true),
        GuideEntry(id: "topic-fibonacci", category: .generators, title: "Fibonacci modulo m", symbol: "Fₙ mod m",
                   commands: ["fibonacci"], explanation: "Die Fibonacci-Folge wird direkt modulo m berechnet: F(n) = (F(n−1) + F(n−2)) mod m. Große Fibonacci-Zahlen entstehen dabei nie. Jeder Rest wählt einen Ton aus der Notenliste; Rhythmus und Notenliste dürfen verschieden lang sein.",
                   syntax: "Sequencer: Fibonacci, m = 4",
                   examples: [classic("mod(13, 4)", "1: F(7) = 13 hat den Rest 1", value: 1, title: "Fibonacci-Rest")],
                   notes: ["Für m = 4 lautet die Restfolge 0, 1, 1, 2, 3, 1 und wiederholt sich dann (Pisano-Periode 6)."],
                   keywords: ["fibonacci", "pisano", "rest", "sequencer"], isGeneratorSetting: true),
        GuideEntry(id: "topic-pascal", category: .generators, title: "Pascal modulo 2", symbol: "C(n, k) mod 2",
                   commands: ["pascal"], explanation: "Zeile für Zeile des Pascalschen Dreiecks erklingen die Positionen k, deren Binomialkoeffizient C(n, k) ungerade ist. Die Parität wird ohne Fakultäten bestimmt: C(n, k) ist genau dann ungerade, wenn alle Bits von k auch in n gesetzt sind (k & n = k). Es entsteht das Sierpinski-Dreieck; Zeilen (≤ 32) und gleichzeitige Noten (≤ 8) sind begrenzt.",
                   syntax: "Sequencer: Pascal, 16 Zeilen",
                   examples: [classic("mod(prod(i, 1, 2, (4 - i + 1)/i), 2)", "0: C(4, 2) = 6 ist gerade", value: 0, title: "C(4,2) mod 2")],
                   keywords: ["pascal", "binomial", "sierpinski", "parität", "dreieck"], isGeneratorSetting: true),
        GuideEntry(id: "topic-fifths", category: .generators, title: "Quintenzirkel und diatonische Quintfolge", symbol: "7n mod 12",
                   commands: ["mod"], explanation: "Der chromatische Quintenzirkel liefert mit pitchClass = mod(7·n, 12) nacheinander alle zwölf Tonklassen. Die diatonische Quintfolge springt mit degree = mod(4·n, 7) durch die sieben Stufen einer Durtonleiter. Beide Verfahren sind verschieden und heißen in der App ausdrücklich so.",
                   syntax: "mod(7*n, 12)",
                   examples: [classic("mod(7*3, 12)", "9 (A über C)", value: 9, title: "Quintenzirkel"),
                              classic("mod(4*3, 7)", "5 (sechste Stufe)", value: 5, title: "Diatonische Quintfolge")],
                   keywords: ["quinte", "quintenzirkel", "diatonisch", "tonklasse", "stufe"], isGeneratorSetting: true),
        GuideEntry(id: "topic-tritone", category: .generators, title: "Tritonus", symbol: "f₀·√2",
                   commands: ["sqrt"], explanation: "Der Tritonus teilt die Oktave in der Mitte: f0 · √2 = f0 · 2^(6/12). Der Sequencer wechselt zwischen beiden Tönen; mit Glättung entsteht ein exponentieller Slide.",
                   syntax: "f0*sqrt(2)",
                   examples: [classic("2^(6/12)", "√2 ≈ 1,4142", value: 2.0.squareRoot(), title: "Tritonus-Verhältnis")],
                   keywords: ["tritonus", "teufelston", "wurzel 2"], isGeneratorSetting: true),
        GuideEntry(id: "topic-riser", category: .generators, title: "Endless Riser (Shepard/Risset)", symbol: "↗↗↗",
                   commands: ["riser"], explanation: "Mehrere Teiltöne im Oktavabstand steigen gemeinsam; jeder wird unten weich eingeblendet und oben weich ausgeblendet (Pegelfenster 0,5 − 0,5·cos(2π·Lage)) und beginnt dann wieder unten. Das Ohr folgt den steigenden Teiltönen, während die Summe gleich bleibt – ein psychoakustischer Eindruck endlosen Steigens, keine unbegrenzt steigende Frequenz.",
                   syntax: "Klangquelle: Endless Riser",
                   examples: [classic("0.5 - 0.5*cos(2*pi*0.5)", "1 – volle Lautstärke in der Mitte des Oktavbereichs", value: 1, title: "Pegelfenster")],
                   keywords: ["shepard", "risset", "riser", "endlos", "illusion"], isGeneratorSetting: true),
        GuideEntry(id: "topic-accelerating", category: .generators, title: "Beschleunigte Wiederholung", symbol: "φ = ∫rate",
                   commands: ["rate"], explanation: "Bei veränderlicher Rate wird die Phase integriert: φ(beat) = ∫ rate d(beat). Bei jedem ganzzahligen Phasendurchgang entsteht ein Ereignis. Die naheliegende Formel t/period(t) wäre falsch, weil sich die Periode während der Wiederholungen ändert. Die Ereignisdichte ist begrenzt; die Grenze wird sichtbar angezeigt.",
                   syntax: "2^(beat/beatsPerBar)",
                   examples: [synth("2^(beat/beatsPerBar)", "4 Ereignisse pro Beat im dritten Takt", value: 4, inputs: ["beat": 8, "beatsPerBar": 4],
                                    payload: .preset(SynthPresets.accelerating))],
                   keywords: ["beschleunigung", "rate", "integral", "phase", "roll"], isGeneratorSetting: true),
        GuideEntry(id: "topic-drums", category: .generators, title: "Schlaginstrumente", symbol: "🥁",
                   commands: ["kick", "snare", "hihat", "cowbell"],
                   explanation: "Kick: Sinus, dessen Tonhöhe in ~30 ms vom Vierfachen auf die Grundfrequenz fällt. Snare: zwei kurze Sinustöne plus bandgefiltertes Rauschen. Hi-Hat: hochpassgefiltertes Rauschen. Cowbell: zwei bandbegrenzte Rechteckschwingungen im Verhältnis 1 : 1,48 durch einen Bandpass. Das Rauschen stammt aus einem gespeicherten Seed – Vorschau und Export klingen identisch.",
                   syntax: "Klangquelle: Schlaginstrument",
                   examples: [classic("540*1.4815", "≈ 800 Hz: zweiter Ton der Cowbell", value: 540 * 1.4815, title: "Cowbell-Töne")],
                   keywords: ["drum", "schlagzeug", "kick", "snare", "hi-hat", "cowbell", "rauschen", "seed"], isGeneratorSetting: true)
    ]
}
