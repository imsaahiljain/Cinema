import SwiftUI
import Supabase

@Observable
final class AppState {
    var currentUser: CinemaUser?
    var isAuthenticated = false
    var hasCompletedOnboarding = false

    init() {
        Task { await checkSession() }
    }

    func checkSession() async {
        do {
            let session = try await SupabaseClient.shared.auth.session
            isAuthenticated = true
            await loadUser(id: session.user.id)
        } catch {
            isAuthenticated = false
        }
    }

    private func loadUser(id: UUID) async {
        do {
            let user: CinemaUser = try await SupabaseClient.shared.database
                .from("users")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            currentUser = user
            hasCompletedOnboarding = user.onboarded
        } catch {
            isAuthenticated = false
        }
    }

    func signOut() async {
        try? await SupabaseClient.shared.auth.signOut()
        currentUser = nil
        isAuthenticated = false
        hasCompletedOnboarding = false
    }
}
