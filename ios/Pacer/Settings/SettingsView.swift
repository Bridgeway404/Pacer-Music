import SwiftUI
import PacerKit

/// Cadence source, music source, and developer options.
struct SettingsView: View {
    @Environment(RunCoordinator.self) private var coordinator
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    @AppStorage("hasOnboarded") private var hasOnboarded = true

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                List {
                    Section("Cadence source") {
                        Picker("Source", selection: $coordinator.providerKind) {
                            ForEach(CadenceProviderKind.allCases) { kind in
                                Text(label(for: kind)).tag(kind)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        if coordinator.providerKind == .coreMotion, !CoreMotionCadenceProvider.isAvailable {
                            Label(
                                "This device/Simulator does not report cadence — use the Simulator source for demos.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.warn)
                        }
                    }
                    .listRowBackground(Theme.surface)

                    Section("Music source") {
                        Picker("Music", selection: $coordinator.musicSource) {
                            ForEach(MusicSourceKind.allCases) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        ForEach(coordinator.activeMusicProvider.capabilities.limitations, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .listRowBackground(Theme.surface)

                    Section("Developer") {
                        Toggle("Diagnostics panel", isOn: $showDiagnostics)
                        Button("Replay onboarding") { hasOnboarded = false }
                            .foregroundStyle(Theme.accentAlt)
                    }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
        .preferredColorScheme(.dark)
    }

    private func label(for kind: CadenceProviderKind) -> String {
        switch kind {
        case .coreMotion: "iPhone Motion (Core Motion)"
        case .simulator: "Simulator (demo runner)"
        case .tap: "Manual Tap"
        }
    }
}
