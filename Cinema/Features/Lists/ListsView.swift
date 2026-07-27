import SwiftUI
import Supabase

// MARK: - ListsView — "Rankings": Watched / Watchlist / user-created lists
//
// Built from the "Popcorn Rankings" design handoff (warm cream + brick-red
// accent, same design language as FeedMarqueeView — see WarmTheme.swift).
// No big title/subtitle per feedback — the tab switcher carries context on
// its own, matching how Beli's "Your Lists" screen leans on plain tabs
// rather than a headline (see Docs/beli-design-notes.md).
//
// Watched, Watchlist, and custom lists are all real Supabase data
// (ranked_items / watchlist / custom_lists+list_items — see Docs/schema.sql).
// Adding a film to a *custom* list from Search/MovieInfo isn't wired yet —
// only list creation. Lists start empty until that follow-up lands.

// MARK: - ViewModel

@Observable
@MainActor
final class ListsViewModel {
    var rankedItems: [RankedItem] = []
    var watchlistItems: [WatchlistEntry] = []
    var customLists: [CustomList] = []
    var listItems: [UUID: [ListItem]] = [:]
    var films: [Int: MediaItem] = [:]
    var isLoadingWatched = false
    var isLoadingWatchlist = false
    var isLoadingLists = false

    private func resolve(tmdbID: Int, mediaType: MediaType) async {
        guard films[tmdbID] == nil else { return }
        if let media = try? await TMDBClient.shared.details(tmdbID: tmdbID, mediaType: mediaType) {
            films[tmdbID] = media
        }
    }

    func loadWatched(userID: UUID?) async {
        guard let userID else { return }
        isLoadingWatched = rankedItems.isEmpty
        do {
            let items: [RankedItem] = try await SupabaseClient.shared
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .order("elo_score", ascending: false)
                .execute()
                .value
            rankedItems = items
            for (i, item) in items.enumerated() {
                await resolve(tmdbID: item.tmdbID, mediaType: item.mediaType)
                if i % 5 == 0 { await Task.yield() }
            }
        } catch {}
        isLoadingWatched = false
    }

    func loadWatchlist(userID: UUID?) async {
        guard let userID else { return }
        isLoadingWatchlist = watchlistItems.isEmpty
        do {
            let items: [WatchlistEntry] = try await SupabaseClient.shared
                .from("watchlist")
                .select()
                .eq("user_id", value: userID)
                .order("added_at", ascending: false)
                .execute()
                .value
            watchlistItems = items
            for (i, item) in items.enumerated() {
                await resolve(tmdbID: item.tmdbID, mediaType: item.mediaType)
                if i % 5 == 0 { await Task.yield() }
            }
        } catch {}
        isLoadingWatchlist = false
    }

    func loadCustomLists(userID: UUID?) async {
        guard let userID else { return }
        isLoadingLists = customLists.isEmpty
        do {
            customLists = try await SupabaseClient.shared
                .from("custom_lists")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {}
        isLoadingLists = false
    }

    func loadItems(for list: CustomList) async {
        guard listItems[list.id] == nil else { return }
        do {
            let items: [ListItem] = try await SupabaseClient.shared
                .from("list_items")
                .select()
                .eq("list_id", value: list.id)
                .order("added_at", ascending: false)
                .execute()
                .value
            listItems[list.id] = items
            for (i, item) in items.enumerated() {
                await resolve(tmdbID: item.tmdbID, mediaType: item.mediaType)
                if i % 5 == 0 { await Task.yield() }
            }
        } catch {}
    }

    @discardableResult
    func createList(name: String, userID: UUID?) async -> CustomList? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let userID, !trimmed.isEmpty else { return nil }
        let newList = CustomList(id: UUID(), userID: userID, name: trimmed, createdAt: Date())
        do {
            try await SupabaseClient.shared
                .from("custom_lists")
                .insert(["id": newList.id.uuidString, "user_id": userID.uuidString, "name": trimmed])
                .execute()
            customLists.append(newList)
            listItems[newList.id] = []
            return newList
        } catch {}
        return nil
    }

