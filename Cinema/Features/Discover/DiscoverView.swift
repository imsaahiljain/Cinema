import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class DiscoverViewModel {
    var top10: [MediaItem] = []
    var newReleases: [MediaItem] = []
    var followingCount: Int = 0
    var friendActivity: [MediaItem] = []
    var highlyRated: [MediaItem] = []
    var platformRows: [(title: String, films: [MediaItem])] = []
    var recommendations: [MediaItem] = []
    var isLoading = false

    func load(currentUserID: UUID?) async {
        isLoading = top10.isEmpty
        top10 = (try? await TMDBClient.shared.trending(mediaType: "movie")) ?? []
        newReleases = (try? await TMDBClient.shared.nowPlaying()) ?? []
        isLoading = false

        // Social
        if let uid = currentUserID {
            await loadSocial(userID: uid)
        }

        // Editorial
        highlyRated = (try? await TMDBClient.shared.highlyRated()) ?? []

        // Platform rows
        let platforms: [(String, Int)] = [("On Netflix", 8), ("On Prime Video", 9), ("On Apple TV+", 350)]
        var pRows: [(title: String, films: [MediaItem])] = []
        for (name, pid) in platforms {
            if let films = try? await TMDBClient.shared.byPlatform(providerID: pid), !films.isEmpty {
                pRows.append((name, films))
            }
        }
        platformRows = pRows

        // Personal (needs user data)
        if let uid = currentUserID {
            await loadPersonal(userID: uid)
        }
    }

    private func loadSocial(userID: UUID) async {
        struct FollowEdge: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        let edges: [FollowEdge] = (try? await SupabaseClient.shared
            .from("follows").select("following_id").eq("follower_id", value: userID)
            .execute().value) ?? []
        followingCount = edges.count

        guard followingCount >= 10 else { return }
        let ids = edges.map(\.followingID)
        guard let recent: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items").select()
            .in("user_id", values: ids.map(\.uuidString))
            .order("updated_at", ascending: false).limit(20)
            .execute().value else { return }

        var seen = Set<Int>(); var items: [MediaItem] = []
        for item in recent {
            guard !seen.contains(item.tmdbID) else { continue }
            seen.insert(item.tmdbID)
            if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                items.append(media)
            }
            if items.count >= 10 { break }
        }
        friendActivity = items
    }

    private func loadPersonal(userID: UUID) async {
        // Top-rated film → recommendations
        if let topItem: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items").select().eq("user_id", value: userID)
            .order("elo_score", ascending: false).limit(1).execute().value,
           let best = topItem.first {
            recommendations = (try? await TMDBClient.shared.recommendations(tmdbID: best.tmdbID, mediaType: best.mediaType)) ?? []

        }
    }
}

// MARK: - DiscoverView

struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = DiscoverViewModel()
    @State private var selectedFilm: MediaItem?

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        Text("Discover")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            .padding(.horizontal, CinemaTheme.Spacing.lg)
                            .padding(.top, 16)

                        // Top 10
                        if !vm.top10.isEmpty {
                            top10Section
                        }

                        // New Releases
                        if !vm.newReleases.isEmpty {
                            MediaRow(title: "New Releases", films: vm.newReleases) { selectedFilm = $0 }
                        }

                        // Friends (gated at 20 following)
                        friendsSection

                        // Recommendations
                        if !vm.recommendations.isEmpty {
                            MediaRow(title: "Recommended for You", films: vm.recommendations) { selectedFilm = $0 }
                        }

                        // Highly Rated
                        if !vm.highlyRated.isEmpty {
                            MediaRow(title: "Highly Rated", films: vm.highlyRated) { selectedFilm = $0 }
                        }

                        // Platform rows
                        ForEach(Array(vm.platformRows.enumerated()), id: \.offset) { _, row in
                            MediaRow(title: row.title, films: row.films) { selectedFilm = $0 }
                        }

                        Spacer().frame(height: 80)
                    }
                }
                .refreshable { await vm.load(currentUserID: appState.currentUser?.id) }
            }
        }
        .task { await vm.load(currentUserID: appState.currentUser?.id) }
        .sheet(item: $selectedFilm) { film in
            MovieInfoView(film: film)
        }
    }

    // MARK: - Top 10

    private var top10Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 10 Right Now")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(vm.top10.prefix(10).enumerated()), id: \.element.id) { i, film in
                        Top10Card(index: i, film: film) { selectedFilm = film }
                    }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }
        }
    }

    // MARK: - Friends Section

    @ViewBuilder
    private var friendsSection: some View {
        if vm.followingCount >= 10 {
            if !vm.friendActivity.isEmpty {
                MediaRow(title: "Watched by Friends", films: vm.friendActivity) { selectedFilm = $0 }
            }
        } else if vm.followingCount > 0 || !vm.top10.isEmpty {
            // Show locked state only once data has loaded
            LockedFriendsPanel(followingCount: vm.followingCount)
        }
    }
}

// MARK: - Top 10 Card

private struct Top10Card: View {
    let index: Int
    let film: MediaItem
    let action: () -> Void

    private let posterW: CGFloat = 110
    private let posterH: CGFloat = 165

    // 1-9: number centered in 72pt frame, poster at x=44  (restored original)
    // 10:  "1" in 48pt + "0" in 48pt, poster at x=68 so "1" is 100% prominent
    //      and "0" peeks the same way single digits peek behind their poster
    private var posterX: CGFloat { index == 9 ? 84 : 44 }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if index == 9 {
                    HStack(spacing: 0) {
                        digit("1").frame(width: 48, alignment: .center)
                        digit("0").frame(width: 48, alignment: .center)
                    }
                    .offset(y: 12)
                } else {
                    digit("\(index + 1)")
                        .frame(width: 72, alignment: .center)
                        .offset(y: 12)
                }

                PosterImage(path: film.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                    .frame(width: posterW, height: posterH)
                    .offset(x: posterX)
            }
            .frame(width: posterX + posterW, height: posterH + 12, alignment: .bottomLeading)
        }
        .buttonStyle(.plain)
    }

    private func digit(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 96, weight: .black).italic())
            .foregroundStyle(CinemaTheme.Colors.surface)
            .overlay(
                Text(s)
                    .font(.system(size: 96, weight: .black).italic())
                    .stroke(color: CinemaTheme.Colors.textSecondary.opacity(0.5), width: 1)
            )
    }
}

// MARK: - Locked Friends Panel

private struct LockedFriendsPanel: View {
    let followingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watched by Friends")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            HStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Follow \(10 - followingCount) more people to unlock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    Text("See what your friends are watching and ranking.")
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(16)
            .background(CinemaTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
            .padding(.horizontal, CinemaTheme.Spacing.lg)
        }
    }
}

// MARK: - Media Row

private struct MediaRow: View {
    let title: String
    let films: [MediaItem]
    let onTap: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(films.prefix(20)) { film in
                        Button { onTap(film) } label: {
                            PosterImage(path: film.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                                .frame(width: 110, height: 165)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }
        }
    }
}

// MARK: - Stroke helper

private extension View {
    func stroke(color: Color, width: CGFloat) -> some View {
        ZStack {
            self.offset(x: -width).foregroundStyle(color)
            self.offset(x:  width).foregroundStyle(color)
            self.offset(y: -width).foregroundStyle(color)
            self.offset(y:  width).foregroundStyle(color)
            self
        }
    }
}
