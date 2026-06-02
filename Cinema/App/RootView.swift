import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Always fill the window — prevents any black flash during transitions
            CinemaTheme.Colors.background.ignoresSafeArea()

            if appState.isCheckingSession {
                SplashView()
            } else if appState.showingOnboarding {
                // Must be checked before isAuthenticated — keeps user inside
                // the current OnboardingView even after auth becomes true mid-flow.
                OnboardingView(startAtMovieWall: false)
                    .transition(.opacity)
            } else if appState.isAuthenticated && appState.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else if appState.isAuthenticated && !appState.hasCompletedOnboarding {
                OnboardingView(startAtMovieWall: true)
                    .transition(.opacity)
            } else {
                AuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isCheckingSession)
        .animation(.easeInOut(duration: 0.3), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: appState.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: appState.showingOnboarding)
        .onAppear {
            Log.app.info("RootView appeared — isCheckingSession=\(appState.isCheckingSession)")
        }
    }
}

// MARK: - Splash

private struct SplashView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Cinema")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                ProgressView()
                    .tint(CinemaTheme.Colors.gold)
                    .scaleEffect(0.8)
            }
        }
        .onAppear { Log.app.info("SplashView shown — waiting for session check") }
    }
}