    func removeFromWatchlist(entry: WatchlistEntry) async {
        do {
            try await SupabaseClient.shared.from("watchlist")
                .delete().eq("id", value: entry.id).execute()
            watchlistItems.removeAll { $0.id == entry.id }
        } catch {}
    }

    func deleteList(_ list: CustomList) async {
        do {
            try await SupabaseClient.shared.from("custom_lists")
                .delete().eq("id", value: list.id).execute()
            customLists.removeAll { $0.id == list.id }
            listItems.removeValue(forKey: list.id)
        } catch {}
    }

    func removeFromList(_ item: ListItem) async {
        do {
            try await SupabaseClient.shared.from("list_items")
                .delete().eq("id", value: item.id).execute()
            listItems[item.listID]?.removeAll { $0.id == item.id }
        } catch {}
    }
}

// Matches the existing 10-Movie Wall onboarding gate — by the time someone
// can even reach this tab they've already crossed it, so scores are
// unlocked in the normal flow. This only matters for accounts seeded
// outside onboarding (QA, dev). Below 10, the rank-based /10 formula's
// endpoints (#1 = 10.0, last place = 0.0) swing too hard between just a
// couple of films to read as a real score rather than a glitch.
private let scoresUnlockThreshold = 10

// MARK: - ListsView

private enum ListsSelection: Hashable {
    case watched
    case watchlist
    case custom(UUID)
}

