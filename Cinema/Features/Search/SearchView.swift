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
    var selectedGenreID: Int? = nil
    var genreResults: [MediaItem] = []
    var isBrowsingGenre = false

    let quickGenres: [(id: Int, name: String)] = [
        (28, "Action"), (18, "Drama"), (35, "Comedy"), (53, "Thriller"),
        (878, "Sci-Fi"), (27, "Horror"), (10749, "Romance"), (16, "Animation"),
        (80, "Crime"), (99, "Documentary")
    ]

    var isQueryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchTask: Task<Void, Never>?

    func onQueryChange() {
        searchTask?.cancel()
        selectedGenreID = nil
        genreResults = []
        guard !isQueryEmpty else { results = []; peopleResults = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
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

    func browseGenre(id: Int) async {
        if selectedGenreID == id { selectedGenreID = nil; genreResults = []; return }
        selectedGenreID = id
        isBrowsingGenre = true
        genreResults = (try? await TMDBClient.shared.discover(genreID: id)) ?? []
        isBrowsingGenre = false
    }

    private func searchPeople(_ q: String) async -> [CinemaUser] {
        (try? await SupabaseClient.shared
            .from("users").select()
            .ilike("username", pattern: "%\(q.lowercased())%")
            .limit(20).execute().value) ?? []
    }

    func loadTrending() async {
        guard trending.isEmpty else { return }
        do {
            trending = try await TMDBClient.shared.trending(mediaType: SearchConfig.includeTVShows ? "all" : "movie")
        } catch {}
    }

    func loadUserLists(userID: UUID?) async {
        guard let userID else { return }
        do {
            let ranked: [RankedItem] = try await SupabaseClient.shared
                .from("ranked_items").select().eq("user_id", value: userID).execute().value
            addedIDs = Set(ranked.map { $0.tmdbID })
        } catch {}
        do {
            struct WL: Decodable {
                let tmdbID: Int
                enum CodingKeys: String, CodingKey { case tmdbID = "tmdb_id" }
            }
            let wl: [WL] = try await SupabaseClient.shared
                .from("watchlist").select("tmdb_id").eq("user_id", value: userID).execute().value
            watchlistIDs = Set(wl.map { $0.tmdbID })
        } catch {}
        do {
            struct FE: Decodable {
                let followingID: UUID
                enum CodingKeys: String, CodingKey { case followingID = "following_id" }
            }
            let edges: [FE] = try await SupabaseClient.shared
                .from("follows").select("following_id").eq("follower_id", value: userID).execute().value
            followedIDs = Set(edges.map { $0.followingID })
        } catch {}
    }

    func addToRanked(item: MediaItem, userID: UUID?) async {
        guard let userID else { return }
        do {
            try await SupabaseClient.shared.from("ranked_items")
                .upsert(["user_id": userID.uuidString, "tmdb_id": String(item.id),
                         "media_type": item.mediaType.rawValue, "elo_score": String(1500.0)])
                .execute()
            addedIDs.insert(item.id)
        } catch {}
    }

    func addToWatchlist(item: MediaItem, userID: UUID?) async {
        guard let userID else { return }
        do {
            try await SupabaseClient.shared.from("watchlist")
                .upsert(["user_id": userID.uuidString, "tmdb_id": String(item.id),
                         "media_type": item.mediaType.rawValue])
                .execute()
            watchlistIDs.insert(item.id)
        } catch {}
    }

    func toggleFollow(user: CinemaUser, currentUserID: UUID?) async {
        guard let currentUserID else { return }
        if followedIDs.contains(user.id) {
            do {
                try await SupabaseClient.shared.from("follows").delete()
                    .eq("follower_id", value: currentUserID.uuidString)
                    .eq("following_id", value: user.id.uuidString).execute()
                followedIDs.remove(user.id)
            } catch {}
        } else {
            do {
                try await SupabaseClient.shared.from("follows")
                    .upsert(["follower_id": currentUserID.uuidString, "following_id": user.id.uuidString])
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
    @State private var showRanking = false

    private var sectionTitle: String {
        guard let id = vm.selectedGenreID else { return "Trending" }
        return vm.quickGenres.first { $0.id == id }?.name ?? "Trending"
    }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                if vm.isSearching {
                    Spacer()
                    ProgressView().tint(CinemaTheme.Colors.gold)
                    Spacer()
                } else if vm.isQueryEmpty {
                    idleContent
                } else {
                    segmentControl
                    Divider().background(CinemaTheme.Colors.border)
                    if vm.segment == .films { filmResults }
                    else { peopleResults }
                }
            }
        }
        .task {
            await vm.loadTrending()
            await vm.loadUserLists(userID: appState.currentUser?.id)
        }
        .sheet(item: $selectedFilm) { MovieInfoView(film: $0) }
        .fullScreenCover(isPresented: $showRanking) { RankingView() }
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    searchFocused || !vm.query.isEmpty
                        ? CinemaTheme.Colors.textPrimary
                        : CinemaTheme.Colors.textSecondary
                )
                .animation(.easeInOut(duration: 0.15), value: searchFocused)

            TextField(SearchConfig.includeTVShows ? "Films, shows, people..." : "Films, people...", text: $vm.query)
                .font(.system(size: 16))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .tint(CinemaTheme.Colors.gold)
                .focused($searchFocused)
                .onChange(of: vm.query) { _, _ in vm.onQueryChange() }
                .submitLabel(.search)

            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.results = []
                    vm.peopleResults = []
                    vm.selectedGenreID = nil
                    vm.genreResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    searchFocused
                        ? CinemaTheme.Colors.gold.opacity(0.5)
                        : CinemaTheme.Colors.border,
                    lineWidth: 1
                )
                .animation(.easeInOut(duration: 0.2), value: searchFocused)
        )
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            segmentTab(SearchConfig.includeTVShows ? "Films & TV" : "Films", isSelected: vm.segment == .films) { vm.segment = .films }
            segmentTab("People",     isSelected: vm.segment == .people) { vm.segment = .people }
        }
        .padding(.horizontal, 20)
    }

    private func segmentTab(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? CinemaTheme.Colors.textPrimary : CinemaTheme.Colors.textSecondary
                    )
                    .padding(.top, 4)
                Rectangle()
                    .fill(isSelected ? CinemaTheme.Colors.gold : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.2), value: isSelected)
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                genreChips
                    .padding(.bottom, 28)

                HStack {
                    Text(sectionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .kerning(0.8)
                        .animation(.easeInOut(duration: 0.2), value: sectionTitle)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                if vm.isBrowsingGenre {
                    HStack {
                        Spacer()
                        ProgressView().tint(CinemaTheme.Colors.gold)
                        Spacer()
                    }
                    .padding(.vertical, 60)
                } else {
                    posterGrid(vm.selectedGenreID != nil ? vm.genreResults : vm.trending)
                }

                Spacer().frame(height: 100)
            }
            .padding(.top, 4)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Genre Chips

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.quickGenres, id: \.id) { genre in
                    let selected = vm.selectedGenreID == genre.id
                    Button {
                        Task { await vm.browseGenre(id: genre.id) }
                    } label: {
                        Text(genre.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? .black : CinemaTheme.Colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(selected ? CinemaTheme.Colors.gold : CinemaTheme.Colors.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    selected ? CinemaTheme.Colors.gold : CinemaTheme.Colors.border,
                                    lineWidth: 1
                                )
                            )
                    }
                    .animation(.spring(duration: 0.2), value: selected)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Poster Grid (edge-to-edge)

    private func posterGrid(_ items: [MediaItem]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
            ],
            spacing: 2
        ) {
            ForEach(items.prefix(18)) { film in
                Button { selectedFilm = film } label: {
                    PosterImage(path: film.posterPath, cornerRadius: 0)
                        .aspectRatio(2/3, contentMode: .fit)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Film Results

    @ViewBuilder
    private var filmResults: some View {
        if vm.results.isEmpty {
            emptyState(icon: "film", message: "No results for \"\(vm.query)\"")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.results) { item in
                        FilmResultRow(
                            item: item,
                            isAdded: vm.addedIDs.contains(item.id),
                            isWatchlisted: vm.watchlistIDs.contains(item.id),
                            onTap: { selectedFilm = item },
                            onAdd: {
                                Task {
                                    let alreadyAdded = vm.addedIDs.contains(item.id)
                                    await vm.addToRanked(item: item, userID: appState.currentUser?.id)
                                    if !alreadyAdded && vm.addedIDs.count >= 2 { showRanking = true }
                                }
                            },
                            onWatchlist: { Task { await vm.addToWatchlist(item: item, userID: appState.currentUser?.id) } }
                        )
                        Divider()
                            .background(CinemaTheme.Colors.border)
                            .padding(.leading, 90)
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - People Results

    @ViewBuilder
    private var peopleResults: some View {
        if vm.peopleResults.isEmpty {
            emptyState(icon: "person", message: "No one found for \"\(vm.query)\"")
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
                            .padding(.leading, 78)
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.35))
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - Film Result Row

private struct FilmResultRow: View {
    let item: MediaItem
    let isAdded: Bool
    let isWatchlisted: Bool
    let onTap: () -> Void
    let onAdd: () -> Void
    let onWatchlist: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                PosterImage(path: item.posterPath, cornerRadius: 8)
                    .frame(width: 56, height: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        if let year = item.releaseYear {
                            Text(year)
                                .font(.system(size: 13))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            Text("·")
                                .font(.system(size: 13))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.4))
                        }
                        Text(item.mediaType == .movie ? "Film" : "TV")
                            .font(.system(size: 13))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        if let genre = item.genreNames.first {
                            Text("·")
                                .font(.system(size: 13))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.4))
                            Text(genre)
                                .font(.system(size: 13))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 14) {
                    Button(action: onWatchlist) {
                        Image(systemName: isWatchlisted ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17))
                            .foregroundStyle(
                                isWatchlisted ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textSecondary
                            )
                    }
                    Button(action: onAdd) {
                        Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 26))
                            .foregroundStyle(isAdded ? Color.green : CinemaTheme.Colors.gold)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
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
                        .frame(width: 46, height: 46)
                        .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                    Text((user.displayName ?? user.username).prefix(1).uppercased())
                        .font(.system(size: 19, weight: .bold))
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
