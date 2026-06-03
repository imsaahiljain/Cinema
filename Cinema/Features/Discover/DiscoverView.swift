import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class DiscoverViewModel {
    var trending: [MediaItem] = []
    var newReleases: [MediaItem] = []
    var friendActivity: [MediaItem] = []
    var genreRows: [(title: String, films: [MediaItem])] = []
    var isLoading = false

    func load(currentUserID: UUID?) async {
        isLoading = trending.isEmpty
        defer { isLoading = false }

        trending = (try? await TMDBClient.shared.trending(mediaType: "movie", timeWindow: "week")) ?? []
        newReleases = (try? await TMDBClient.shared.nowPlaying()) ?? []

        var rows: [(title: String, films: [MediaItem])] = []
        if let d = try? await TMDBClient.shared.discover(genreID: 18), !d.isEmpty {
            rows.append(("Trending in Drama", d))
        }
        if let a = try? await TMDBClient.shared.discover(genreID: 28), !a.isEmpty {
            rows.append(("Trending in Action", a))
        }
        if let s = try? await TMDBClient.shared.discover(genreID: 878), !s.isEmpty {
            rows.append(("Trending in Sci-Fi", s))
        }
        genreRows = rows

        if let uid = currentUserID {
            friendActivity = await loadFriendActivity(userID: uid)
        }
    }

    private func loadFriendActivity(userID: UUID) async -> [MediaItem] {
        struct FollowEdge: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        guard let edges: [FollowEdge] = try? await SupabaseClient.shared
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userID)
            .execute()
            .value, !edges.isEmpty else { return [] }

        let ids = edges.map(\.followingID)
        guard let recent: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items")
            .select()
            .in("user_id", values: ids.map(\.uuidString))
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value else { return [] }

        var seen = Set<Int>()
        var items: [MediaItem] = []
        for item in recent {
            guard !seen.contains(item.tmdbID) else { continue }
            seen.insert(item.tmdbID)
            if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                items.append(media)
            }
            if items.count >= 10 { break }
        }
        return items
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

                        if !vm.trending.isEmpty {
                            top10Row
                        }

                        if !vm.newReleases.isEmpty {
                            MediaRow(title: "New Releases", films: vm.newReleases) { selectedFilm = $0 }
                        }

                        if !vm.friendActivity.isEmpty {
                            MediaRow(title: "Watched by Friends", films: vm.friendActivity) { selectedFilm = $0 }
                        }

                        ForEach(Array(vm.genreRows.enumerated()), id: \.offset) { _, row in
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

    // MARK: - Top 10 Row

    private var top10Row: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 10 Right Now")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(vm.trending.prefix(10).enumerated()), id: \.element.id) { i, film in
                        Top10Card(index: i, film: film) { selectedFilm = film }
                    }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }
        }
    }
}

// MARK: - Top 10 Card

private struct Top10Card: View {
    let index: Int
    let film: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Big number — rendered behind the poster
                Text("\(index + 1)")
                    .font(.system(size: 96, weight: .black))
                    .italic()
                    .foregroundStyle(CinemaTheme.Colors.surface)
                    .overlay(
                        Text("\(index + 1)")
                            .font(.system(size: 96, weight: .black))
                            .italic()
                            .stroke(color: CinemaTheme.Colors.textSecondary.opacity(0.5), width: 1)
                    )
                    .frame(width: 72, alignment: .center)
                    .offset(y: 12)

                // Poster — overlapping number on the left
                PosterImage(path: film.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                    .frame(width: 110, height: 165)
                    .offset(x: 44)
            }
            .frame(width: 154, height: 177, alignment: .bottomLeading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standard Media Row

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

// MARK: - Text stroke helper

private extension View {
    func stroke(color: Color, width: CGFloat) -> some View {
        ZStack {
            self.offset(x: -width, y: 0).foregroundStyle(color)
            self.offset(x: width, y: 0).foregroundStyle(color)
            self.offset(x: 0, y: -width).foregroundStyle(color)
            self.offset(x: 0, y: width).foregroundStyle(color)
            self
        }
    }
}
