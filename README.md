# Demonic Graph Audiolyzer

Native iOS-App (SwiftUI, Swift, SwiftData), die mathematische Funktionen in **sichtbare und hörbare Graphen** verwandelt:
Formel eingeben → Graph im x-y-Koordinatensystem sehen → „Graph abspielen“ → ein leuchtender Punkt wandert von links nach rechts,
die Kurve entsteht schrittweise und gleichzeitig erklingt der aus der Funktion erzeugte Klang → Export als **MP3, WAV oder M4A**.

Dazu kommen ein **mehrstimmiger Formel-Synthesizer** mit musikalischer Zeit (BPM, Takte, Beats), ausdrücklichen Formelrollen
(Tonhöhe, Amplitude, Audiosignal), mathematischen Sequencern, einem **Pendel-Modus**, einem Endless Riser, beschleunigter Wiederholung,
20 Formel-Presets plus Kombinationen – und ein vollständiger Bereich **„Anleitungen“** zu allen Zeichen, Funktionen, Variablen und Rollen.

Die Kernfunktion arbeitet vollständig **offline** – ohne Anmeldung, Server oder Mikrofonzugriff.

---

## Inhalt

1. [Öffnen und Starten in Xcode](#öffnen-und-starten-in-xcode)
2. [Signing und verbindliche Bundle-ID](#signing-und-verbindliche-bundle-id)
3. [Deployment Target und Projekteinstellungen](#deployment-target-und-projekteinstellungen)
4. [App-Icon-Integration](#app-icon-integration)
5. [Abhängigkeiten und Codec-Integration (LAME)](#abhängigkeiten-und-codec-integration-lame)
6. [Formelsyntax](#formelsyntax)
7. [Klangmodi](#klangmodi)
8. [Formel-Synthesizer](#formel-synthesizer)
9. [Pendel, Riser, Beschleunigung und Sequencer](#pendel-riser-beschleunigung-und-sequencer)
10. [Presets](#presets)
11. [Anleitungen](#anleitungen)
12. [Ressourcengrenzen und Sicherheit](#ressourcengrenzen-und-sicherheit)
13. [Audiowiedergabe](#audiowiedergabe)
14. [Audioexport](#audioexport)
15. [Speicherung und Datenmigration](#speicherung-und-datenmigration)
16. [Design](#design)
17. [Architektur](#architektur)
18. [Tests und ausgeführte Prüfungen](#tests-und-ausgeführte-prüfungen)
19. [Verbleibende Einschränkungen](#verbleibende-einschränkungen)

---

## Öffnen und Starten in Xcode

1. Repository klonen und `DemonicGraphAudiolyzer.xcodeproj` in **Xcode 26** öffnen (das Projekt wurde mit Xcode 26.3 angelegt; es verwendet synchronisierte Ordner, `objectVersion 77`).
2. Xcode löst das lokale Swift Package `Packages/LameKit` automatisch auf (keine Netzwerkverbindung nötig – alle Quellen liegen im Repository).
3. Scheme **DemonicGraphAudiolyzer** wählen, ein iPhone oder einen iOS-Simulator als Ziel wählen, **⌘R**.

**Auf dem eigenen iPhone starten**

1. iPhone per Kabel (oder WLAN) verbinden, auf dem iPhone *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* aktivieren (einmalig, Neustart).
2. In Xcode unter *Signing & Capabilities* ist das Team **David Martens (Personal Team / Individual)** mit *Automatically manage signing* bereits eingetragen. Gegebenenfalls in *Xcode → Settings → Accounts* mit der Apple-ID anmelden.
3. iPhone als Ziel wählen und **⌘R**. Beim ersten Start ggf. auf dem iPhone unter *Einstellungen → Allgemein → VPN & Geräteverwaltung* dem Entwicklerzertifikat vertrauen.

Tests: **⌘U** (Unit-Tests mit Swift Testing und UI-Tests mit XCTest).

## Signing und verbindliche Bundle-ID

| Target | Bundle-ID | Konfigurationen |
|---|---|---|
| App `DemonicGraphAudiolyzer` | **`me.thedemonlord333.DemonicGraphAudiolyzer`** | Debug **und** Release |
| Unit-Tests | `me.thedemonlord333.DemonicGraphAudiolyzerTests` | Debug und Release |
| UI-Tests | `me.thedemonlord333.DemonicGraphAudiolyzerUITests` | Debug und Release |

* Signing-Einstellungen und Development-Team-ID (`LWL7HM459L`, *Automatic*) wurden unverändert übernommen.
* Anzeigename auf dem Homescreen: **Demonic Graph Audiolyzer** (`INFOPLIST_KEY_CFBundleDisplayName`).
* Der Test `ProjectConfigurationTests` prüft die Bundle-ID in allen App-Build-Konfigurationen direkt in `project.pbxproj` sowie zur Laufzeit.

## Deployment Target und Projekteinstellungen

* **Deployment Target: iOS 17.0** (Projekt und Test-Targets). Das neu angelegte Projekt stand auf iOS 26.2; gefordert war „iOS 17 oder neuer“. Mit 17.0 läuft die App auf allen iPhones ab iOS 17. Es werden nur APIs bis iOS 17 verwendet (iOS-18-APIs wie `AVAudioFile.close()` nur mit `#available`).
* iPhone (Hoch- und Querformat) und iPad; im Querformat nutzt der Graph die linke Bildschirmseite in voller Höhe.
* `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` im App-Target: Parser, Abtastung und Audioerzeugung laufen bewusst **außerhalb** des Main Actors; UI-Typen (`AudiolyzerModel`, `AudioPlaybackEngine`, `ExportModel`, Views) sind explizit `@MainActor`. Mit der Xcode-26-Vorgabe `MainActor` wären alle Rechenkerne an den Main Thread gebunden.
* Info.plist-Schlüssel (generiert): Anzeigename, Kategorie *Musik*, `ITSAppUsesNonExemptEncryption = NO`. Kein Mikrofon-Schlüssel – die App braucht keinen Mikrofonzugriff.
* Kein CloudKit, keine Hintergrund-Audio-Fähigkeit (die Wiedergabe pausiert beim Wechsel in den Hintergrund).

## App-Icon-Integration

* Vorlage: `Dämonischer Audiograph mit Neonhörnern.png` im Repository-Wurzelverzeichnis (1254 × 1254 px, RGB, **unverändert erhalten**).
* `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`: das komplette Motiv, verlustfrei auf **1024 × 1024 px** skaliert (Lanczos), quadratisch → quadratisch ohne Beschnitt, **deckend ohne Alphakanal** (PNG-Farbtyp 2/RGB), Ecken nicht selbst abgerundet (macht iOS).
* Das Single-Size-Format von Xcode benötigt nur die 1024-px-Variante; sie ist auch für das Erscheinungsbild „Dunkel“ eingetragen (das Motiv ist bereits dunkel). Für „Getönt“ erzeugt iOS die Variante automatisch.
* `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in Debug und Release.
* Zusätzlich `DemonIcon.imageset` (96/192/288 px) für die In-App-Verwendung (Einstellungen → Über, Teilen-Vorschau).
* Geprüft durch `ProjectConfigurationTests` (Abmessungen, Farbtyp, Asset-Name, `CFBundleIconName` zur Laufzeit).

## Abhängigkeiten und Codec-Integration (LAME)

Die App nutzt nur Apple-Frameworks (SwiftUI, SwiftData, AVFoundation/AVFAudio, Accessibility, UniformTypeIdentifiers) und **ein** lokales Swift Package:

**`Packages/LameKit`** – MP3-Encoder. iOS enthält keinen nativen MP3-*Encoder* (AVFoundation/AudioToolbox dekodieren MP3 nur). Deshalb ist
**LAME 3.100** als Quelltext eingebunden:

* Herkunft: offizielles Release `https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz`,
  SHA-256 `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`.
* Vendort: die Quellen aus `libmp3lame/` und `include/lame.h` **unverändert** (einzige projektspezifische Datei: `config.h`). Keine vorkompilierten Binärdateien – Xcode übersetzt LAME für iPhone (arm64) und Simulator selbst, daher reproduzierbar.
* `Packages/LameKit/Scripts/verify-lame-sources.sh` lädt das Original, prüft den SHA-256 und vergleicht jede Datei byte-genau.
* Schmale Swift-Schnittstelle `MP3Encoder` (C nur als Codec-Brücke, App-Logik bleibt Swift).
* **Lizenz: GNU LGPL v2** (`Packages/LameKit/COPYING-LAME.txt`). Für private Nutzung unproblematisch. **Vor einer App-Store-Veröffentlichung** muss die LGPL-Pflicht zur Ermöglichung des Neu-Linkens (statisches Linken) geprüft werden. Details: `Packages/LameKit/README.md`. MP3-Patente sind abgelaufen.

## Formelsyntax

| | |
|---|---|
| Schreibweisen | `sin(x)`, `y = sin(x)`, `f(x) = sin(x)` |
| Variablen (klassisch) | `x`; Parameter `a`, `b`, `c` mit Schiebereglern (−10 … 10) und manueller Eingabe |
| Variablen (Synthesizer) | `t` (s), `beat`, `bar` (ab 0), `beatInBar`, `localTime`, `localBeat` (seit dem letzten Auslösen der Stimme), `n` (Triggerzähler), `note`, `velocity`, `x` (pro Projekt: Sekunden, Beats oder freier Durchlauf), `bpm`, `beatsPerBar`, `baseFrequency`, `nyquist` |
| Konstanten | `pi` bzw. `π`, `e` |
| Operatoren | `+ - * / ^`, Klammern, unäres Minus; auch `×`, `÷`, `−`, `²`, `³`, `√` |
| Vergleiche und Logik | `< <= > >= == !=` (auch `≤ ≥ ≠`), `and`, `or`, `not(…)`; wahr = 1, falsch = 0. `&`, `\|` und `!` allein werden mit Korrekturhinweis abgelehnt (`\|x\|` → `abs(x)`) |
| Fallunterscheidungen | `if(Bedingung, dann, sonst)`, `piecewise(b1, w1, b2, w2, …, sonst)` – **lazy**: nur der gewählte Zweig wird berechnet |
| Summen und Produkte | `sum(i, Start, Ende, Ausdruck)` = Σ, `prod(i, Start, Ende, Ausdruck)` = Π; auch `Σ(…)`/`Π(…)`. Die Laufvariable gilt nur im Ausdruck (verschachtelt und verdeckend möglich); Ende < Start ergibt 0 bzw. 1 |
| Funktionen | `sin cos tan asin acos atan` (auch `arcsin arccos arctan`), `sqrt exp ln log10 abs sign floor ceil round frac min max mod clip` (auch `clamp`), `len` |
| Listen | `notes = [0, 3, 7, 10]`, Zugriff **ab 0**: `notes[0]`, zyklisch mit `notes[mod(n, len(notes))]`; Index außerhalb → Definitionslücke |
| Definitionen | mehrzeilig im erweiterten Editor: Zwischenwerte (`env = exp(-4*localTime)`), Hilfsfunktionen (`f(k) = 2^(k/12)`), Listen; Namen aus mehreren Buchstaben (`depth`, `rate2`), griechische Buchstaben (`α` = `alpha` …) |
| Winkel | Radiant |
| Rangfolge | `-x^2 = -(x^2)`, `2^3^2 = 2^(3^2)`, `2^-1 = 0.5`; Vergleiche binden schwächer als Arithmetik, `and` stärker als `or` |
| Implizite Multiplikation | `2x`, `2sin(x)`, `2(x+1)`, `(x+1)(x-1)`, `bx`, `2pi`. Buchstabenfolgen werden beim Parsen eindeutig zerlegt (längster bekannter Name zuerst, Definitionen haben Vorrang); verbleibende Mehrdeutigkeiten werden als Hinweis gemeldet statt still geraten. `1/2x` = (1/2)·x |
| `mod(a,b)` | `a − b·floor(a/b)`, nur für endliches `b > 0` definiert |
| `round` | rundet Hälften von null weg (2,5 → 3, −2,5 → −3) |
| Dezimalzahlen | mit Punkt (`0.5`); Komma bzw. Semikolon trennt Argumente. Keine Exponentialschreibweise (`1e5`), um Verwechslungen mit `e` zu vermeiden |

Ablauf: eigener Lexer → Parser (Syntaxbaum mit Quellpositionen) → Binder (Namen, Gültigkeitsbereiche, Zyklen, unbekannte Namen) → Compiler zu Closures mit Konstantenfaltung (`Core/Formula`). Es wird **kein Code ausgeführt** und nichts dynamisch geladen. Fehler erscheinen deutsch mit Zeile, Position und markierter Stelle; zyklische Definitionen (`a = b`, `b = a`) und unbekannte Namen sind Fehler. Division durch null, Polstellen, `NaN` und ±∞ sind Definitionslücken.

**Editor:** einfacher Modus (eine Zeile, unbekannte Einzelbuchstaben werden als Parameter mit Wert 1 erkannt und können als Regler übernommen werden) und erweiterter Modus (mehrzeilig, keine automatische Erkennung). Unter der Eingabe steht die Formel lesbar gesetzt (Brüche, Exponenten, Wurzeln, Σ/Π mit Grenzen, Fallunterscheidungen mit Klammer; der gerade aktive Fall leuchtet während der Wiedergabe). Die Signaturhilfe zeigt die Argumente der Funktion am Cursor und hebt das aktuelle hervor; das Buch-Symbol öffnet den passenden Eintrag der Anleitungen. Visuelle Editoren für Fallunterscheidungen und Σ/Π erzeugen die Texteingabe. Die Zusatztastatur enthält Variablen, Vergleiche, Listenzeichen und alle Funktionen.

## Klangmodi

### Standardmodus „Graph vertonen“

Für Dauer D und Zeit t: `x(t) = xMin + (xMax − xMin)·t/D`, `y(t) = f(x(t))`.
Der Klangbereich `[yLow, yHigh]` ist unabhängig vom sichtbaren Ausschnitt:
`u = clamp((y − yLow)/(yHigh − yLow), 0, 1)`, `Frequenz = fLow·(fHigh/fLow)^u` (Standard 110 Hz … 880 Hz). Höhere y-Werte → höhere Töne; negative y-Werte sind normale Töne.

* **Klangbereich automatisch** (vor dem Durchlauf aus 4097 Stützstellen des gesamten x-Bereichs ermittelt): Minimum/Maximum; bei extremen Ausreißern (Spanne > 3 × 1 %–99 %-Quantilspanne, z. B. Polstellen) die Quantile. Konstante Funktionen → `u = 0,5` (mittlere Frequenz, geometrisches Mittel). Nirgends definiert → Stille. **Manuell**: yLow/yHigh frei einstellbar.
* Kontinuierliche Oszillatorphase (`phase += f/sampleRate` in Zyklen, entspricht `2π·f/sampleRate` in Radiant).
* Klangfarben: **Sinus**, **Dreieck**, **Obertonreich**. Dreieck und Obertonreich kommen aus bandbegrenzten Wavetables (additiv per inverser FFT aufgebaut, 3 Tabellen pro Oktave, Obertöne ≤ 0,45 · Abtastrate für die *höchste* Grundfrequenz jedes Bandes, stetige Überblendung zwischen Bändern). Frequenzen werden auf 0,45 · Abtastrate begrenzt.
* Glättungen: Tonhöhengleiten als Einpol-Filter auf log₂(f) (Standard 8 ms, einstellbar 0–200 ms); lineare 5-ms-Stummschaltrampe an Definitionslücken (die Zeit läuft weiter, der Punkt wird ausgeblendet); Raised-Cosine-Ein-/Ausblendung (Standard 20 ms); definierter Spitzenpegel (Standard −3 dBFS).

### Zusatzmodus „Formel als Klangwelle“

> Hier wird die Kurve selbst zur Klangwelle. Die Grundfrequenz bestimmt, wie oft der gewählte Abschnitt pro Sekunde wiederholt wird.

`p(t) = Bruchteil(Grundfrequenz·t)`, `x(t) = Anfang + (Ende − Anfang)·p(t)`, `sample(t) = normalisiert(f(x(t)))`.
Die Abschnittsgrenzen sind eigene Einstellungen (nicht die Parameter a/b).
Aufbau der periodischen Wavetable (4096 Punkte): undefinierte Werte → 0 (Anteil wird angezeigt), DC-Entfernung, sanfte Begrenzung extremer Ausreißer (tanh), Fourier-Analyse, Entfernen aller Obertöne über 0,45·Abtastrate/Grundfrequenz mit Lanczos-σ-Gewichtung (Anti-Aliasing auch für den Sprung zwischen Abschnittsende und -anfang, wenig Gibbs-Überschwingen), Normalisierung auf Spitze 1 → kein Clipping.
Die Wellenform wird mit Hinweisen angezeigt. Da ein Phasencursor bei z. B. 220 Hz mit 60–120 Bildern/s nur als irreführendes Stroboskop-Muster darstellbar wäre, leuchtet während der Wiedergabe die ganze Periode; optional zeigt die deutlich beschriftete **„Zeitlupe der Wellenform“** den Cursor mit 2 s pro Durchlauf.

Das genaue Audioverfahren des Referenzvideos ist unbekannt – die App implementiert diese beiden definierten Verfahren und behauptet keine exakte Rekonstruktion.

## Formel-Synthesizer

Modusauswahl oben in „Graph & Klang“: **Graph vertonen · Klangwelle · Synthesizer · Pendel**. Die bisherigen Modi und gespeicherten Projekte behalten ihre Bedeutung unverändert.

**Musikalische Zeit:** Tempo (30–300 BPM), Beats pro Takt (1–12), Takte (1–64), höchstens 120 s pro Durchlauf. Alle Zeitvariablen werden samplegenau aus der Audiouhr berechnet (`MusicalClock`), nie aus Bildern. Die Bedeutung von `x` wird pro Projekt gewählt: Sekunden (`x = t`), Beats (`x = beat`) oder freier Durchlauf von x₀ bis x₁.

**Stimmen (bis 8):** Name, Farbe, Sichtbarkeit, Stumm/Solo, Lautstärke (dB), Panorama, Auslöser, Klangquelle, eigene Definitionen und Parameter, Polyphonie. Jede Formel hat eine ausdrückliche Rolle mit sichtbarer Bedeutung:

| Rolle | Bedeutung |
|---|---|
| **A – Tonhöhe** | Einheit wählbar: Hz, Halbtöne (`f = Grundfrequenz · 2^(s/12)`), Oktaven (`f = Grundfrequenz · 2^o`) oder „Graph → Ton“ (bisherige Zuordnung `[yLow, yHigh] → [fLow, fHigh]`); optional Tonleiter-Quantisierung (chromatisch, Dur, Moll, Pentatonik) und Glide |
| **B – Amplitude** | linear (≥ 0) oder dB (`10^(A/20)`, ≤ −120 dB stumm), z. B. `exp(-4*localTime)` |
| **C – Audiosignal** | periodisch (eine Periode über einem Abschnitt, Tonhöhe aus A) oder direkt (Abtastwerte aus `t`, `localTime` …); Gleichanteil wird entfernt, optional automatisch normalisiert, Formel 1–8-fach überabgetastet und mit FIR-Tiefpass heruntergerechnet (Anti-Aliasing) |
| Anzeige | Kurven, die nur gezeichnet werden (Einheiten Hz, Halbtöne, Oktaven, Verstärkung, Wert, Signal) |

Weitere Klangquellen: bandbegrenzte Oszillatoren (Sinus, Dreieck, Sägezahn, Rechteck, obertonreich; Unisono mit Verstimmung), synthetische Schlaginstrumente (Kick, Snare, Hi-Hat, Cowbell mit reproduzierbarem Rauschen) und der Endless Riser.

**Parameter:** konstant mit Regler oder als Liste, die pro Beat bzw. pro Takt weiterschaltet (`p = [1, 2, 4][mod(bar, 3)]`). Projektweite und stimmeneigene Definitionen.

**Mischung:** Die Stimmen werden als Signale addiert (nicht ihre Formeln), mit Reserve 1/√(hörbare Stimmen), Projektpegel (Spitze) und einem weichen Schutzbegrenzer bei −1 dBFS (angezeigt, wenn er eingreift). Ausgabe in Stereo mit Panorama.

**Mehrspur-Graph:** Bahnen je Einheit (oder alle Tonhöhen gemeinsam in Hz auf log-Achse), Amplitudenbahn, Ereignisbahn mit Aufleuchten und „Rate begrenzt“-Markierung, Riser-Bahn, Takt-/Beat-Raster, gemeinsamer Cursor, wachsende Kurven, Punkte, Leuchtspuren und ein Audioausschnitt mit Millisekundenachse (aus den echten Stimmsignalen der Vorschau). Legende (Antippen blendet Stimmen aus), Live-Werte (Takt, Beat, t, Frequenz und Pegel jeder Stimme, aktuelle Parameter), Vollbild, Hoch- und Querformat.

## Pendel, Riser, Beschleunigung und Sequencer

* **Pendel:** `position = cos(2π · N · beat / P)`; Auslösen beim Mitteldurchgang (eine oder beide Richtungen) zu den analytisch berechneten Zeitpunkten `beat = (P/4 + m·P/2)/N`. Das Aufleuchten in der Pendelansicht nutzt dieselben Zeitpunkte – ausgelassene Bilder verlieren oder verdoppeln nichts. Einstellbar: Anzahl, kleinstes N, P, Richtung, Grundfrequenz, Noten.
* **Endless Riser:** Shepard-/Risset-Prinzip – mehrere Teiltöne im Oktavabstand steigen gemeinsam, werden oben weich aus- und unten wieder eingeblendet. Psychoakustische Illusion eines endlos steigenden Klangs; die Frequenzen selbst steigen nicht unbegrenzt.
* **Beschleunigte Wiederholung:** Rate in Ereignissen pro Beat als Formel; Phase = ∫ Rate d(beat) (Mittelpunktregel in 16-Sample-Blöcken, exakte Lage des Durchgangs), Ereignis bei jedem ganzzahligen Phasendurchgang; über der Höchstrate (Standard 24/s) wird sichtbar begrenzt.
* **Sequencer:** Fibonacci modulo m (direkt modulo m berechnet, Rest wählt die Note), Pascal-Dreieck modulo 2 (`k & r = k`, begrenzte Gleichzeitigkeit), Quintenzirkel chromatisch (`mod(7n, 12)`) und diatonisch, Tritonus. Rhythmusmuster (`x` Schlag, `o` leise, `.` Pause) laufen unabhängig von der Notenfolge; die Note steht als `note` in der Tonhöhenformel.

## Presets

Die Presets setzen die beschriebenen mathematischen Strukturen mit ausdrücklichen Formelrollen um und sind vollständig editierbar. Sie sind von mathematischen Musikvideos inspiriert, **reproduzieren aber keine Originalspuren**.

* **Klassische Beispiele** (unverändert): Sanfte Welle, Doppelwelle, Stufen, Gedämpfte Welle, Wellenkamm, Experiment, Parameterwelle.
* **20 Formel-Presets:** Kick Roll, 808 Slide, Reverse Bass, Quantized Sine, Shapeshifter, Drum Pattern, Staircase, Saturation, Fraktale Summe, Chirp, Stutter, Damped Spring, Reese / Schwebung, Hoover, Hyperbolic Drop, Call and Response, Wobble, Tan Screech, Fourier Square, Walsh / Rademacher.
* **Sequencer:** Fibonacci-Bass, Pascal-Dreieck, Quintenzirkel, Tritonus.
* **Generatoren:** Sechs Pendel, Endless Riser, Beschleunigte Wiederholung.
* **Kombinationen:** Kick Roll + Cowbell, Tritone Bass + Hoover, Bass + Drum Pattern, Hyperbolic Drop + Tan Screech, Final Boss.

Im Synthesizer können die Stimmen eines Presets mit „Stimmen hinzufügen“ in das aktuelle Projekt übernommen werden (Projekt-Parameter und -Definitionen werden in die Stimmen kopiert).

## Anleitungen

Eigener Tab mit Suche nach Symbol (`Σ`, `Π`, `π`, `√`), deutschem Namen (Summe, Betrag) oder Befehl (`sum`, `abs`) und Kategorien: Grundzeichen, Funktionen, Summen und Produkte, Bedingungen, Listen und Definitionen, Zeit und Musik, Klang und Formelrollen, Generatoren und Presets. Jeder Eintrag zeigt Symbol, lesbare Darstellung, Erklärung, exakte Eingabe (kopierbar), Argumenttabelle mit Position in der Darstellung, Beispiele mit Ergebnis, Graph-Beispiel und Hinweise. „Im Editor öffnen“ lädt das Beispiel mit passender Rolle, Modus und Parametern; ungespeicherte Änderungen werden vorher abgefragt. Der Pflichteintrag **Σ** enthält ein beschriftetes Diagramm, welches Argument (Laufvariable, Start, Ende, Ausdruck) wo im gesetzten Summenzeichen erscheint.

Funktions-, Operator- und Variableneinträge werden aus denselben Katalogen erzeugt, die der Parser verwendet; Tests prüfen, dass jede Funktion dokumentiert ist und alle Beispiele das angegebene Ergebnis liefern.

## Ressourcengrenzen und Sicherheit

| Grenze | Wert |
|---|---|
| Formeltext | 4 000 Zeichen, 80 Zeilen, 500 Zeichen pro Zeile |
| Schachtelung | 64 Ebenen |
| Listen | 1 024 Einträge |
| Σ/Π | 10 000 Durchläufe pro Schleife, 200 000 pro Auswertung (verschachtelt zusammen) – darüber Definitionslücke statt Hänger |
| Ausdrucksbaum nach Einsetzen der Hilfsfunktionen | 20 000 Knoten |
| Ereignisse pro Stimme | 20 000 |
| Stimmen | 8 |
| Durchlauf | 120 s |

Formeln werden nur geparst und ausgewertet – keine Codeausführung, kein `eval`, kein Netzwerk.

## Audiowiedergabe

* AVAudioEngine + AVAudioPlayerNode; das PCM wird vorab asynchron (außerhalb des Main Threads) erzeugt und mit 44,1 kHz Mono abgespielt (bitgleich zum Standardexport); der Mixer passt an die Hardware-Rate an.
* **Die tatsächlich abgespielte Audiozeit ist die Zeitquelle**: Position = `playerTime(forNodeTime: lastRenderTime)` (zwischen zwei Render-Zyklen mit der Host-Uhr interpoliert) **minus Ausgabelatenz** (`AVAudioSession.outputLatency`, wichtig bei Bluetooth). Die Anzeige (`TimelineView`) liest diese Uhr nur ab.
* Abspielen, Pause/Fortsetzen (klickfrei durch 30-ms-Blende), Stopp mit Zurücksetzen, Wiederholung (nahtlos, Ein-/Ausblendungen an den Enden), Lautstärke (wirkt nur auf die Vorschau), Dauer 1–120 s, moderate Standardlautstärke 60 %.
* Formel-, Parameter- oder Klangänderungen stoppen den Durchlauf; der nächste Start erzeugt eine neue, unveränderliche Konfiguration. Veraltete Berechnungsergebnisse werden über Generationszähler verworfen.
* Behandelt: Audio-Unterbrechungen (Anruf, Siri), Kopfhörer abziehen (Pause), Ausgabegerätewechsel/Konfigurationsänderung der Engine (Neustart an derselben Position), Neustart der Mediendienste, Wechsel in den Hintergrund (Pause, Engine aus).
* Im Audio-Render-Pfad gibt es keine Parser-Aufrufe, Dateizugriffe, Sperren oder Allokationen (es wird nur ein fertiger Puffer abgespielt).

## Audioexport

| Format | Codec / Container | Optionen (Standard fett) |
|---|---|---|
| **WAV** | lineares PCM, RIFF/WAVE, Stereo | **16 Bit**, 24 Bit; **44,1 kHz**, 48 kHz |
| **M4A** | AAC-LC im MPEG-4-Container (AVAudioFile/ExtAudioFile) | 128, 160, **192**, 256, 320 kbit/s (CBR) |
| **MP3** | MPEG-1 Layer III (LAME 3.100) mit LAME-„Info“-Tag (exakte Länge, Encoder-Delay/Padding) | 128, 160, **192**, 224, 256, 320 kbit/s (CBR); Kodierqualität Maximal/**Hoch**/Schnell |

* Vorschau und Export nutzen **denselben `PCMRenderer`** und dieselbe unveränderliche `RenderConfiguration` (Formel, Parameter, Modus, Bereiche, Frequenzen, Klangfarbe, Glättung, Dauer, Normalisierung, Blenden, Pegel). Die Systemlautstärke und der Lautstärkeregler beeinflussen die Datei nicht.
* Exportiert wird genau **ein vollständiger Durchlauf** (eine aktivierte Wiederholung führt nicht zu einem endlosen Export); die Dauer ist im Exportdialog einstellbar.
* Asynchron und chunkweise (16 384 Frames): Rendern → direkt kodieren → in eine temporäre Datei schreiben → erst bei Erfolg umbenennen. **Abbrechen** löscht alle Teil-Dateien.
* Nach dem Export wird die Datei mit AVFoundation geöffnet und Codec, Abtastrate, Kanäle und dekodierbare Dauer angezeigt.
* Aktionen: **„In Dateien sichern“** (Dokumentauswahl, Kopie), **Teilen** (iOS-Teilen-Menü), **„Anhören“** (spielt die exportierte Datei selbst ab).
* Fertige Exporte liegen in `Library/Caches/Exports/…` und bleiben verfügbar, bis Teilen/Sichern abgeschlossen ist; sie werden bei einem späteren App-Start nach 24 h entfernt.
* Dateiendungen/UTTypes: `.mp3` (`public.mp3`), `.wav` (`com.microsoft.waveform-audio`), `.m4a` (`com.apple.m4a-audio`).

## Speicherung und Datenmigration

Eigene Presets liegen in SwiftData (lokal, ohne CloudKit). Das Schema ist versioniert (`SavedPresetSchemaV1` → `SavedPresetSchemaV2`) mit einem `SchemaMigrationPlan` (leichtgewichtige Migration): V2 ergänzt nur das optionale Attribut `projectData` (JSON des Synthesizer-Projekts). Vorhandene Presets bleiben unverändert erhalten und behalten ihre Bedeutung; ein Test öffnet einen V1-Speicher mit V2 und prüft alle Felder. Das Projekt-JSON wird tolerant dekodiert (fehlende Felder erhalten Standardwerte), sodass spätere Erweiterungen alte Projekte lesbar lassen. Der Sitzungszustand (inkl. Synthesizer- und Pendelprojekt) liegt weiterhin als JSON in `UserDefaults`.

## Design

Das gesamte Design ist aus dem App-Icon abgeleitet (Farben im Icon gemessen):

* Hintergrund nahezu schwarz (#06070F) mit dunkelblauem (#0D142B) und violettem (#1A0B2E) Verlauf, dezente grüne Audiobalken wie im Icon.
* Hauptfarbe Discord-Blauviolett **#5865F2**, Akzent Spotifygrün **#1DB954**, Neongrün der Augen für Leuchteffekte.
* Metallische Rahmen (Verlauf hell #D4D3FF → #5358FD → #3A33D5 → #14125E) mit Lichtkanten wie die Hörner.
* Wiederverwendbares Theme (`Theme/`): Panel mit konkaven Eckschnitten und Seitenklingen, **Hornpaar mit Krone und grünen Augen** auf Graphkarte, Kopfbereich und Exportkarte, Klingenform für „Graph abspielen“ (grünes Play-Symbol), Runen-Buttons für Pause/Stopp/Wiederholung, Rauten als Regler-Knopf, Achsenspitzen und Aufzählungszeichen (wie die Achsenenden im Icon), eigene Tab-Leiste, Segment-Auswahl und Schalter.
* Graph: dunkle Fläche, blauviolette Achsen und Raster, abgespielte Kurve grün mit kontrolliertem Leuchten, Punkt mit hellem Kern und Lichtschein, gedämpfte Vorschau, optionale Positionslinie. Der **helle Graphmodus** ändert nur die Graphfläche (heller Hintergrund, schwarze Achsen/Kurve).
* Barrierefreiheit: Dynamic Type (Textstile, mitwachsende Formelschrift), VoiceOver-Beschriftungen auf Deutsch, Graph als **Audiograph** (`AXChartDescriptor`), Kontraste ≥ 4,5 : 1 für Text, „Bewegung reduzieren“ (keine Skalierungsanimationen, 30 fps statt ProMotion), Touchflächen ≥ 44 pt. Dekoration ist nicht antippbar und verdeckt keine Inhalte.

## Architektur

```
DemonicGraphAudiolyzer/
  Core/            plattformunabhängig (nur Foundation), auch unter Linux getestet
    Formula/       Lexer, Parser (Syntaxbaum), Katalog, Binder, Compiler, Mathe-Layout, Editor-Logik
    Synth/         Projektmodell, musikalische Zeit, Ereignisplanung, Sequencer, Pendel, Riser,
                   Kompilierung, Render-Plan, Stereo-Renderer, Graph-Analyse
    Graph/         adaptive Abtastung, Sichtbereich, Achsenteilung
    DSP/           FFT, bandbegrenzte Wavetables, Filter
    Sound/         klassische Modi (SoundPlan, PCMRenderer), RenderJob für Vorschau und Export
    Playback/      Transport-Zustandsautomat, Zeitlinie (Pause/Loop-Mathematik)
    Export/        Exportoptionen, WAV-Writer
    Presets/       Preset-Werttyp, klassische Beispiele, Synthesizer-Presets
    Guide/         Katalog der Anleitungen, Themen, „Im Editor öffnen“
  Audio/           AVAudioEngine-Wiedergabe (Stereo), Vorschau-Rendering
  Export/          Exporter (chunkweise), AAC-/MP3-/WAV-Encoder, Export-Modell
  Persistence/     SwiftData-Schema V1/V2 mit Migration, Einstellungen, Sitzungszustand
  Model/           AudiolyzerModel (MainActor, @Observable)
  Theme/           dämonisches Theme: Farben, Formen, Komponenten
  Views/           SwiftUI: Graph & Klang (alle Modi), Synthesizer, Formeleditor, Presets,
                   Anleitungen, Einstellungen, Vollbild, Export
Packages/LameKit/  LAME 3.100 + Swift-Schnittstelle
```

Zustände: *Bereit, Formel ungültig, Audio wird vorbereitet, Wiedergabe, Pausiert, Export läuft, Fehler* (`TransportStateMachine`).
Presets: eigene Presets in SwiftData (lokal, `cloudKitDatabase: .none`) mit ID, Name, Formel, Parametern, Modus, x-Bereich, Klangbereich, Wellenformabschnitt, Grund-/Frequenzbereich, Klangfarbe, Glättung, Blende, Pegel, Dauer, Erstell- und Änderungsdatum sowie (ab Schema V2) dem vollständigen Synthesizer-Projekt.
Vorschau und Export verwenden denselben unveränderlichen `RenderJob` und denselben Renderer – Ereignisse, Parameter, Hüllkurven, Rauschen und Pegel sind identisch.
Alle mitgelieferten Presets sind Konstanten im Code (mit festen IDs) – sie werden nie in die Datenbank geschrieben und daher nicht bei jedem Start neu erzeugt.
Der letzte Arbeitszustand (Formel, Parameter, Einstellungen, Synthesizer- und Pendelprojekt, Ausschnitt, Lautstärke, Wiederholung) wird als JSON in `UserDefaults` gesichert und beim Start wiederhergestellt; UI-Präferenzen über `@AppStorage`.

## Tests und ausgeführte Prüfungen

**Unit-Tests** (`DemonicGraphAudiolyzerTests`, Swift Testing):

| Datei | Inhalt |
|---|---|
| `FormulaParserTests` | Präfixe, Rangfolge, implizite Multiplikation, alle Funktionen, `mod`, Definitionslücken, Compiler = Interpreter, Syntaxfehler mit Position |
| `GraphSamplerTests` | stetige Kurven, Polstellen/Sprünge ohne falsche Linien, Definitionsränder, Ausreißer, Achsen, Zoom/Pan |
| `SoundSynthesisTests` | Frequenzzuordnung, konstante Funktionen, Ausreißer, endliche/begrenzte Samples, Sampleanzahl/Dauer, Blenden, Stummschaltung, Chunk-Invarianz (Vorschau = Export), Bandbegrenzung, Klangwelle |
| `TransportTests` | Abspielen/Pause/Fortsetzen/Stopp/Wiederholung als Zustandsautomat und Zeitlinie |
| `WAVWriterTests`, `SessionStateTests` | RIFF-Header, 16/24 Bit, Wiederherstellung nach Neustart, Standardwerte |
| `ProjectConfigurationTests` | Bundle-ID in allen App-Konfigurationen, Test-IDs, App-Icon 1024 px ohne Alpha |
| `AudioExportTests` *(nur Apple)* | echte Codecs (PCM/AAC/MP3) per AVFoundation dekodiert, Container-Signaturen, Dauer inkl. Codec-Padding, Pegel, Vorschau = Export bitgenau, 120-s-Export ohne blockierten Main Actor, Abbrechen räumt auf |
| `PersistenceTests` *(nur Apple)* | SwiftData: Preset übersteht „Neustart“ (neuer Container), alle Felder, Umbenennen/Überschreiben/Löschen, Migration V1 → V2, Synthesizer-Projekt hin und zurück |
| `PlaybackIntegrationTests` *(nur Apple)* | echte AVAudioEngine: Position aus der Audiouhr, Pause hält die Zeit an, Fortsetzen, Stopp, Ende, Wiederholung |
| `FormulaLanguageTests` | Vergleiche, Logik, lazy `if`/`piecewise`, `frac`, `clip`, `atan`/`arctan`, Σ/Π mit Gültigkeitsbereichen und Grenzen, Listen ab 0, `len`, Hilfsfunktionen, mehrzeilige Definitionen, Zyklen, unbekannte Namen, griechische Aliase, Ressourcengrenzen, `-x^2`/`2^3^2` |
| `FormulaEditingTests` | lesbare Darstellung (Σ mit Grenzen, Brüche, Potenzen, Wurzel, Betrag, Fallunterscheidungen, mehrzeilige Programme), Signaturhilfe mit aktivem Argument, Fallunterscheidungs- und Σ/Π-Editor lesen und schreiben |
| `MusicalTimingTests` | beat/bar/beatInBar, samplegenaue Trigger bei jedem Tempo, exakte Loop-Länge, Rate-Integration (Phase = Integral) und sichtbare Begrenzung, Pendel analytisch ohne verlorene/doppelte Trigger, Fibonacci mod m (Pisano), Pascal mod 2 per Bitlogik, chromatische vs. diatonische Quinten, Rhythmus und Notenliste verschiedener Länge, Tritonus |
| `SynthRenderTests` | alle Presets fehlerfrei und sauber, 808-Slide (Frequenzen, Phase), Reverse-Bass-Hüllkurve, Mischung als Signale mit Reserve 1/√N, Panorama/Mute/Solo, Begrenzer, Vorschau = Export bei jeder Blockgröße, reproduzierbares Rauschen, Bandbegrenzung (Sägezahn, Fourier-Rechteck, Sättigung), samplegenaue Ausrichtung überabgetasteter Formelsignale, Shepard-Riser, Parameter pro Takt und Tonhöheneinheiten, x-Zuordnung, Fehlerzuordnung zu Stimme und Rolle, tolerantes JSON |
| `SynthAnalysisTests` | Bahnen je Einheit, Anzeigekurven, Ereignis-/Riser-Bahn, aktiver Fall, aktuelle Parameter, Zahlenlisten |
| `GuideTests` | jede Funktion und jeder Operator dokumentiert, Argumentpositionen wie im Parser, alle Beispiele mit dem echten Parser ausgewertet, Σ-Pflichteintrag, „Im Editor öffnen“ vollständig konfiguriert, Suche nach Symbol/Name/Befehl, offline ohne Weblinks, Tab-Reihenfolge |

**UI-Tests** (`DemonicGraphAudiolyzerUITests`, XCTest): Formel eingeben → Graph anzeigen → abspielen → pausieren → stoppen; ungültige Formel; Querformat; Presets/Einstellungen erreichbar; Synthesizer- und Pendel-Modus wählen, abspielen, stoppen, Stimmeneditor; Anleitungen durchsuchen, Σ-Eintrag öffnen, Beispiel im Editor öffnen; Start-Screenshot.

**Tatsächlich ausgeführt**

*In der Entwicklungsumgebung (Linux, ohne Xcode):*

* Swift 6.1 (offizielle Ubuntu-Pakete): Kernmodul + plattformunabhängige Tests → **57 Tests bestanden** (Parser, Abtastung, Klang/PCM, Transport, WAV, Sitzungszustand, Projekt-/Icon-Prüfung).
* `swift test` für `Packages/LameKit` → **5 Tests bestanden**; erzeugtes MP3 mit `ffprobe`/`ffmpeg` geprüft (MPEG-1 Layer III, 192 kbit/s, exakt 2,000 s dank Info-Tag, 440 Hz).
* Gerenderte Presets spektral analysiert: keine Aliasing-Anteile (< 10⁻⁵ der Energie außerhalb der Harmonischen), keine Knackser an Definitionslücken; 10 s Audio werden in ca. 30 ms erzeugt (Release-Build, x86-64).
* `project.pbxproj` maschinell geparst (Paketreferenz, Bundle-IDs, Deployment Target); LAME-Quellen per `verify-lame-sources.sh` gegen das Original verifiziert.

*Auf macOS mit Xcode 26 (GitHub Actions, Workflow `.github/workflows/ios.yml`, Runner `macos-26`, Simulator „iPhone Air“, iOS 26.5):*

* `swift test` für LameKit auf macOS → bestanden.
* **Release-Build für iPhone** (`generic/platform=iOS`, arm64, ohne Signierung) → **BUILD SUCCEEDED**.
* **Unit-Tests im Simulator: alle bestanden** (Swift Testing, 10 Suites), u. a. echte AAC-/MP3-/WAV-Exporte mit AVFoundation-Dekodierung, 120-s-Export ohne blockierten Main Actor, Vorschau = Export bitgenau, SwiftData-Neustart, Wiedergabe mit echter AVAudioEngine (Pause hält die Audiouhr an, Fortsetzen, Ende, Wiederholung).
* **UI-Tests im Simulator: alle bestanden** – Formel eingeben → Graph anzeigen → abspielen → pausieren → stoppen, ungültige Formel, Querformat inkl. Vollbild, Presets/Einstellungen/Exportdialog, Start-Screenshots in allen UI-Konfigurationen.
* Screenshots aller Hauptansichten (Hoch- und Querformat, Wiedergabe, Pause, Formelfehler, Presets, Einstellungen, Export, Mathe-Tastatur) wurden aus dem Testlauf ausgewertet; sie liegen als Artefakt `ui-screenshots` am jeweiligen Workflow-Lauf.

*Noch auf einem echten iPhone selbst zu prüfen* (hier nicht möglich): Signierung mit dem eigenen Team und Installation, Homescreen-Icon auf dem Gerät, Klang über Lautsprecher/Kopfhörer/Bluetooth (Latenzausgleich), Kopfhörer-Abziehen und Anrufe, „In Dateien sichern“ und Teilen mit echten Ziel-Apps, Bedienung mit VoiceOver und sehr großen Schriftgrößen, Leistung auf älteren Geräten.

### Build-Status

Jeder Push auf `main` oder `claude/**` und jeder Pull Request startet „iOS Build & Tests“ (LameKit-Tests, iPhone-Build, Unit- und UI-Tests im Simulator). Ergebnisse, Logs, `.xcresult`-Bundles und Screenshots stehen als Artefakte am Lauf.

## Verbleibende Einschränkungen

* Keine Hintergrundwiedergabe (gewollt; die App pausiert im Hintergrund).
* Klassische Modi: Export in Stereo mit identischen Kanälen (das Signal ist mono erzeugt); Synthesizer und Pendel sind echtes Stereo mit Panorama.
* Formel-Audiosignale (Rolle C) werden pro Stimme mono berechnet und dann im Panorama platziert.
* Die Pausen-/Stopp-Blende wird über die Mischer-Lautstärke in 8 Stufen à ca. 4 ms gefahren – sehr leise, aber nicht sample-genau.
* MP3 über LAME unterliegt der LGPL (siehe oben) – vor einer App-Store-Veröffentlichung prüfen.
* Exponentialschreibweise für Zahlen (`1e-3`) und reelle ungerade Wurzeln negativer Zahlen über `^` (z. B. `(-8)^(1/3)` → undefiniert, wie `pow`) werden nicht unterstützt.
* Die Klang- und Bildverfahren der Referenzvideos sind unbekannt; implementiert sind die oben definierten Verfahren. Presets sind Nachbildungen der beschriebenen mathematischen Strukturen, keine Reproduktion der Originalspuren.
* Der Endless Riser ist eine psychoakustische Illusion (Shepard/Risset), kein unbegrenzt steigender Ton.
* Die Synthesizer-Vorschau wird vor dem Abspielen vollständig berechnet (bis 120 s); Änderungen während der Wiedergabe beenden den Durchlauf und werden beim nächsten Start übernommen.
