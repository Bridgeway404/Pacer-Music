import SwiftUI
import PacerKit

/// Subtle beat visualization: a ring that breathes on every beat.
struct BeatPulseRing: View {
    let pulse: Int
    let isActive: Bool

    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(Theme.accent.opacity(isActive ? 0.55 : 0.15), lineWidth: 3)
            .scaleEffect(animate ? 1.0 : 0.88)
            .opacity(animate ? 0.25 : 0.9)
            .animation(.easeOut(duration: 0.5), value: animate)
            .onChange(of: pulse) {
                animate = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    animate = false
                }
            }
    }
}

/// The big cadence dial: current SPM inside a pulsing ring.
struct CadenceDial: View {
    let spm: Double?
    let pulse: Int
    let isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surfaceRaised, lineWidth: 3)
            BeatPulseRing(pulse: pulse, isActive: isRunning)
            VStack(spacing: 2) {
                Text(spm.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("SPM")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 230, height: 230)
        .animation(.snappy, value: spm != nil)
    }
}

/// Music sync status pill (matching / catching up / …).
struct SyncStatePill: View {
    let state: MusicSyncState

    private var color: Color {
        switch state {
        case .matching: Theme.accent
        case .catchingUp, .slowingDown: Theme.warn
        case .selecting: Theme.accentAlt
        case .waiting, .stopped: Theme.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(state.rawValue)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface, in: Capsule())
    }
}

/// Follow Me / Pace Me switcher with large touch targets.
struct ModeSwitcher: View {
    @Binding var mode: RunMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RunMode.allCases) { candidate in
                Button {
                    withAnimation(.snappy) { mode = candidate }
                } label: {
                    Text(candidate.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            mode == candidate ? Theme.surfaceRaised : .clear,
                            in: Capsule()
                        )
                        .foregroundStyle(mode == candidate ? Theme.textPrimary : Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
    }
}

/// Pace Me target adjuster: quick presets + fine stepper.
struct TargetAdjuster: View {
    @Binding var targetSpm: Int
    let presets = [150, 155, 160, 165, 170, 175, 180]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("TARGET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                HStack(spacing: 18) {
                    Button {
                        targetSpm = max(120, targetSpm - 1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.surfaceRaised, Theme.textPrimary)
                    }
                    Text("\(targetSpm)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 66)
                        .contentTransition(.numericText())
                    Button {
                        targetSpm = min(200, targetSpm + 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.surfaceRaised, Theme.textPrimary)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            withAnimation(.snappy) { targetSpm = preset }
                        } label: {
                            Text("\(preset)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    targetSpm == preset ? Theme.accent : Theme.surfaceRaised,
                                    in: Capsule()
                                )
                                .foregroundStyle(targetSpm == preset ? .black : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .pacerCard()
    }
}

/// Current track card with artwork, name, artist, live BPM readout.
struct NowPlayingCard: View {
    let track: PacerTrack?
    let tempoStatus: TempoEngineStatus
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(track?.name ?? "Nothing playing")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(track?.artist ?? "Press play to start")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let current = tempoStatus.currentBpm, isPlaying {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(current.rounded()))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentAlt)
                        .contentTransition(.numericText())
                    Text("BPM NOW")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if let bpm = track?.bpm {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(bpm.rounded()))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Text("BPM")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .pacerCard()
    }
}

struct ArtworkView: View {
    let track: PacerTrack?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = track?.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentAlt.opacity(0.7), Theme.accent.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "waveform")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Adaptive Up Next queue — visibly reorders as the target cadence moves.
struct UpNextList: View {
    let queue: [RankedTrack]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UP NEXT")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
            if queue.isEmpty {
                Text("Queue builds once cadence locks in")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(queue) { ranked in
                HStack(spacing: 10) {
                    ArtworkView(track: ranked.track, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ranked.track.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(ranked.track.artist)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let match = ranked.match {
                        Text(matchLabel(match))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(match.isGoodMatch ? Theme.accent : Theme.textTertiary)
                    } else {
                        Text("? BPM")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .pacerCard()
        .animation(.snappy, value: queue.map(\.id))
    }

    private func matchLabel(_ match: BpmMatch) -> String {
        let bpm = Int((match.perceivedBpm).rounded())
        if match.multiplier == 1 { return "\(bpm)" }
        if match.multiplier == 2 { return "\(bpm) ×2" }
        return "\(bpm) ×½"
    }
}

/// Developer diagnostics panel (hidden behind a toggle, never in the runner UI).
struct DiagnosticsPanel: View {
    let coordinator: RunCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DIAGNOSTICS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.warn)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                diagRow("source", coordinator.providerKind.rawValue)
                diagRow("engine", coordinator.engineState.rawValue)
                diagRow("raw", coordinator.rawSpm.map { String(format: "%.1f SPM", $0) } ?? "—")
                diagRow("smoothed", coordinator.smoothedSpm.map { String(format: "%.1f SPM", $0) } ?? "—")
                diagRow("engine target", coordinator.engineTargetSpm.map { "\($0) SPM" } ?? "—")
                diagRow("musical target", coordinator.musicalTargetSpm.map { "\($0) BPM" } ?? "—")
                diagRow("track BPM", trackBpmLabel)
                diagRow(
                    "multiplier",
                    coordinator.musicalTargetSpm.flatMap { target in
                        BpmMatcher.match(cadenceSpm: Double(target), trackBpm: coordinator.currentTrack?.bpm)
                            .map { String(format: "%.1fx", $0.multiplier) }
                    } ?? "—"
                )
                diagRow(
                    "playback",
                    String(
                        format: "%.0f BPM @ %.2fx",
                        coordinator.tempoStatus.currentBpm ?? 0,
                        coordinator.tempoStatus.playbackRate
                    )
                )
                if let pending = coordinator.pendingRetarget {
                    diagRow("pending", "\(pending.candidateSpm) SPM for \(String(format: "%.1f", pending.since))s")
                }
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)

            simulatorControls

            Divider().overlay(Theme.surfaceRaised)

            ForEach(coordinator.diagnostics.suffix(6).reversed()) { event in
                Text("\(event.at.formatted(date: .omitted, time: .standard))  \(event.text)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
        }
        .pacerCard()
    }

    private var trackBpmLabel: String {
        if let bpm = coordinator.currentTrack?.bpm {
            return String(format: "%.0f", bpm)
        }
        return "—"
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.textTertiary)
            Text(value)
        }
    }

    @ViewBuilder
    private var simulatorControls: some View {
        if coordinator.providerKind == .simulator {
            VStack(alignment: .leading, spacing: 6) {
                Text("SIMULATED RUNNER")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 8) {
                    ForEach([0, 150, 154, 162, 170, 180], id: \.self) { spm in
                        Button {
                            coordinator.simulatorProvider.targetSpm = Double(spm)
                        } label: {
                            Text(spm == 0 ? "Stop" : "\(spm)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.surfaceRaised, in: Capsule())
                                .foregroundStyle(spm == 0 ? Theme.warn : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
