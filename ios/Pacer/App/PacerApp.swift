import SwiftUI

@main
struct PacerApp: App {
    @State private var coordinator = RunCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(SupabaseService.shared)
        }
    }
}

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            RunView()
                .tabItem { Label("Run", systemImage: "figure.run") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.xyaxis.line") }
            AuthView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
