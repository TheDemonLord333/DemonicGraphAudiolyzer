import SwiftUI

/// "Graph abspielen", pause/resume, stop, repeat and the state line.
struct TransportControls: View {
    @Environment(AudiolyzerModel.self) private var model
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            if compact {
                HStack(spacing: 10) {
                    playButton
                    secondaryButtons
                }
            } else {
                playButton
                HStack(spacing: 12) {
                    secondaryButtons
                }
            }
            statusLine
        }
    }

    private var isPreparing: Bool { model.phase == .preparing }

    private var canPlay: Bool {
        switch model.phase {
        case .invalidFormula, .preparing, .exporting: return false
        default: return model.parsedFormula != nil
        }
    }

    private var playButton: some View {
        Button {
            model.play()
        } label: {
            HStack(spacing: 10) {
                if isPreparing {
                    ProgressView()
                        .tint(DemonTheme.neonGreen)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.black))
                        .foregroundStyle(DemonTheme.neonGreen)
                        .shadow(color: DemonTheme.neonGreen.opacity(0.9), radius: 6)
                }
                Text(isPreparing ? "Wird vorbereitet …" : (compact ? "Abspielen" : "Graph abspielen"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(DemonPrimaryButtonStyle())
        .disabled(!canPlay)
        .accessibilityLabel("Graph abspielen")
        .accessibilityHint(model.phase == .playing ? "Startet den Durchlauf von vorne" : "Spielt den Graphen als Klang ab")
        .accessibilityIdentifier("playButton")
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        let isPaused = model.phase == .paused
        Button {
            model.togglePause()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isPaused ? "playpause.fill" : "pause.fill")
                if !compact {
                    Text(isPaused ? "Fortsetzen" : "Pause")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .buttonStyle(DemonRuneButtonStyle(isActive: isPaused))
        .disabled(!(model.phase == .playing || isPaused))
        .accessibilityLabel(isPaused ? "Fortsetzen" : "Pausieren")
        .accessibilityIdentifier("pauseButton")

        Button {
            model.stop()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "stop.fill")
                if !compact {
                    Text("Stopp")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .buttonStyle(DemonRuneButtonStyle())
        .disabled(!model.phase.isActive)
        .accessibilityLabel("Stopp")
        .accessibilityHint("Beendet die Wiedergabe und springt an den Anfang")
        .accessibilityIdentifier("stopButton")

        Button {
            model.isLooping.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "repeat")
                if !compact {
                    Text("Wiederholen")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .buttonStyle(DemonRuneButtonStyle(isActive: model.isLooping))
        .accessibilityLabel("Wiederholung")
        .accessibilityValue(model.isLooping ? "ein" : "aus")
        .accessibilityAddTraits(model.isLooping ? .isSelected : [])
        .accessibilityIdentifier("loopButton")
    }

    private var statusLine: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                DiamondShape()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
                Text(model.phase.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(statusColor)
                if model.isLooping {
                    Text("· Wiederholung an")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DemonTheme.textTertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(model.phase.title)")
            .accessibilityIdentifier("transportStatus")

            if let message = model.lastError, case .failed = model.phase {
                HStack(alignment: .top, spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(DemonTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("OK") { model.dismissError() }
                        .buttonStyle(DemonChipButtonStyle())
                }
            } else if let issue = model.settingsIssue {
                Text(issue)
                    .font(.footnote)
                    .foregroundStyle(DemonTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .playing: return DemonTheme.green
        case .paused, .preparing, .exporting: return DemonTheme.blurpleText
        case .invalidFormula, .failed: return DemonTheme.danger
        case .ready: return DemonTheme.textSecondary
        }
    }
}
