import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class AuthViewModel {
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?

    func signIn(appState: AppState) async {
        guard !email.isEmpty, !password.isEmpty else { return }
        Log.auth.info("signIn: attempting for \(self.email)")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await SupabaseClient.shared.auth.signIn(email: email, password: password)
            Log.auth.info("signIn: success")
            await appState.checkSession()
        } catch {
            Log.auth.error("signIn: failed — \(error.localizedDescription)")
            errorMessage = "Couldn't sign in. Check your email and password."
        }
    }
}

// MARK: - AuthView (Feature Tour)

struct AuthView: View {
    @Environment(AppState.self) private var appState
    @State private var showLogin = false
    @State private var page = 0

    private let features: [(icon: String, title: String, subtitle: String)] = [
        ("list.number",         "Rank",     "Your taste, finally in order"),
        ("sparkles",            "Discover", "Find your next obsession"),
        ("checkmark.circle",    "Track",    "Every film you've ever seen"),
    ]

    var body: some View {
        GeometryReader { geo in
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Small wordmark
                Text("Popcorn")
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, geo.safeAreaInsets.top + 24)

                Spacer()

                // Feature slides — height scales with screen, capped so it never dominates
                TabView(selection: $page) {
                    ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                        FeatureSlide(icon: f.icon, title: f.title, subtitle: f.subtitle)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: min(geo.size.height * 0.40, 340))

                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == page ? 20 : 6, height: 6)
                            .animation(.spring(duration: 0.35), value: page)
                    }
                }
                .padding(.top, 36)

                Spacer()

                // CTAs
                VStack(spacing: 14) {
                    Button {
                        appState.showingOnboarding = true
                    } label: {
                        Text("Create Account")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(CinemaTheme.Colors.gold)
                            .clipShape(Capsule())
                    }

                    Button { showLogin = true } label: {
                        Text("Already have an account? Log in")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(geo.safeAreaInsets.bottom + 16, 52))
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showLogin) {
            LoginView().environment(appState)
        }
        } // GeometryReader
    }
}

// MARK: - Feature Slide (no card, direct on black)

private struct FeatureSlide: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.85))

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
}

// MARK: - LoginView

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm = AuthViewModel()
    @State private var showPassword = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(CinemaTheme.Colors.surface)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 20)

                OnboardingHeader(title: "Welcome back.", subtitle: "Sign in to your Cinema account")
                    .padding(.top, 40)

                VStack(spacing: 32) {
                    OnboardingTextField("Email", text: $vm.email, keyboardType: .emailAddress)
                        .focused($focus, equals: .email)

                    ZStack(alignment: .trailing) {
                        if showPassword {
                            OnboardingTextField("Password", text: $vm.password)
                                .focused($focus, equals: .password)
                        } else {
                            OnboardingSecureField("Password", text: $vm.password)
                                .focused($focus, equals: .password)
                        }
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                .padding(.bottom, 12)
                        }
                    }
                }
                .padding(.top, 40)

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(.top, 16)
                }

                Spacer()

                CinemaButton("Sign In", isLoading: vm.isLoading, enabled: !vm.email.isEmpty && !vm.password.isEmpty) {
                    Task { await vm.signIn(appState: appState) }
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
        }
        .onAppear { focus = .email }
    }
}
