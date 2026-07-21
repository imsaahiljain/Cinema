import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var results: [MediaItem] = []
    var trending: [MediaItem] = []
    var isSearching = false
    var addedIDs: Set<Int> = []
    var watchlistIDs: Set<Int> = []
    var selectedGenreID: Int? = nil
    var genreResults: [MediaItem] = []
    var isBrowsingGenre = false

    let quickGenres: [(id: Int, name: String)] = [
        (28, "Action"), (18, "Drama"), (35, "Comedy"), (53, "Thriller"),
        (878, "Sci-Fi"), (27, "Horror"), (10749, "Romance"), (16, "Animation"),
        (80, "Crime"), (99, "Documentary")
    ]

    var isQueryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Genre chip filtering applied on top of typed search results (TMDB's search endpoints don't
    /// accept a genre param, so this filters the already-fetched `results` client-side rather than
    /// re-querying — `genreResults`/`browseGenre` remain the idle-browse path, driven by `discover`).
    var displayedResults: [MediaItem] {
        guard let id = selectedGenreID, let name = quickGenres.first(where: { $0.id == id })?.name else { return results }
        return results.filter { $0.genreNames.contains(name) }
    }

    private var searchTask: Task<Void, Never>?

    func onQueryChange() {
        searchTask?.cancel()
        guard !isQueryEmpty else { results = []; return }
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
        results = (try? await TMDBClient.shared.search(query: q)) ?? []
        isSearching = false
    }

    func browseGenre(id: Int) async {
        if selectedGenreID == id { selectedGenreID = nil; genreResults = []; return }
        selectedGenreID = id
        isBrowsingGenre = true
        genreResults = (try? await TMDBClient.shared.discover(genreID: id)) ?? []
        isBrowsingGenre = false
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

}

// MARK: - SearchView

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = SearchViewModel()
    @FocusState private var searchFocused: Bool
    @State private var selectedFilm: MediaItem?
    @State private var showRanking = false
    @State private var addToListItem: MediaItem?

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
                    genreChips
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    Divider().background(CinemaTheme.Colors.border)
                    filmResults
                }
            }
        }
        .task {
            await vm.loadTrending()
            await vm.loadUserLists(userID: appState.currentUser?.id)
        }
        .sheet(item: $selectedFilm) { MovieInfoView(film: $0) }
        .fullScreenCover(isPresented: $showRanking) { RankingView() }
        .sheet(item: $addToListItem, onDismiss: {
            Task { await vm.loadUserLists(userID: appState.currentUser?.id) }
        }) { item in
            AddToListSheet(tmdbID: item.id, mediaType: item.mediaType, title: item.title, posterPath: item.posterPath, userID: appState.currentUser?.id)
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

            TextField(SearchConfig.includeTVShows ? "Search films, shows..." : "Search films...", text: $vm.query)
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
                    vm.selectedGenreID = nil
                    vm.genreResults = []
                    searchFocused = false
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
        if vm.displayedResults.isEmpty {
            let genreLabel = vm.selectedGenreID.flatMap { id in vm.quickGenres.first { $0.id == id }?.name }
            let message = genreLabel.map { "No \($0) results for \"\(vm.query)\"" } ?? "No results for \"\(vm.query)\""
            emptyState(icon: "film", message: message)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.displayedResults) { item in
                        FilmResultRow(
                            item: item,
                            isAdded: vm.addedIDs.contains(item.id),
                            isWatchlisted: vm.watchlistIDs.contains(item.id),
                            onTap: { selectedFilm = item },
                            onAdd: {
                                Task {
                                    // Tapping an already-ranked item re-opens the battle screen instead of
                                    // being a dead end — closing RankingView with the X before ever battling
                                    // (e.g. only 1 item ranked so far) used to strand it as "added" with no
                                    // way back in, since isAdded already being true skipped showRanking.
                                    if !vm.addedIDs.contains(item.id) {
                                        await vm.addToRanked(item: item, userID: appState.currentUser?.id)
                                    }
                                    if vm.addedIDs.count >= 2 { showRanking = true }
                                }
                            },
                            onOpenListPicker: { addToListItem = item }
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
    let onOpenListPicker: () -> Void

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

                    metadataLine
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                HStack(spacing: 14) {
                    Button(action: onOpenListPicker) {
                        Image(systemName: isWatchlisted ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17))
                            .foregroundStyle(
                                isWatchlisted ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textSecondary
                            )
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Add to List")
                    .accessibilityAddTraits(isWatchlisted ? .isSelected : [])

                    Button(action: onAdd) {
                        if isAdded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.green)
                        } else {
                            Text("VS")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(CinemaTheme.Colors.gold)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(CinemaTheme.Colors.gold, lineWidth: 1.5))
                        }
                    }
                    .accessibilityLabel(isAdded ? "Ranked" : "Rank This or That")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Single truncating Text (not a row of separate Text/Image views) so a squeezed row
    /// ellipsizes cleanly instead of wrapping mid-word — an HStack of independent Text
    /// elements has no shared truncation and can break a word like "Animation" across lines.
    private var metadataLine: Text {
        var segments: [Text] = []
        if let year = item.releaseYear {
            segments.append(Text(year).foregroundStyle(CinemaTheme.Colors.textSecondary))
        }
        segments.append(Text(item.mediaType == .movie ? "Film" : "TV").foregroundStyle(CinemaTheme.Colors.textSecondary))
        if let genre = item.genreNames.first {
            segments.append(Text(genre).foregroundStyle(CinemaTheme.Colors.textSecondary))
        }
        if let rating = item.voteAverage, rating > 0 {
            let star = Text(Image(systemName: "star.fill")).foregroundStyle(CinemaTheme.Colors.gold)
            let value = Text(" " + String(format: "%.1f", rating)).foregroundStyle(CinemaTheme.Colors.textSecondary)
            segments.append(star + value)
        }
        let dot = Text(" · ").foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.4))
        return segments.dropFirst().reduce(segments.first ?? Text("")) { $0 + dot + $1 }
    }
}

