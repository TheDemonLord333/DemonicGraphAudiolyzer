import SwiftUI

/// Pendulums seen from above: every pendulum swings on its own track,
/// position = cos(2π · N · beat / P). The flash at the midline is computed from the analytic
/// trigger times (the same ones the audio uses), not from rendered frames.
struct PendulumStageView: View {
    @Environment(AudiolyzerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 20.0 : nil, paused: model.phase != .playing)) { _ in
            let snapshot = model.playbackSnapshot()
            let clock = model.compilation?.clock ?? MusicalClock(tempo: model.project.tempo, sampleRate: AudiolyzerModel.previewSampleRate)
            let beat = snapshot.map { clock.beat(atFrame: $0.frame) }
            Canvas { context, size in
                draw(in: &context, size: size, beat: beat, secondsPerBeat: clock.tempo.secondsPerBeat)
            }
        }
        .frame(height: CGFloat(max(pendulums.count, 1)) * 30 + 16)
        .background(DemonPanelShape(cornerCut: 10, spike: 0).fill(Color.black.opacity(0.55)))
        .clipShape(DemonPanelShape(cornerCut: 10, spike: 0))
        .overlay(DemonPanelShape(cornerCut: 10, spike: 0).stroke(DemonTheme.metalMid.opacity(0.75), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("Pendel")
        .accessibilityValue(pendulums.map { "\($0.name): N = \($0.trigger.pendulumCycles)" }.joined(separator: ", "))
        .accessibilityIdentifier("pendulumStage")
    }

    private var pendulums: [SynthVoice] {
        model.project.voices.filter { $0.trigger.kind == .pendulum }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, beat: Double?, secondsPerBeat: Double) {
        let voices = pendulums
        guard !voices.isEmpty else { return }
        let labelWidth: CGFloat = 54
        let top: CGFloat = 8
        let rowHeight = (size.height - 2 * top) / CGFloat(voices.count)
        let trackStart = labelWidth + 12
        let trackEnd = size.width - 14
        let center = (trackStart + trackEnd) / 2
        let amplitude = (trackEnd - trackStart) / 2

        var midline = Path()
        midline.move(to: CGPoint(x: center, y: 2))
        midline.addLine(to: CGPoint(x: center, y: size.height - 2))
        context.stroke(midline, with: .color(DemonTheme.blurple.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        for (row, voice) in voices.enumerated() {
            let y = top + rowHeight * (CGFloat(row) + 0.5)
            let color = voice.color.color
            let math = PendulumMath(trigger: voice.trigger)
            let position = math.position(atBeat: beat ?? 0)
            let x = center + amplitude * CGFloat(position)

            var flash = 0.0
            if let beat, let index = math.lastTriggerIndex(atOrBefore: beat) {
                let ageSeconds = (beat - math.triggerBeat(index)) * secondsPerBeat
                flash = exp(-ageSeconds * 7)
            }

            var track = Path()
            track.move(to: CGPoint(x: trackStart, y: y))
            track.addLine(to: CGPoint(x: trackEnd, y: y))
            context.stroke(track, with: .color(DemonTheme.metalMid.opacity(0.55)), lineWidth: 1)

            let label = Text("N = \(voice.trigger.pendulumCycles)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundColor(color)
            context.draw(label, at: CGPoint(x: 6, y: y), anchor: .leading)

            if flash > 0.02 {
                let radius = 10 + 14 * flash
                let ring = Path(ellipseIn: CGRect(x: center - radius, y: y - radius, width: radius * 2, height: radius * 2))
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4))
                    layer.fill(ring, with: .color(color.opacity(0.55 * flash)))
                }
            }
            let bobRadius: CGFloat = 7
            let bob = Path(ellipseIn: CGRect(x: x - bobRadius, y: y - bobRadius, width: bobRadius * 2, height: bobRadius * 2))
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(bob, with: .color(color.opacity(0.6 + 0.4 * flash)))
            }
            context.fill(bob, with: .color(color))
            context.stroke(bob, with: .color(.white.opacity(0.5 + 0.5 * flash)), lineWidth: 1)
        }
    }
}

/// Quick settings of the pendulum mode: number of pendulums, cycle, directions, notes.
struct PendulumSettingsCard: View {
    @Environment(AudiolyzerModel.self) private var model

