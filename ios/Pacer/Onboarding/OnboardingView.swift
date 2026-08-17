import SwiftUI
import PacerKit

/// Three-screen onboarding: concept → music source → run mode.
struct OnboardingView: View {
    @Environment(RunCoordinator.self) private var coordinator
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var page = 0
    @State private var appleMusicError: String?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            TabView(selection: $page) {
                conceptPage.tag(0)
                musicPage.tag(1)
                modePage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }

    private var conceptPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.run")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Run to your rhythm.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Pacer turns your music into a running DJ that responds to your pace.")
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            nextButton("Get Started") { withAnimation { page = 1 } }
                .padding(.bottom, 60)
        }
    }

    private var musicPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Choose music.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            sourceCard(
                icon: "waveform.badge.magnifyingglass",
                title: "Demo Mode",
                subtitle: "Built-in beats that actually speed up and slow down with you. No account needed.",
                selected: coordinator.musicSource == .demo
            ) {
                coordinator.musicSource = .demo
            }

            sourceCard(
                icon: "music.note",
                title: "Apple Music",
                subtitle: "Your playlists, cadence-aware track picks. Requires a subscription.",
                selected: coordinator.musicSource == .appleMusic
            ) {
                coordinator.musicSource = .appleMusic
                Task {
                    do {
                        try await coordinator.activeMusicProvider.authorize()
                        appleMusicError = nil
                    } catch {
                        appleMusicError = error.localizedDescription
                    }
                }
            }

            if let appleMusicError {
                Text(appleMusicError)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 24)
            }

            Text("Spotify is coming as a secondary source.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            nextButton("Next") { withAnimation { page = 2 } }
                .padding(.bottom, 60)
        }
        .padding(.horizontal, 20)
    }

    private var modePage: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("How should Pacer run?")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            sourceCard(
                icon: "arrow.triangle.merge",
                title: "Follow Me",
                subtitle: "Music follows your natural cadence.",
                selected: coordinator.mode == .followMe
            ) {
                coordinator.mode = .followMe
            }

            sourceCard(
                icon: "metronome.fill",
                title: "Pace Me",
                subtitle: "Choose a cadence and let the music lead you.",
                selected: coordinator.mode == .paceMe
            ) {
                coordinator.mode = .paceMe
            }

            Spacer()
            nextButton("Start Running") {
                hasOnboarded = true
            }
            .padding(.bottom, 60)
        }
        .padding(.horizontal, 20)
    }

    private func sourceCard(
        icon: String, title: String, subtitle: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
            }
            .padding(16)
            .background(
                selected ? Theme.surfaceRaised : Theme.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func nextButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}
