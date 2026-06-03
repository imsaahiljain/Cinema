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
    var criticallyAcclaimed: [MediaItem] = []
    var awardWinners: [MediaItem] = []
    var genreRows: [(id: Int, title: String, films: [MediaItem])] = []
    var platformRows: [(title: String, films: [MediaItem])] = []
    var watchlistFilms: [MediaItem] = []
    var recommendations: [MediaItem] = []
    var becauseYouWatched: (title: String, films: [MediaItem])?
    var isLoading = false

    private var likedGenreIDs: [Int] {
        UserDefaults.standard.string(forKey: "cinema_liked_genres")?
            .split(separator: ",").compactMap { Int($0) } ?? [18, 28, 878]
    }
    private var dislikedGenreIDs: [Int] {
        UserDefaults.standard.string(forKey: "cinema_disliked_genres")?
            .split(separator: ",").compactMap { Int($0) } ?? []
    }

    func load(currentUserID: UUID?) async {
        isLoading = top10.isEmpty
        top10 = (try? await TMDBClient.shared.trending(mediaType: "movie", englishOnly: true)) ?? []
        newReleases = (try? await TMDBClient.shared.nowPlaying()) ?? []
        isLoading = false

        // Social
        if let uid = currentUserID {
            await loadSocial(userID: uid)
        }

        // Editorial
        criticallyAcclaimed = (try? await TMDBClient.shared.criticallyAcclaimed()) ?? []
        awardWinners = (try? await TMDBClient.shared.awardWinners()) ?? []

        // Liked-genre rows (skip disliked)
        let liked = likedGenreIDs.filter { !dislikedGenreIDs.contains($0) }
        var rows: [(id: Int, title: String, films: [MediaItem])] = []
        for gid in liked {
            if let films = try? await TMDBClient.shared.discover(genreID: gid), !films.isEmpty {
                let name = MediaItem.genreMap[gid] ?? "Genre"
                rows.append((gid, "Trending in \(name)", films))
            }
        }
        genreRows = rows

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

        guard followingCount >= 20 else { return }
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
        // Watchlist
        struct WatchlistRow: Decodable {
            let tmdbID: Int; let mediaType: String
            enum CodingKeys: String, CodingKey { case tmdbID = "tmdb_id"; case mediaType = "media_type" }
        }
        if let rows: [WatchlistRow] = try? await SupabaseClient.shared
            .from("watchlist").select().eq("user_id", value: userID)
            .order("added_at", ascending: false).limit(20).execute().value {
            var wl: [MediaItem] = []
            for row in rows {
                let type = MediaType(rawValue: row.mediaType) ?? .movie
                if let m = try? await TMDBClient.shared.details(tmdbID: row.tmdbID, mediaType: type) { wl.append(m) }
            }
            watchlistFilms = wl
        }

        // Top-rated film → recommendations
        if let topItem: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items").select().eq("user_id", value: userID)
            .order("elo_score", ascending: false).limit(1).execute().value,
           let best = topItem.first {
            recommendations = (try? await TMDBClient.shared.recommendations(tmdbID: best.tmdbID, mediaType: best.mediaType)) ?? []

            // Most-recently added film → because you watched
            if let recentItems: [RankedItem] = try? await SupabaseClient.shared
                .from("ranked_items").select().eq("user_id", value: userID)
                .order("added_at", ascending: false).limit(1).execute().value,
               let recent = recentItems.first, recent.tmdbID != best.tmdbID,
               let recentMedia = try? await TMDBClient.shared.details(tmdbID: recent.tmdbID, mediaType: recent.mediaType) {
                let recs = (try? await TMDBClient.shared.recommendations(tmdbID: recent.tmdbID, mediaType: recent.mediaType)) ?? []
                if !recs.isEmpty { becauseYouWatched = (recentMedia.title, recs) }
            }
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
                            .padding(.top, 60)

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

                        // Because You Watched
                        if let byw = vm.becauseYouWatched, !byw.films.isEmpty {
                            MediaRow(title: "Because You Watched \(byw.title)", films: byw.films) { selectedFilm = $0 }
                        }

                        // Recommendations
                        if !vm.recommendations.isEmpty {
                            MediaRow(title: "Recommended for You", films: vm.recommendations) { selectedFilm = $0 }
                        }

                        // Critically Acclaimed
                        if !vm.criticallyAcclaimed.isEmpty {
                            MediaRow(title: "Critically Acclaimed", films: vm.criticallyAcclaimed) { selectedFilm = $0 }
                        }

                        // Award Winners
                        if !vm.awardWinners.isEmpty {
                            MediaRow(title: "Award Winners", films: vm.awardWinners) { selectedFilm = $0 }
                        }

                        // Genre rows
                        ForEach(Array(vm.genreRows.enumerated()), id: \.offset) { _, row in
                            MediaRow(title: row.title, films: row.films) { selectedFilm = $0 }
                        }

                        // Platform rows
                        ForEach(Array(vm.platformRows.enumerated()), id: \.offset) { _, row in
                            MediaRow(title: row.title, films: row.films) { selectedFilm = $0 }
                        }

                        // Watchlist
                        if !vm.watchlistFilms.isEmpty {
                            MediaRow(title: "Your Watchlist", films: vm.watchlistFilms) { selectedFilm = $0 }
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
        if vm.followingCount >= 20 {
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
    private let peek: CGFloat = 50   // left area where number shows

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Text("\(index + 1)")
                    .font(.system(size: 100, weight: .black).italic())
                    .foregroundStyle(CinemaTheme.Colors.background)
                    .stroke(color: Color.white.opacity(0.25), width: 2)
                    .offset(y: 8)

                PosterImage(path: film.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                    .frame(width: posterW, height: posterH)
                    .offset(x: peek)
            }
            .frame(width: peek + posterW, height: posterH + 8, alignment: .bottomLeading)
        }
        .buttonStyle(.plain)
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
                    Text("Follow \(20 - followingCount) more people to unlock")
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
