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
            #if DEBUG
            await debugAutoSignIn()
            #else
            isAuthenticated = false
            #endif
        }
    }

    #if DEBUG
    // Skips the login/onboarding wall during development so a fresh install
    // doesn't require re-authenticating every time — compiled out entirely
    // in Release, so this never reaches a real build.
    private func debugAutoSignIn() async {
        do {
            try await SupabaseClient.shared.auth.signIn(email: Secrets.qaEmail, password: Secrets.qaPassword)
            let session = try await SupabaseClient.shared.auth.session
            isAuthenticated = true
            await loadUser(id: session.user.id)
            Log.app.info("checkSession: DEBUG auto-signed into QA account")
        } catch {
            Log.app.error("checkSession: DEBUG auto sign-in failed — \(error.localizedDescription)")
            isAuthenticated = false
        }
    }
    #endif

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

    /// Permanently deletes the current user's account. Cascades through every table via
    /// foreign keys (ranked_items, elo_matches, follows, feed_events, watchlist, custom_lists,
    /// list_items, film_notes) down from `auth.users` — see the `delete_own_account` Postgres
    /// function (SECURITY DEFINER, runs as `delete from auth.users where id = auth.uid()`).
    /// Returns false on failure so the caller can show an error instead of assuming success.
    func deleteAccount() async -> Bool {
        guard let userID = currentUser?.id else { return false }
        Log.app.info("deleteAccount: deleting \(userID)")
        // Best-effort — an orphaned avatar file isn't worth failing the whole deletion over.
        try? await SupabaseClient.shared.storage.from("avatars").remove(paths: ["\(userID.uuidString)/avatar.jpg"])
        do {
            try await SupabaseClient.shared.rpc("delete_own_account").execute()
        } catch {
            Log.app.error("deleteAccount: RPC failed — \(error.localizedDescription)")
            return false
        }
        try? await SupabaseClient.shared.auth.signOut()
        currentUser = nil
        isAuthenticated = false
        hasCompletedOnboarding = false
        showingOnboarding = false
        Log.app.info("deleteAccount: success")
        return true
    }
}
