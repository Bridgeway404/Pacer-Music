import SwiftUI
import PacerKit

/// Unified run history: cloud sessions (when signed in) + local sessions.
struct HistoryView: View {
    @Environment(SupabaseService.self) private var supabase
    @State private var cloudSessions: [SupabaseService.RunSessionRow] = []
    @State private var localSessions: [LocalRunRecord] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                List {
                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.warn)
                            .listRowBackground(Theme.surface)
                    }
                    if !cloudSessions.isEmpty {
                        Section("Cloud") {
                            ForEach(cloudSessions) { session in
                                row(
                                    startedAt: session.startedAt,
                                    endedAt: session.endedAt,
                                    mode: session.mode,
                                    avg: session.averageCadence,
                                    peak: session.peakCadence,
                                    onBeat: session.onBeatPercent,
                                    playlist: session.playlistName
                                )
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                    if !localSessions.isEmpty {
                        Section(supabase.isSignedIn ? "On this iPhone" : "Runs") {
                            ForEach(localSessions) { session in
                                row(
                                    startedAt: session.startedAt,
                                    endedAt: session.endedAt,
                                    mode: session.mode,
                                    avg: session.averageCadence,
                                    peak: session.peakCadence,
                                    onBeat: session.onBeatPercent,
                                    playlist: session.playlistName
                                )
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                    if cloudSessions.isEmpty, localSessions.isEmpty, !isLoading {
                        ContentUnavailableView(
                            "No runs yet",
                            systemImage: "figure.run",
                            description: Text("Finish your first run and it will show up here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("History")
            .task { await reload() }
            .refreshable { await reload() }
        }
        .preferredColorScheme(.dark)
    }

    private func row(
        startedAt: Date, endedAt: Date?, mode: String,
        avg: Double?, peak: Double?, onBeat: Double?, playlist: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(RunMode(rawValue: mode)?.displayName ?? mode)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 14) {
                if let endedAt {
                    let mins = Int(endedAt.timeIntervalSince(startedAt)) / 60
                    let secs = Int(endedAt.timeIntervalSince(startedAt)) % 60
                    metric("\(mins):\(String(format: "%02d", secs))", "time")
                }
                if let avg { metric("\(Int(avg.rounded()))", "avg spm") }
                if let peak { metric("\(Int(peak.rounded()))", "peak") }
                if let onBeat { metric("\(Int(onBeat.rounded()))%", "on beat") }
            }
            if let playlist {
                Text(playlist)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func reload() async {
        isLoading = true
        loadError = nil
        localSessions = LocalSessionStore.loadAll()
        if supabase.isSignedIn {
            do {
                cloudSessions = try await supabase.fetchSessions()
            } catch {
                loadError = "Could not load cloud history: \(error.localizedDescription)"
            }
        } else {
            cloudSessions = []
        }
        isLoading = false
    }
}