struct ListsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ListsViewModel()
    @State private var selection: ListsSelection = .watched
    @State private var showCreateList = false
    @State private var rankingFilm: MediaItem?
    @State private var listPendingDelete: CustomList?
    @State private var watchlistEntryPendingDelete: WatchlistEntry?
    @State private var listItemPendingDelete: ListItem?
    @AppStorage("cinema_dev_scores_unlocked") private var devScoresUnlocked = false

    var body: some View {
        ZStack {
            WarmTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenTitle("My Lists")
                tabSwitcher

                switch selection {
                case .watched:
                    watchedContent
                case .watchlist:
                    watchlistContent
                case .custom(let id):
                    if let list = vm.customLists.first(where: { $0.id == id }) {
                        customListContent(list)
                    }
                }
            }
        }
        .task {
            async let a: () = vm.loadWatched(userID: appState.currentUser?.id)
            async let b: () = vm.loadWatchlist(userID: appState.currentUser?.id)
            async let c: () = vm.loadCustomLists(userID: appState.currentUser?.id)
            _ = await (a, b, c)
        }
        .sheet(isPresented: $showCreateList) {
            CreateListSheet { name in
                if let list = await vm.createList(name: name, userID: appState.currentUser?.id) {
                    selection = .custom(list.id)
                }
            }
        }
        .sheet(item: $rankingFilm, onDismiss: {
            Task { await vm.loadWatched(userID: appState.currentUser?.id) }
        }) { film in
            RankingView(film: film)
        }
        .alert(
            "Delete \u{201C}\(listPendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { listPendingDelete != nil },
                set: { if !$0 { listPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { listPendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let list = listPendingDelete {
                    if selection == .custom(list.id) { selection = .watched }
                    Task { await vm.deleteList(list) }
                }
                listPendingDelete = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Remove from Watchlist?",
            isPresented: Binding(
                get: { watchlistEntryPendingDelete != nil },
                set: { if !$0 { watchlistEntryPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { watchlistEntryPendingDelete = nil }
            Button("Remove", role: .destructive) {
                if let entry = watchlistEntryPendingDelete {
                    Task { await vm.removeFromWatchlist(entry: entry) }
                }
                watchlistEntryPendingDelete = nil
            }
        }
        .alert(
            "Remove from this list?",
            isPresented: Binding(
                get: { listItemPendingDelete != nil },
                set: { if !$0 { listItemPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { listItemPendingDelete = nil }
            Button("Remove", role: .destructive) {
                if let item = listItemPendingDelete {
                    Task { await vm.removeFromList(item) }
                }
                listItemPendingDelete = nil
            }
        }
    }

    // MARK: Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("Watched", isSelected: selection == .watched) { selection = .watched }
                    pill("Watchlist", isSelected: selection == .watchlist) { selection = .watchlist }
                    ForEach(vm.customLists) { list in
                        pill(list.name, isSelected: selection == .custom(list.id)) {
                            selection = .custom(list.id)
                            Task { await vm.loadItems(for: list) }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                listPendingDelete = list
                            } label: {
                                Label("Delete List", systemImage: "trash")
                            }
                        }
                        .sensoryFeedback(.impact(weight: .medium), trigger: listPendingDelete == list)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 8)
            }

            Button {
                showCreateList = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WarmTheme.titleText)
                    .frame(width: 36, height: 36)
                    .background(WarmTheme.chipBackground)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Create List")
            .padding(.trailing, 20)
        }
        .padding(.bottom, 14)
    }

    private func pill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WarmTheme.Font.bodyBold(14))
                .foregroundStyle(isSelected ? .white : WarmTheme.nameText)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(isSelected ? WarmTheme.accent : WarmTheme.chipBackground)
                .clipShape(Capsule())
        }
    }

    // MARK: Watched Content

    @ViewBuilder
    private var watchedContent: some View {
        if vm.isLoadingWatched {
            loadingSpacer
        } else if vm.rankedItems.isEmpty {
            EmptyStateView(message: "Rank your first film to start your list.")
        } else {
            let unlocked = devScoresUnlocked || vm.rankedItems.count >= scoresUnlockThreshold
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !unlocked {
                        ScoresLockedHint(rankedCount: vm.rankedItems.count, threshold: scoresUnlockThreshold)
                    }
                    ForEach(Array(vm.rankedItems.enumerated()), id: \.element.id) { index, item in
                        PosterRow(
                            rank: index + 1,
                            media: vm.films[item.tmdbID],
                            tmdbID: item.tmdbID
                        ) {
                            if unlocked {
                                Text(String(format: "%.1f", ratingOutOf10(rankPosition: index + 1, totalRanked: vm.rankedItems.count)))
                                    .font(WarmTheme.Font.bodyBold(13))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(WarmTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        rowDivider(isLast: index == vm.rankedItems.count - 1)
                    }
                }
                .padding(.bottom, 100)
            }
            .refreshable { await vm.loadWatched(userID: appState.currentUser?.id) }
        }
    }

    // MARK: Watchlist Content

    @ViewBuilder
    private var watchlistContent: some View {
        if vm.isLoadingWatchlist {
            loadingSpacer
        } else if vm.watchlistItems.isEmpty {
            EmptyStateView(message: "Save films you want to watch here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.watchlistItems.enumerated()), id: \.element.id) { index, entry in
                        PosterRow(rank: nil, media: vm.films[entry.tmdbID], tmdbID: entry.tmdbID) {
                            RankItButton {
                                Task {
                                    await vm.removeFromWatchlist(entry: entry)
                                    rankingFilm = vm.films[entry.tmdbID]
                                }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                watchlistEntryPendingDelete = entry
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        rowDivider(isLast: index == vm.watchlistItems.count - 1)
                    }
                }
                .padding(.bottom, 100)
            }
            .refreshable { await vm.loadWatchlist(userID: appState.currentUser?.id) }
        }
    }

    // MARK: Custom List Content

    @ViewBuilder
    private func customListContent(_ list: CustomList) -> some View {
        let items = vm.listItems[list.id] ?? []
        if items.isEmpty {
            EmptyStateView(message: "No films in \u{201C}\(list.name)\u{201D} yet.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PosterRow(rank: nil, media: vm.films[item.tmdbID], tmdbID: item.tmdbID) {
                            RankItButton {
                                rankingFilm = vm.films[item.tmdbID]
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                listItemPendingDelete = item
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        rowDivider(isLast: index == items.count - 1)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    private var loadingSpacer: some View {
        VStack {
            Spacer()
            ProgressView().tint(WarmTheme.accent)
            Spacer()
        }
    }

    private func rowDivider(isLast: Bool) -> some View {
        Group {
            if !isLast {
                Rectangle()
                    .fill(WarmTheme.divider)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Scores Locked Hint

private struct ScoresLockedHint: View {
    let rankedCount: Int
    let threshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rank \(threshold - rankedCount) more film\(threshold - rankedCount == 1 ? "" : "s") to reveal scores.")
                .font(WarmTheme.Font.body(13))
                .foregroundStyle(WarmTheme.secondaryText)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WarmTheme.chipBackground)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WarmTheme.accent)
                        .frame(width: geo.size.width * min(CGFloat(rankedCount) / CGFloat(threshold), 1.0), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Rank It Button

private struct RankItButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Rank it")
                .font(WarmTheme.Font.bodyBold(12))
                .foregroundStyle(WarmTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(WarmTheme.accent, lineWidth: 1.5))
        }
    }
}

// MARK: - Poster Row

private struct PosterRow<Trailing: View>: View {
    let rank: Int?
    let media: MediaItem?
    let tmdbID: Int
    @ViewBuilder let trailing: () -> Trailing

    private var rankColor: Color {
        guard let rank else { return WarmTheme.titleText }
        return rank <= 3 ? WarmTheme.accent : WarmTheme.titleText
    }

    var body: some View {
        HStack(spacing: 14) {
            if let rank {
                Text("\(rank)")
                    .font(rank <= 3 ? WarmTheme.Font.wordmarkBold(22) : WarmTheme.Font.wordmark(18))
                    .foregroundStyle(rankColor)
                    .frame(width: 30, alignment: .center)
            }

            poster
                .frame(width: 56, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(media?.title ?? "Loading\u{2026}")
                    .font(WarmTheme.Font.wordmark(17))
                    .foregroundStyle(WarmTheme.titleText)
                    .lineLimit(1)
                if let year = media?.releaseYear {
                    Text(year)
                        .font(WarmTheme.Font.body(13))
                        .foregroundStyle(WarmTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var poster: some View {
        if let path = media?.posterPath, let url = TMDBClient.shared.posterURL(path: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        let colors = PosterPlaceholder.colors(seed: tmdbID)
        return PosterPlaceholder(dark: colors.dark, darker: colors.darker)
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(message)
                .font(WarmTheme.Font.body(15))
                .foregroundStyle(WarmTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Create List Sheet

/// Not private — reused by AddToListSheet.swift (Search's "Add to List" flow) for inline list creation.
struct CreateListSheet: View {
    let onCreate: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            WarmTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("Name your list")
                    .font(WarmTheme.Font.wordmarkBold(24))
                    .foregroundStyle(WarmTheme.titleText)
                    .padding(.top, 28)

                VStack(spacing: 0) {
                    TextField("Funny Movies", text: $name)
                        .font(WarmTheme.Font.body(18))
                        .foregroundStyle(WarmTheme.titleText)
                        .tint(WarmTheme.accent)
                        .focused($focused)
                        .padding(.bottom, 10)
                    Rectangle()
                        .fill(name.isEmpty ? WarmTheme.divider : WarmTheme.accent)
                        .frame(height: 1.5)
                }

                Spacer()

                Button {
                    isSaving = true
                    Task {
                        await onCreate(name)
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    ZStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create")
                                .font(WarmTheme.Font.bodyBold(16))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? WarmTheme.accent.opacity(0.4) : WarmTheme.accent)
                    .clipShape(Capsule())
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .presentationDetents([.height(240)])
        .onAppear { focused = true }
    }
}
