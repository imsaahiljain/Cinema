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

    private var searchTask: Task<Void, Never>?

    func onQueryChange() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
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
        do {
            results = try await TMDBClient.shared.search(query: q)
        } catch {}
        isSearching = false
    }

    func loadTrending() async {
        guard trending.isEmpty else { return }
        do { trending = try await TMDBClient.shared.trending() } catch {}
    }

    func loadUserLists(userID: UUID?) async {
        guard let userID else { return }
        do {
            let ranked: [RankedItem] = try await SupabaseClient.shared.database
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value
            addedIDs = Set(ranked.map { $0.tmdbID })
        } catch {}
    }

    func addToRanked(item: MediaItem, userID: UUID?) async {
        guard let userID else { return }
        let startingElo = 1500.0
        do {
            try await SupabaseClient.shared.database
                .from("ranked_items")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(item.id),
                    "media_type": item.mediaType.rawValue,
                    "elo_score": String(startingElo),
                ])
                .execute()
            addedIDs.insert(item.id)
        } catch {}
    }

    func addToWatchlist(item: MediaItem, userID: UUID?) async {
        guard let userID else { return }
        do {
            try await SupabaseClient.shared.database
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
}

// MARK: - SearchView

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = SearchViewModel()
    @FocusState private var searchFocused: Bool

    var displayItems: [MediaItem] {
        vm.query.trimmingCharacters(in: .whitespaces).isEmpty ? vm.trending : vm.results
    }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    TextField("Search movies...", text: $vm.query)
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        .tint(CinemaTheme.Colors.gold)
                        .focused($searchFocused)
                        .onChange(of: vm.query) { _, _ in vm.onQueryChange() }
                    if !vm.query.isEmpty {
                        Button { vm.query = ""; vm.results = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        }
                    }
                }
                .padding(14)
                .background(CinemaTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.top, 60)
                .padding(.bottom, 16)

                if vm.isSearching {
                    Spacer()
                    ProgressView().tint(CinemaTheme.Colors.gold)
                    Spacer()
                } else if displayItems.isEmpty && !vm.query.isEmpty {
                    Spacer()
                    Text("No results for \"\(vm.query)\"")
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    Spacer()
                } else {
                    // Section header
                    HStack {
                        Text(vm.query.isEmpty ? "Trending" : "Results")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.bottom, 8)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayItems) { item in
                                SearchResultRow(
                                    item: item,
                                    isAdded: vm.addedIDs.contains(item.id),
                                    isWatchlisted: vm.watchlistIDs.contains(item.id),
                                    onAdd: { Task { await vm.addToRanked(item: item, userID: appState.currentUser?.id) } },
                                    onWatchlist: { Task { await vm.addToWatchlist(item: item, userID: appState.currentUser?.id) } }
                                )
                                Divider().background(CinemaTheme.Colors.border).padding(.leading, 76)
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .task {
            await vm.loadTrending()
            await vm.loadUserLists(userID: appState.currentUser?.id)
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let item: MediaItem
    let isAdded: Bool
    let isWatchlisted: Bool
    let onAdd: () -> Void
    let onWatchlist: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(path: item.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                .frame(width: 44, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let year = item.releaseYear {
                        Text(year).font(.system(size: 13)).foregroundStyle(CinemaTheme.Colors.textSecondary)
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
                // Watchlist bookmark
                Button(action: onWatchlist) {
                    Image(systemName: isWatchlisted ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundStyle(isWatchlisted ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textSecondary)
                }

                // Add to ranked
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
}
