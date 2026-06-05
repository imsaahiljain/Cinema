import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class SearchViewModel {
    enum Segment { case films, people }

    var query = ""
    var segment: Segment = .films
    var results: [MediaItem] = []
    var peopleResults: [CinemaUser] = []
    var trending: [MediaItem] = []
    var isSearching = false
    var addedIDs: Set<Int> = []
    var watchlistIDs: Set<Int> = []
    var followedIDs: Set<UUID> = []

    private var searchTask: Task<Void, Never>?

    func onQueryChange() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            peopleResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        async let films = TMDBClient.shared.search(query: q)
        async let people = searchPeople(q)
        results = (try? await films) ?? []
        peopleResults = await people
        isSearching = false
    }

    private func searchPeople(_ q: String) async -> [CinemaUser] {
        (try? await SupabaseClient.shared
            .from("users")
            .select()
            .ilike("username", pattern: "%\(q.lowercased())%")
            .limit(20)
            .execute()
            .value) ?? []
    }

    func loadTrending() async {
        guard trending.isEmpty else { return }
        do { trending = try await TMDBClient.shared.trending() } catch {}
    }

    func loadUserLists(userID: UUID?) async {
        guard let userID else { return }

        do {
            let ranked: [RankedItem] = try await SupabaseClient.shared
                .from("ranked_items").select()
                .eq("user_id", value: userID)
                .execute().value
            addedIDs = Set(ranked.map { $0.tmdbID })
        } catch {}

        do {
            struct WatchlistRow: Decodable {
                let tmdbID: Int
                enum CodingKeys: String, CodingKey { case tmdbID = "tmdb_id" }
            }
            let wl: [WatchlistRow] = try await SupabaseClient.shared
                .from("watchlist").select("tmdb_id")
                .eq("user_id", value: userID)
                .execute().value
            watchlistIDs = Set(wl.map { $0.tmdbID })
        } catch {}

        do {
            struct FollowEdge: Decodable {
                let followingID: UUID
                enum CodingKeys: String, CodingKey { case followingID = "following_id" }
            }
            let edges: [FollowEdge] = try await SupabaseClient.shared
                .from("follows").select("following_id")
                .eq("follower_id", value: userID)
                .execute().value
            followedIDs = Set(edges.map { $0.followingID })
        } catch {}
    }

    func addToRanked(item: MediaItem, userID: UUID?) async {
        guard let userID else { return }
        do {
            try await SupabaseClient.shared
                .from("ranked_items")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(item.id),
                    "media_type": item.mediaType.rawValue,
                    "elo_score": String(1500.0),
                ])
                .execute()
            addedIDs.insert(item.id)
        } catch {}
    }

    func addToWatchlist(item: MediaItem, userID: UUID?) async {
        guard let userID else { return }
        do {
            try await SupabaseClient.shared
                .from("watchlist")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(item.id),
                    "media_type": item.mediaType.rawValue,
                ])
                .execute()
            watchlistIDs.insert(item.id)
        } catch {}
    }

    func toggleFollow(user: CinemaUser, currentUserID: UUID?) async {
        guard let currentUserID else { return }
        if followedIDs.contains(user.id) {
            do {
                try await SupabaseClient.shared
                    .from("follows")
                    .delete()
                    .eq("follower_id", value: currentUserID.uuidString)
                    .eq("following_id", value: user.id.uuidString)
                    .execute()
                followedIDs.remove(user.id)
            } catch {}
        } else {
            do {
                try await SupabaseClient.shared
                    .from("follows")
                    .upsert([
                        "follower_id": currentUserID.uuidString,
                        "following_id": user.id.uuidString,
                    ])
                    .execute()
                followedIDs.insert(user.id)
            } catch {}
        }
    }
}