    private var pendulums: [SynthVoice] {
        model.project.voices.filter { $0.trigger.kind == .pendulum }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemonSectionHeader(title: "Pendel", systemImage: "metronome")
            DemonCaption("Jedes Pendel schwingt mit position = cos(2π · N · beat / P). Beim Durchgang durch die Mitte erklingt seine Note. Nach P Beats sind alle Pendel mit ganzzahligem N wieder gleichphasig.")
            DemonStepper(title: "Anzahl der Pendel", value: Binding(get: { pendulums.count }, set: setCount),
                         range: 1...SynthProject.maximumVoices)
            DemonStepper(title: "Kleinstes N", value: Binding(get: { pendulums.map(\.trigger.pendulumCycles).min() ?? 6 }, set: setFirstCycles),
                         range: 1...48)
            DemonSlider(title: "Zykluslänge P", value: Binding(get: { pendulums.first?.trigger.pendulumPeriodBeats ?? 16 },
                                                               set: { value in updateAll { $0.trigger.pendulumPeriodBeats = value } }),
                        range: 1...64, step: 1, format: { NumberText.compact($0) + " Beats" })
            DemonSegmentedPicker(title: "Auslösen",
                                 selection: Binding(get: { pendulums.first?.trigger.pendulumBothDirections ?? true },
                                                    set: { value in updateAll { $0.trigger.pendulumBothDirections = value } }),
                                 options: [(value: true, title: "Beide Richtungen"), (value: false, title: "Eine Richtung")])
            DemonSlider(title: "Grundfrequenz", value: Binding(get: { pendulums.first?.pitch.baseFrequency ?? 330 },
                                                               set: { value in updateAll { $0.pitch.baseFrequency = value } }),
                        range: PitchControl.baseFrequencyRange, logarithmic: true, format: { NumberText.frequency($0) })
            NumberListField(title: "Noten der Pendel (Halbtöne, von oben nach unten)",
                            values: Binding(get: { pendulums.map { Double($0.pitch.formula) ?? 0 } }, set: setNotes),
                            maximumCount: SynthProject.maximumVoices, identifier: "pendulumNotes")
            DemonCaption("Die Note eines Pendels ist seine Tonhöhenformel (Halbtöne über der Grundfrequenz). Jede Stimme lässt sich unten auch einzeln bearbeiten.")
            Button {
                model.showGuide(topic: "topic-pendulum")
            } label: {
                Label("Pendel erklärt", systemImage: "book.fill")
            }
            .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
        }
        .demonCard()
    }

    private func updateAll(_ change: @escaping (inout SynthVoice) -> Void) {
        model.updateProject { project in
            for index in project.voices.indices where project.voices[index].trigger.kind == .pendulum {
                change(&project.voices[index])
            }
        }
    }

    private func setCount(_ count: Int) {
        model.updateProject { project in
            var current = project.voices.filter { $0.trigger.kind == .pendulum }
            while current.count > max(count, 1) {
                let removed = current.removeLast()
                project.voices.removeAll { $0.id == removed.id }
            }
            while current.count < count && project.voices.count < SynthProject.maximumVoices {
                var voice = current.last ?? Self.template
                voice.id = UUID()
                voice.isSolo = false
                voice.trigger.pendulumCycles = (current.map(\.trigger.pendulumCycles).max() ?? 5) + 1
                let index = current.count
                voice.name = "Pendel N = \(voice.trigger.pendulumCycles)"
                voice.color = SynthPresets.pendulumColors[index % SynthPresets.pendulumColors.count]
                let notes = SynthPresets.pendulumNotes
                let note = notes[index % notes.count] + 12 * Double(index / notes.count)
                voice.pitch.formula = FormulaNumber.literal(note)
                voice.pan = 0
                current.append(voice)
                project.voices.append(voice)
            }
        }
    }

    private func setFirstCycles(_ first: Int) {
        model.updateProject { project in
            var offset = 0
            for index in project.voices.indices where project.voices[index].trigger.kind == .pendulum {
                project.voices[index].trigger.pendulumCycles = first + offset
                project.voices[index].name = "Pendel N = \(first + offset)"
                offset += 1
            }
        }
    }

    private func setNotes(_ notes: [Double]) {
        model.updateProject { project in
            var position = 0
            for index in project.voices.indices where project.voices[index].trigger.kind == .pendulum {
                guard position < notes.count else { break }
                project.voices[index].pitch.formula = FormulaNumber.literal(notes[position])
                project.voices[index].pitch.unit = .semitones
                position += 1
            }
        }
    }

    private static var template: SynthVoice {
        var voice = SynthVoice(name: "Pendel", color: .green)
        voice.trigger.kind = .pendulum
        voice.trigger.pendulumCycles = 6
        voice.trigger.pendulumPeriodBeats = 16
        voice.pitch = PitchControl(formula: "0", unit: .semitones, baseFrequency: 330)
        voice.amplitude = AmplitudeControl(formula: "exp(-3*localTime)")
        voice.volumeDecibels = -9
        return voice
    }
}
