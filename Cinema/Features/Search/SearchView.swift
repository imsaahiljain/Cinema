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

}

// MARK: - SearchView

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = SearchViewModel()
    @FocusState private var searchFocused: Bool
    @State private var selectedFilm: MediaItem?

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
        }
        .sheet(item: $selectedFilm) { MovieInfoView(film: $0) }
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

    /// Idle browse only shows a bounded, curated 18 (six full rows, no dangling partial row).
    private func posterGrid(_ items: [MediaItem]) -> some View {
        posterGridContent(Array(items.prefix(18)))
    }

    /// Shared by idle browse and typed search results — same edge-to-edge, caption-less,
    /// action-less poster tile in both places. Typed results used to be a heavier card (title,
    /// tags, a "..." quick-actions menu); those actions are moving to the movie detail screen
    /// instead, so results go back to being exactly what idle browse already looked like: a
    /// poster you tap to confirm, nothing else.
    private func posterGridContent(_ items: [MediaItem]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
            ],
            spacing: 2
        ) {
            ForEach(items) { film in
                Button { selectedFilm = film } label: {
                    // .fill + .clipped, not .fit — PosterImage already fills whatever frame
                    // it's given internally; .fit on top of that shrinks/letterboxes the image
                    // inside its box instead of filling it edge to edge.
                    PosterImage(path: film.posterPath, cornerRadius: 0)
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("searchGridTile.poster.\(film.id)")
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
                posterGridContent(vm.displayedResults)
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
