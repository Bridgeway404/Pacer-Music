import SwiftUI
import PacerKit

/// The flagship Pacer screen: glanceable while running, dark, huge numbers.
struct RunView: View {
    @Environment(RunCoordinator.self) private var coordinator
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    @State private var showSummary = false

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    CadenceDial(
                        spm: coordinator.smoothedSpm,
                        pulse: coordinator.beatPulse,
                        isRunning: coordinator.runState == .running
                    )
                    .padding(.top, 4)

                    targetReadout

                    ModeSwitcher(mode: $coordinator.mode)

                    if coordinator.mode == .paceMe {
                        TargetAdjuster(targetSpm: $coordinator.paceTargetSpm)
                        if let gap = coordinator.paceGapSpm, gap != 0 {
                            Text(gap > 0 ? "+\(gap) SPM to target" : "\(gap) SPM over target")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(abs(gap) <= 4 ? Theme.accent : Theme.warn)
                                .contentTransition(.numericText())
                        }
                    }

                    NowPlayingCard(
                        track: coordinator.currentTrack,
                        tempoStatus: coordinator.tempoStatus,
                        isPlaying: coordinator.isMusicPlaying
                    )

                    musicControls

                    if coordinator.providerKind == .tap, coordinator.runState == .running {
                        tapPad
                    }

                    UpNextList(queue: coordinator.upNext)

                    if showDiagnostics {
                        DiagnosticsPanel(coordinator: coordinator)
                    }

                    if let error = coordinator.lastError {
                        Text(error)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pacerCard()
                    }

                    startStopControls
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSummary) {
            if let summary = coordinator.lastSummary {
                SessionSummaryView(summary: summary)
                    .presentationDetents([.large])
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PACER")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(Theme.accent)
                Text(elapsedString)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }
            Spacer()
            SyncStatePill(state: coordinator.syncState)
        }
        .padding(.top, 8)
    }

    private var targetReadout: some View {
        HStack(spacing: 28) {
            StatNumeral(
                value: coordinator.musicalTargetSpm.map(String.init) ?? "—",
                unit: "MUSIC TARGET",
                color: Theme.accentAlt,
                size: 40
            )
            if coordinator.mode == .followMe {
                StatNumeral(
                    value: pendingLabel,
                    unit: "ENGINE",
                    color: Theme.textSecondary,
                    size: 40
                )
            }
        }
    }

    private var pendingLabel: String {
        if let pending = coordinator.pendingRetarget {
            return "→\(pending.candidateSpm)"
        }
        switch coordinator.engineState {
        case .idle: return "idle"
        case .acquiring: return "..."
        case .locked: return "lock"
        case .stopped: return "stop"
        }
    }

    private var musicControls: some View {
        HStack(spacing: 14) {
            Button {
                Task { await coordinator.togglePlayback() }
            } label: {
                Image(systemName: coordinator.isMusicPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 68, height: 68)
                    .background(Theme.surfaceRaised, in: Circle())
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                Task { await coordinator.skip() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 68, height: 68)
                    .background(Theme.surface, in: Circle())
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var tapPad: some View {
        Button {
            coordinator.tapProvider.registerTap()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 30, weight: .bold))
                Text("TAP EACH STEP")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: coordinator.rawSpm)
    }

    private var startStopControls: some View {
        HStack(spacing: 12) {
            switch coordinator.runState {
            case .idle, .ended:
                Button {
                    Task {
                        await coordinator.startRun()
                    }
                } label: {
                    Label("Start Run", systemImage: "figure.run")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            case .running, .paused:
                Button {
                    Task { await coordinator.togglePause() }
                } label: {
                    Label(
                        coordinator.runState == .paused ? "Resume" : "Pause",
                        systemImage: coordinator.runState == .paused ? "play.fill" : "pause.fill"
                    )
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await coordinator.endRun()
                        showSummary = coordinator.lastSummary != nil
                    }
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(Theme.warn, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var elapsedString: String {
        let total = Int(coordinator.elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
