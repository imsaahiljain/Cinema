import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            // showingOnboarding MUST be checked first — keeps the user inside the
            // current OnboardingView even after isAuthenticated becomes true mid-flow.
            if appState.showingOnboarding {
                OnboardingView(startAtMovieWall: false)
            } else if appState.isAuthenticated && appState.hasCompletedOnboarding {
                MainTabView()
            } else if appState.isAuthenticated && !appState.hasCompletedOnboarding {
                OnboardingView(startAtMovieWall: true)
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.35), value: appState.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.35), value: appState.showingOnboarding)
    }
}