// MARK: - SearchView

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = SearchViewModel()
    @FocusState private var searchFocused: Bool
    @State private var selectedFilm: MediaItem?
    @State private var selectedUser: CinemaUser?

    private var isQueryEmpty: Bool {
        vm.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.top, 60)
                    .padding(.bottom, 12)

                if !isQueryEmpty {
                    segmentControl
                        .padding(.bottom, 2)
                }

                if vm.isSearching {
                    Spacer()
                    ProgressView().tint(CinemaTheme.Colors.gold)
                    Spacer()
                } else if isQueryEmpty {
                    trendingGrid
                } else if vm.segment == .films {
                    filmResults
                } else {
                    peopleResults
                }
            }
        }
        .task {
            await vm.loadTrending()
            await vm.loadUserLists(userID: appState.currentUser?.id)
        }
        .sheet(item: $selectedFilm) { film in
            MovieInfoView(film: film)
        }
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileView(user: user)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedUser = nil }
                                .foregroundStyle(CinemaTheme.Colors.gold)
                        }
                    }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            TextField("Films, shows, people...", text: $vm.query)
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .tint(CinemaTheme.Colors.gold)
                .focused($searchFocused)
                .onChange(of: vm.query) { _, _ in vm.onQueryChange() }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.results = []
                    vm.peopleResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            segmentTab("Films & TV", isSelected: vm.segment == .films) { vm.segment = .films }
            segmentTab("People", isSelected: vm.segment == .people) { vm.segment = .people }
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
    }

    private func segmentTab(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? CinemaTheme.Colors.textPrimary : CinemaTheme.Colors.textSecondary)
                Rectangle()
                    .fill(isSelected ? CinemaTheme.Colors.gold : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.2), value: isSelected)
    }

    // MARK: - Trending Grid (idle state)

    private var trendingGrid: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trending")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.top, 4)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 3),
                        GridItem(.flexible(), spacing: 3),
                        GridItem(.flexible(), spacing: 3),
                    ],
                    spacing: 3
                ) {
                    ForEach(vm.trending.prefix(18)) { film in
                        Button { selectedFilm = film } label: {
                            PosterImage(path: film.posterPath, cornerRadius: 0)
                                .aspectRatio(2/3, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                .padding(.horizontal, CinemaTheme.Spacing.lg)

                Spacer().frame(height: 80)
            }
        }
    }

    // MARK: - Film Results

    @ViewBuilder
    private var filmResults: some View {
        if vm.results.isEmpty {
            Spacer()
            Text("No results for \"\(vm.query)\"")
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Spacer()
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.results) { item in
                        SearchResultRow(
                            item: item,
                            isAdded: vm.addedIDs.contains(item.id),
                            isWatchlisted: vm.watchlistIDs.contains(item.id),
                            onTap: { selectedFilm = item },
                            onAdd: { Task { await vm.addToRanked(item: item, userID: appState.currentUser?.id) } },
                            onWatchlist: { Task { await vm.addToWatchlist(item: item, userID: appState.currentUser?.id) } }
                        )
                        Divider()
                            .background(CinemaTheme.Colors.border)
                            .padding(.leading, 76)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - People Results

    @ViewBuilder
    private var peopleResults: some View {
        if vm.peopleResults.isEmpty {
            Spacer()
            Text("No people found for \"\(vm.query)\"")
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Spacer()
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.peopleResults) { user in
                        PeopleResultRow(
                            user: user,
                            isFollowing: vm.followedIDs.contains(user.id),
                            isCurrentUser: user.id == appState.currentUser?.id,
                            onTap: { selectedUser = user },
                            onFollow: { Task { await vm.toggleFollow(user: user, currentUserID: appState.currentUser?.id) } }
                        )
                        Divider()
                            .background(CinemaTheme.Colors.border)
                            .padding(.leading, 72)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let item: MediaItem
    let isAdded: Bool
    let isWatchlisted: Bool
    let onTap: () -> Void
    let onAdd: () -> Void
    let onWatchlist: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                PosterImage(path: item.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                    .frame(width: 44, height: 66)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if let year = item.releaseYear {
                            Text(year)
                                .font(.system(size: 13))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        }
                        Text(item.mediaType == .movie ? "Film" : "TV")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(CinemaTheme.Colors.surface)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: onWatchlist) {
                        Image(systemName: isWatchlisted ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18))
                            .foregroundStyle(isWatchlisted ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textSecondary)
                    }
                    Button(action: onAdd) {
                        Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(isAdded ? .green : CinemaTheme.Colors.gold)
                    }
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - People Result Row

private struct PeopleResultRow: View {
    let user: CinemaUser
    let isFollowing: Bool
    let isCurrentUser: Bool
    let onTap: () -> Void
    let onFollow: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CinemaTheme.Colors.surface)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                    Text(user.displayName?.prefix(1).uppercased()
                         ?? user.username.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName ?? user.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }

                Spacer()

                if !isCurrentUser {
                    Button(action: onFollow) {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isFollowing ? CinemaTheme.Colors.textSecondary : .black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isFollowing ? CinemaTheme.Colors.surface : CinemaTheme.Colors.gold)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    isFollowing ? CinemaTheme.Colors.border : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
