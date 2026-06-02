import SwiftUI
import Supabase

@Observable
@MainActor
final class AppState {
    var currentUser: CinemaUser?
    var isAuthenticated = false
    var hasCompletedOnboarding = false
    var showingOnboarding = false
    var isCheckingSession = true   // true until first session check resolves

    init() {
        Log.app.info("AppState init — starting session check")
        Task { await checkSession() }
    }

    func checkSession() async {
        Log.app.info("checkSession: started")
        defer {
            isCheckingSession = false
            Log.app.info("checkSession: done — isAuthenticated=\(self.isAuthenticated) onboarded=\(self.hasCompletedOnboarding)")
        }
        do {
            let session = try await SupabaseClient.shared.auth.session
            Log.app.info("checkSession: session found for \(session.user.id)")
            isAuthenticated = true
            await loadUser(id: session.user.id)
        } catch {
            Log.app.info("checkSession: no active session — \(error.localizedDescription)")
            isAuthenticated = false
        }
    }

    private func loadUser(id: UUID) async {
        Log.app.info("loadUser: fetching profile for \(id)")
        do {
            let user: CinemaUser = try await SupabaseClient.shared
                .from("users")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            currentUser = user
            hasCompletedOnboarding = user.onboarded
            Log.app.info("loadUser: loaded \(user.username) onboarded=\(user.onboarded)")
        } catch {
            Log.app.error("loadUser: failed — \(error.localizedDescription)")
            isAuthenticated = false
        }
    }

    func markOnboardingComplete() async {
        guard let id = currentUser?.id else { return }
        Log.app.info("markOnboardingComplete: user=\(id)")
        do {
            try await SupabaseClient.shared
                .from("users")
                .update(["onboarded": true])
                .eq("id", value: id)
                .execute()
            hasCompletedOnboarding = true
            showingOnboarding = false
            Log.app.info("markOnboardingComplete: success")
        } catch {
            Log.app.error("markOnboardingComplete: failed — \(error.localizedDescription)")
        }
    }

    func signOut() async {
        Log.app.info("signOut: signing out \(self.currentUser?.username ?? "unknown")")
        try? await SupabaseClient.shared.auth.signOut()
        currentUser = nil
        isAuthenticated = false
        hasCompletedOnboarding = false
        showingOnboarding = false
    }
}
