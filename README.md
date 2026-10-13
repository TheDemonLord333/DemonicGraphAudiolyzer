# Demonic Graph Audiolyzer

Native iOS-App (SwiftUI, Swift, SwiftData), die mathematische Funktionen in **sichtbare und hörbare Graphen** verwandelt:
Formel eingeben → Graph im x-y-Koordinatensystem sehen → „Graph abspielen“ → ein leuchtender Punkt wandert von links nach rechts,
die Kurve entsteht schrittweise und gleichzeitig erklingt der aus der Funktion erzeugte Klang → Export als **MP3, WAV oder M4A**.

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
8. [Audiowiedergabe](#audiowiedergabe)
9. [Audioexport](#audioexport)
10. [Design](#design)
11. [Architektur](#architektur)
12. [Tests und ausgeführte Prüfungen](#tests-und-ausgeführte-prüfungen)
13. [Verbleibende Einschränkungen](#verbleibende-einschränkungen)

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
| Variable | `x` |
| Parameter | `a`, `b`, `c` – mit Schiebereglern (−10 … 10) und manueller Eingabe (beliebige Werte) |
| Konstanten | `pi` bzw. `π`, `e` |
| Operatoren | `+ - * / ^`, Klammern, unäres Minus; auch `×`, `÷`, `−`, `²`, `³`, `√` |
| Funktionen | `sin cos tan asin acos atan abs sqrt ln log10 exp floor ceil round min max mod` |
| Winkel | Radiant |
| Rangfolge | `-x^2 = -(x^2)`, `2^3^2 = 2^(3^2)`, `2^-1 = 0.5` |
| Implizite Multiplikation | `2x`, `2sin(x)`, `2(x+1)`, `(x+1)(x-1)`, `bx`, `2pi`, `sin(x)cos(3x)`. Buchstabenfolgen werden mit „längster Name zuerst“ zerlegt: `asin` ist der Arkussinus, für a·sin schreibe `a*sin(x)` oder `a sin(x)`. `1/2x` = (1/2)·x. Zwei Zahlen direkt hintereinander (`2 3`) sind ein Fehler. |
| `mod(a,b)` | `a − b·floor(a/b)`, nur für endliches `b > 0` definiert; sonst Definitionslücke |
| `round` | rundet Hälften von null weg (2,5 → 3, −2,5 → −3) |
| Dezimalzahlen | mit Punkt (`0.5`); Komma bzw. Semikolon trennt Funktionsargumente. `0,5` außerhalb einer Funktion ergibt eine Korrekturmeldung. Exponentialschreibweise (`1e5`) wird bewusst nicht unterstützt (Verwechslung mit der Konstante `e`). |

Der Parser ist ein eigener Tokenizer + rekursiver Abstiegsparser mit AST (`Core/Formula`). Es wird **kein Code ausgeführt**; unbekannte Zeichen und Namen werden abgelehnt. Fehler werden deutsch und mit Position gemeldet (die fehlerhafte Stelle wird markiert). Division durch null, Polstellen, `NaN` und ±∞ werden als Definitionslücken behandelt.
Die Zusatztastatur über der Systemtastatur enthält Variablen, Konstanten, Operatoren, Klammern und alle Funktionen und fügt am Cursor ein (Funktionen mit Cursor in der Klammer).

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
    Formula/       Tokenizer, Parser (AST), Auswertung/Kompilierung
    Graph/         adaptive Abtastung, Sichtbereich, Achsenteilung
    DSP/           FFT, bandbegrenzte Wavetables
    Sound/         Einstellungen, Tonhöhen-Zuordnung, SoundPlan, PCMRenderer
    Playback/      Transport-Zustandsautomat, Zeitlinie (Pause/Loop-Mathematik)
    Export/        Exportoptionen, WAV-Writer
    Presets/       Preset-Werttyp, mitgelieferte Beispiele
  Audio/           AVAudioEngine-Wiedergabe, Vorschau-Rendering
  Export/          Exporter (chunkweise), AAC-/MP3-/WAV-Encoder, Export-Modell
  Persistence/     SwiftData-Modell `SavedPreset`, Einstellungen, Sitzungszustand
  Model/           AudiolyzerModel (MainActor, @Observable)
  Theme/           dämonisches Theme: Farben, Formen, Komponenten
  Views/           SwiftUI: Graph & Klang, Presets, Einstellungen, Vollbild, Export
Packages/LameKit/  LAME 3.100 + Swift-Schnittstelle
```

Zustände: *Bereit, Formel ungültig, Audio wird vorbereitet, Wiedergabe, Pausiert, Export läuft, Fehler* (`TransportStateMachine`).
Presets: eigene Presets in SwiftData (lokal, `cloudKitDatabase: .none`) mit ID, Name, Formel, Parametern, Modus, x-Bereich, Klangbereich, Wellenformabschnitt, Grund-/Frequenzbereich, Klangfarbe, Glättung, Blende, Pegel, Dauer, Erstell- und Änderungsdatum.
Die sieben mitgelieferten Beispiele sind Konstanten im Code – sie werden nie in die Datenbank geschrieben und daher nicht bei jedem Start neu erzeugt.
Der letzte Arbeitszustand (Formel, Parameter, Einstellungen, Ausschnitt, Lautstärke, Wiederholung) wird als JSON in `UserDefaults` gesichert und beim Start wiederhergestellt; UI-Präferenzen über `@AppStorage`.

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
| `PersistenceTests` *(nur Apple)* | SwiftData: Preset übersteht „Neustart“ (neuer Container), alle Felder, Umbenennen/Überschreiben/Löschen |
| `PlaybackIntegrationTests` *(nur Apple)* | echte AVAudioEngine: Position aus der Audiouhr, Pause hält die Zeit an, Fortsetzen, Stopp, Ende, Wiederholung |

**UI-Tests** (`DemonicGraphAudiolyzerUITests`, XCTest): Formel eingeben → Graph anzeigen → abspielen → pausieren → stoppen; ungültige Formel; Querformat; Presets/Einstellungen erreichbar; Start-Screenshot.

**Tatsächlich ausgeführt (in dieser Entwicklungsumgebung, Linux ohne Xcode):**

* Swift 6.1 (offizielle Ubuntu-Pakete): Kernmodul + plattformunabhängige Tests → **56 Tests bestanden** (Parser, Abtastung, Klang/PCM, Transport, WAV, Sitzungszustand, Projekt-/Icon-Prüfung).
* `swift test` für `Packages/LameKit` → **5 Tests bestanden**; erzeugtes MP3 mit `ffprobe`/`ffmpeg` geprüft (MPEG-1 Layer III, 192 kbit/s, exakt 2,000 s dank Info-Tag, 440 Hz).
* Gerenderte Presets spektral analysiert: keine Aliasing-Anteile (< 10⁻⁵ der Energie außerhalb der Harmonischen), keine Knackser an Definitionslücken.
* `project.pbxproj` maschinell geparst (Paketreferenz, Bundle-IDs, Deployment Target).
* LAME-Quellen per `verify-lame-sources.sh` gegen das Original verifiziert.

**Auf einem Mac (Xcode 26) bzw. iPhone:** Der Workflow `.github/workflows/ios.yml` baut auf einem macOS-Runner mit Xcode 26 die App für iPhone (unsigniert), führt die LameKit-Tests sowie alle Unit- und UI-Tests im iOS-Simulator aus. Ergebnis siehe Abschnitt [Build-Status](#build-status).
Auf einem echten iPhone noch selbst zu prüfen: Signierung mit dem eigenen Team, Homescreen-Icon, Klang über Lautsprecher/Kopfhörer/Bluetooth (Latenzausgleich), Kopfhörer-Abziehen und Anrufe, „In Dateien sichern“/Teilen, Bedienung mit VoiceOver und großen Schriftgrößen.

### Build-Status

Siehe GitHub Actions „iOS Build & Tests“ für den Branch dieses Stands.

## Verbleibende Einschränkungen

* Keine Hintergrundwiedergabe (gewollt; die App pausiert im Hintergrund).
* Exportiert wird Stereo (identische Kanäle); das Signal ist mono erzeugt.
* Die Pausen-/Stopp-Blende wird über die Mischer-Lautstärke in 8 Stufen à ca. 4 ms gefahren – sehr leise, aber nicht sample-genau.
* MP3 über LAME unterliegt der LGPL (siehe oben) – vor einer App-Store-Veröffentlichung prüfen.
* Exponentialschreibweise für Zahlen (`1e-3`) und reelle ungerade Wurzeln negativer Zahlen über `^` (z. B. `(-8)^(1/3)` → undefiniert, wie `pow`) werden nicht unterstützt.
* Die Klangdarstellung des Referenzvideos ist unbekannt; implementiert sind die zwei oben definierten Verfahren.
