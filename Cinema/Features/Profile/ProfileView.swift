import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class ProfileViewModel {
    var rankedItems: [RankedItem] = []
    var topFilms: [MediaItem] = []
    var isLoading = false
    var totalBattles = 0

    func load(userID: UUID?) async {
        guard let userID else { return }
        isLoading = topFilms.isEmpty
        do {
            let items: [RankedItem] = try await SupabaseClient.shared
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .order("elo_score", ascending: false)
                .limit(9)
                .execute()
                .value
            rankedItems = items

            var loaded: [MediaItem] = []
            for item in items {
                if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                    loaded.append(media)
                }
            }
            topFilms = loaded

            let matches: [[String: String]] = try await SupabaseClient.shared
                .from("elo_matches")
                .select("id")
                .eq("user_id", value: userID)
                .execute()
                .value
            totalBattles = matches.count
        } catch {}
        isLoading = false
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ProfileViewModel()
    @State private var showShareCard = false

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        profileHeader
                        statsBar
                        topNineGrid
                        tasteDNA
                        Spacer().frame(height: 100)
                    }
                }
                .refreshable { await vm.load(userID: appState.currentUser?.id) }
            }
        }
        .task { await vm.load(userID: appState.currentUser?.id) }
        .sheet(isPresented: $showShareCard) {
            ShareCardView(films: vm.topFilms, user: appState.currentUser)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(CinemaTheme.Colors.surface)
                .frame(width: 80, height: 80)
                .overlay(
                    Text(appState.currentUser?.displayName?.prefix(1).uppercased() ?? "?")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                )
                .padding(.top, 60)

            // Name + username
            VStack(spacing: 4) {
                Text(appState.currentUser?.displayName ?? appState.currentUser?.username ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Text("@\(appState.currentUser?.username ?? "")")
                    .font(.system(size: 15))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private var statsBar: some View {
        HStack(spacing: 0) {
            StatCell(value: "\(vm.rankedItems.count < 9 ? vm.rankedItems.count : vm.rankedItems.count)", label: "Ranked")
            Divider().frame(height: 36).background(CinemaTheme.Colors.border)
            StatCell(value: "\(vm.totalBattles)", label: "Battles")
            Divider().frame(height: 36).background(CinemaTheme.Colors.border)
            StatCell(value: vm.topFilms.first?.title ?? "—", label: "Top Film", small: true)
        }
        .padding(.vertical, 16)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg)
                .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1)
        )
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.bottom, 28)
    }

    private var topNineGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Films")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Spacer()
                Button {
                    showShareCard = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Share")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)

            if vm.topFilms.isEmpty {
                Text("Rank 9 films to unlock your top grid")
                    .font(.system(size: 14))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)],
                    spacing: 3
                ) {
                    ForEach(Array(vm.topFilms.prefix(9).enumerated()), id: \.element.id) { i, film in
                        ZStack(alignment: .topLeading) {
                            PosterImage(path: film.posterPath, cornerRadius: 0)
                                .aspectRatio(2/3, contentMode: .fit)

                            if i == 0 {
                                Text("#1")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(CinemaTheme.Colors.gold)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(6)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }
        }
        .padding(.bottom, 32)
    }

    private var tasteDNA: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Taste DNA")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            if vm.rankedItems.count < 5 {
                Text("Rank more films to unlock your taste profile")
                    .font(.system(size: 14))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
            } else {
                VStack(spacing: 10) {
                    TasteDNARow(label: "Films Ranked", value: "\(vm.rankedItems.count)")
                    TasteDNARow(label: "Battles Fought", value: "\(vm.totalBattles)")
                    if let top = vm.topFilms.first {
                        TasteDNARow(label: "Current #1", value: top.title)
                    }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }

            // Sign out
            Button {
                Task { await appState.signOut() }
            } label: {
                Text("Sign Out")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .padding(.top, 8)
        }
    }
}

// MARK: - Supporting Views

private struct StatCell: View {
    let value: String
    let label: String
    var small: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: small ? 13 : 22, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TasteDNARow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(16)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
    }
}

// MARK: - Share Card

struct ShareCardView: View {
    let films: [MediaItem]
    let user: CinemaUser?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

                // The shareable card
                ShareCard(films: films, user: user)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)

                CinemaButton("Share to Instagram Stories") {
                    // Generate UIImage from card and share
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)

                Spacer()
            }
        }
    }
}

struct ShareCard: View {
    let films: [MediaItem]
    let user: CinemaUser?

    var body: some View {
        VStack(spacing: 0) {
            // 3x3 grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                spacing: 2
            ) {
                ForEach(Array(films.prefix(9).enumerated()), id: \.element.id) { _, film in
                    PosterImage(path: film.posterPath, cornerRadius: 0)
                        .aspectRatio(2/3, contentMode: .fit)
                }
                // Fill empty slots
                ForEach(films.count..<9, id: \.self) { _ in
                    CinemaTheme.Colors.surface.aspectRatio(2/3, contentMode: .fit)
                }
            }

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(user?.username ?? "")")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    if let top = films.first {
                        Text("#1 \(top.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaTheme.Colors.gold)
                    }
                }
                Spacer()
                Text("Cinema")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }
            .padding(16)
            .background(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg))
    }
}
