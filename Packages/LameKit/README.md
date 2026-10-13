# LameKit

Schmale Swift-Schnittstelle (`MP3Encoder`) um den MP3-Encoder **LAME 3.100**.
iOS enthält keinen nativen MP3-*Encoder* (AVFoundation/AudioToolbox können MP3
nur dekodieren). Deshalb bindet Demonic Graph Audiolyzer LAME als lokales
Swift Package ein.

## Herkunft

| Eigenschaft | Wert |
|---|---|
| Projekt | LAME – https://lame.sourceforge.io |
| Version | 3.100 (offizielles Release vom 13.10.2017) |
| Quelle | https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz |
| SHA-256 des Archivs | `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e` |

Übernommen wurden **unverändert**:

* alle `.c`- und `.h`-Dateien aus `libmp3lame/` außer `mpglib_interface.c`
  (Decoder-Schnittstelle, ohne mpglib leer),
* `libmp3lame/vector/lame_intrin.h` (nur Deklarationen; SSE-Code wird nicht übersetzt),
* `include/lame.h`,
* `COPYING` → `COPYING-LAME.txt`, `LICENSE` → `LICENSE-LAME.txt`, `README` → `README-LAME.txt`.

Projektspezifisch ist nur `Sources/CLame/config.h` (ersetzt die von autoconf
erzeugte Datei; Begründung im Dateikopf). Es werden keine vorkompilierten
Binärdateien verwendet – Xcode übersetzt die Quellen für jede Zielarchitektur
(iPhone arm64, Simulator arm64/x86_64) selbst.

Prüfung der Herkunft (lädt das Original, prüft SHA-256 und vergleicht jede Datei):

```sh
Packages/LameKit/Scripts/verify-lame-sources.sh
```

## Lizenz

LAME steht unter der **GNU Library General Public License Version 2 (LGPL)**,
siehe `COPYING-LAME.txt` und `LICENSE-LAME.txt`. Konsequenzen:

* Der LAME-Quelltext muss mit ausgeliefert bzw. angeboten werden (liegt hier vollständig bei).
* Änderungen an LAME müssten unter der LGPL veröffentlicht werden (es gibt keine).
* Bei statischem Linken in eine App verlangt die LGPL, dass Empfänger die App mit
  einer geänderten LAME-Version neu linken können (z. B. durch Bereitstellung der
  Objektdateien bzw. des Quelltexts der App). Für die private Nutzung/Entwicklung
  auf dem eigenen iPhone ist das unproblematisch. **Vor einer Verteilung über den
  App Store muss diese Pflicht geprüft werden** (App-Store-Bedingungen und LGPL
  sind nicht ohne Weiteres vereinbar).
* Die MP3-Patente sind abgelaufen (2017); es fallen keine Patentlizenzen an.

## API

```swift
let encoder = try MP3Encoder(sampleRate: 44_100, channels: 2, bitrateKbps: 192)
var bytes = try encoder.encode(left: leftPointer, right: rightPointer, frameCount: n)
bytes += try encoder.finish()
let infoTag = encoder.infoTagFrame()   // an Offset 0 der Datei schreiben (Gapless-Info)
```

## Tests

`swift test` im Paketordner prüft u. a., dass ein gültiger MPEG-1-Layer-III-
Frame-Strom entsteht (jeder Frame-Header wird geparst), dass der LAME-Info-Tag
geschrieben wird und dass ungültige Konfigurationen abgelehnt werden.
