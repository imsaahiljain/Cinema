import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var results: [MediaItem] = []
    var hiddenGems: [MediaItem] = []
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

    // Was trending() — the exact call Discover's Top 10 row already makes, so Search's idle
    // browse just re-showed whatever Discover already showed. hiddenGems() is TMDBClient's own
    // axis: solid reviews that never crossed into Discover's "highlyRated" mainstream floor.
    // Movie-only for now, matching SearchConfig.includeTVShows being off app-wide.
    func loadHiddenGems() async {
        guard hiddenGems.isEmpty else { return }
        do {
            hiddenGems = try await TMDBClient.shared.hiddenGems()
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
        guard let id = vm.selectedGenreID else { return "Hidden Gems" }
        return vm.quickGenres.first { $0.id == id }?.name ?? "Hidden Gems"
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
            await vm.loadHiddenGems()
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
                .autocorrectionDisabled()
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
                    posterGrid(vm.selectedGenreID != nil ? vm.genreResults : vm.hiddenGems)
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
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible()),
                    ],
                    spacing: 18
                ) {
                    ForEach(vm.displayedResults) { item in
                        SearchGridTile(
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
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
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

/// Poster-forward grid tile (replaces the old full-width list row): searching is a
/// confirm-and-select task, not a browse task — you already know the title, so recognizing
/// the poster matters more than reading a paragraph of metadata. Actions live behind a single
/// visible affordance (the "..." dots) with a long-press-the-title shortcut on top of it —
/// nothing in this app should require a hidden gesture with no discoverable equivalent.
private struct SearchGridTile: View {
    let item: MediaItem
    let isAdded: Bool
    let isWatchlisted: Bool
    let onTap: () -> Void
    let onAdd: () -> Void
    let onOpenListPicker: () -> Void

    @State private var showActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onTap) {
                ZStack(alignment: .top) {
                    // Gesture lives on the poster image specifically (not the whole button) —
                    // a nested Button (the "..." dots) sits in the same label, and composing
                    // simultaneousGesture on the outer Button wasn't triggering reliably with
                    // that nested button present.
                    // .fill, not .fit — PosterImage already fills whatever frame it's given
                    // internally; .fit on top of that let the box shrink and center within the
                    // column instead of filling it edge to edge, which is why the poster (and
                    // the checkmark badge anchored to its bounds) looked inset from the title.
                    PosterImage(path: item.posterPath, cornerRadius: 10)
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .clipped()
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4).onEnded { _ in showActions = true }
                        )

                    VStack {
                        HStack {
                            if isWatchlisted { statusBadge(icon: "bookmark.fill", tint: CinemaTheme.Colors.gold) }
                            Spacer()
                            // Always-visible tap target for actions, with long-press on the poster
                            // itself as a shortcut into the same menu — never gesture-only.
                            Button { showActions = true } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.black.opacity(0.45), in: Circle())
                            }
                            .accessibilityLabel("Quick Actions")
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            if isAdded { statusBadge(icon: "checkmark", tint: .green) }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("searchGridTile.poster.\(item.id)")

            // Title sizes to however many lines it actually needs (1 or 2) — most titles are
            // one line, so forcing a fixed two-line reservation left a permanent dead gap under
            // the common case just to align the uncommon one. A mixed row can have slightly
            // uneven caption heights and that's fine; a fixed-height hack across every screen
            // size is not.
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(2)

                // Year dropped entirely — outside a handful of brand-new releases, it did
                // nothing to help identify a movie. "New" / "Coming Soon" are the only date
                // info actually worth surfacing here, so they're the only things left in
                // this slot — nothing shown for anything already out and not brand new.
                if item.isRecentRelease {
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                        .kerning(0.5)
                } else if item.isUpcoming {
                    Text("COMING SOON")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .kerning(0.3)
                }
            }
        }
        .popover(isPresented: $showActions) {
            actionsMenu
                .presentationCompactAdaptation(.popover)
        }
    }

    private func statusBadge(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
    }

    private var actionsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showActions = false
                onOpenListPicker()
            } label: {
                Label("Add to List", systemImage: "bookmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider().background(CinemaTheme.Colors.border)

            Button {
                showActions = false
                onAdd()
            } label: {
                Label(isAdded ? "Re-Rank" : "Rank This or That", systemImage: "circle.grid.cross")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 230)
        .background(CinemaTheme.Colors.surface)
    }
}

