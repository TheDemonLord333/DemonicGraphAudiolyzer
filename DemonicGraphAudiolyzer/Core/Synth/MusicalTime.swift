import Foundation

/// Position in musical time.
struct MusicalPosition: Equatable, Sendable {
    /// Seconds since the start of the pass.
    var time: Double
    var beat: Double
    /// Zero-based bar index: floor(beat / beatsPerBar).
    var bar: Double
    /// mod(beat, beatsPerBar)
    var beatInBar: Double
}

/// Sample-accurate conversion between frames, seconds and beats for a constant tempo.
///
/// The pass has exactly `totalFrames` frames, so loops repeat at the same frame grid and events
/// that are scheduled from beat positions fall on the same frames in every repetition.
struct MusicalClock: Equatable, Sendable {
    let tempo: TempoSettings
    let sampleRate: Double
    let framesPerBeat: Double
    let totalFrames: Int

    init(tempo: TempoSettings, sampleRate: Double) {
        self.tempo = tempo.clamped()
        self.sampleRate = sampleRate
        self.framesPerBeat = sampleRate * 60 / self.tempo.bpm
        self.totalFrames = max(1, Int((self.tempo.duration * sampleRate).rounded()))
    }

    var duration: Double { Double(totalFrames) / sampleRate }
    var totalBeats: Double { tempo.totalBeats }
    var beatsPerSecond: Double { tempo.bpm / 60 }

    @inline(__always)
    func time(atFrame frame: Double) -> Double { frame / sampleRate }

    @inline(__always)
    func beat(atFrame frame: Double) -> Double { frame / framesPerBeat }

    func position(atFrame frame: Double) -> MusicalPosition {
        let beat = self.beat(atFrame: frame)
        let perBar = Double(tempo.beatsPerBar)
        let bar = floor(beat / perBar)
        return MusicalPosition(time: time(atFrame: frame), beat: beat, bar: bar, beatInBar: beat - bar * perBar)
    }

    /// First frame at or after the given beat (an event at an exact beat sounds from that sample on).
    @inline(__always)
    func frame(atBeat beat: Double) -> Int {
        Int((beat * framesPerBeat - 1e-6).rounded(.up))
    }

    @inline(__always)
    func frame(atTime time: Double) -> Int {
        Int((time * sampleRate - 1e-6).rounded(.up))
    }
}

/// The value of x for a project (explicitly chosen per project).
struct XMappingFunction: Equatable, Sendable {
    let mapping: XMapping
    let freeXMin: Double
    let freeXMax: Double
    let clock: MusicalClock

    init(project: SynthProject, clock: MusicalClock) {
        self.mapping = project.xMapping
        self.freeXMin = project.freeXMin
        self.freeXMax = project.freeXMax
        self.clock = clock
    }

    @inline(__always)
    func x(atFrame frame: Double) -> Double {
        switch mapping {
        case .seconds: return frame / clock.sampleRate
        case .beats: return frame / clock.framesPerBeat
        case .freeRange: return freeXMin + (freeXMax - freeXMin) * frame / Double(clock.totalFrames)
        }
    }

    /// Inverse (for drawing the x axis of the lanes).
    func frame(atX x: Double) -> Double {
        switch mapping {
        case .seconds: return x * clock.sampleRate
        case .beats: return x * clock.framesPerBeat
        case .freeRange:
            let span = freeXMax - freeXMin
            guard span != 0 else { return 0 }
            return (x - freeXMin) / span * Double(clock.totalFrames)
        }
    }

    var range: ClosedRange<Double> {
        let first = x(atFrame: 0)
        let last = x(atFrame: Double(clock.totalFrames))
        return min(first, last)...max(first, last, min(first, last) + 1e-9)
    }
}
