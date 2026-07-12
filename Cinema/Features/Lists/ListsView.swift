import SwiftUI
import Supabase

// MARK: - ListsView — "Rankings": Watched / Watchlist / Lists
//
// Built from the "Popcorn Rankings" design handoff (warm cream + brick-red
// accent, same design language as FeedMarqueeView — see WarmTheme.swift).
// Watched is real data (ranked_items via ELO). Watchlist and Lists have no
// backend yet (no watchlist/custom_lists tables in Docs/schema.sql), so
// they're placeholder states for now — separate feature to build next.

// MARK: - ViewModel

@Observable
@MainActor
final class ListsViewModel {
    var rankedItems: [RankedItem] = []
    var films: [Int: MediaItem] = [:]
    var isLoading = false

    func load(userID: UUID?) async {
        guard let userID else { return }
        isLoading = rankedItems.isEmpty
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
                if films[item.tmdbID] == nil {
                    if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                        films[item.tmdbID] = media
                    }
                    if i % 5 == 0 { await Task.yield() }
                }
            }
        } catch {}
        isLoading = false
    }
}

// MARK: - ListsView

enum ListsTab: String, CaseIterable {
    case watched = "Watched"
    case watchlist = "Watchlist"
    case lists = "Lists"
}

struct ListsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ListsViewModel()
    @State private var selectedTab: ListsTab = .watched

    var body: some View {
        ZStack {
            WarmTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabSwitcher

                switch selectedTab {
                case .watched:
                    watchedContent
                case .watchlist:
                    ComingSoonListView(message: "Save films you want to watch here.")
                case .lists:
                    ComingSoonListView(message: "Create your own lists, like \u{201C}Funny Movies.\u{201D}")
                }
            }
        }
        .task { await vm.load(userID: appState.currentUser?.id) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rankings")
                .font(WarmTheme.Font.wordmarkBold(34))
                .foregroundStyle(WarmTheme.titleText)
            Text("Ranked by head-to-head duels \u{00B7} \(vm.rankedItems.count) movies")
                .font(WarmTheme.Font.body(13))
                .foregroundStyle(WarmTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(ListsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(WarmTheme.Font.bodyBold(14))
                        .foregroundStyle(selectedTab == tab ? .white : WarmTheme.nameText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(selectedTab == tab ? WarmTheme.accent : WarmTheme.chipBackground)
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: Watched Content

    @ViewBuilder
    private var watchedContent: some View {
        if vm.isLoading {
            Spacer()
            ProgressView().tint(WarmTheme.accent)
            Spacer()
        } else if vm.rankedItems.isEmpty {
            ComingSoonListView(message: "Rank your first film to start your list.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.rankedItems.enumerated()), id: \.element.id) { index, item in
                        RankedRow(
                            rank: index + 1,
                            media: vm.films[item.tmdbID],
                            tmdbID: item.tmdbID,
                            score: ratingOutOf10(rankPosition: index + 1, totalRanked: vm.rankedItems.count)
                        )
                        if index < vm.rankedItems.count - 1 {
                            Rectangle()
                                .fill(WarmTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .refreshable { await vm.load(userID: appState.currentUser?.id) }
        }
    }
}

// MARK: - Ranked Row

private struct RankedRow: View {
    let rank: Int
    let media: MediaItem?
    let tmdbID: Int
    let score: Double

    private var rankColor: Color { rank <= 3 ? WarmTheme.accent : WarmTheme.titleText }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(rank <= 3 ? WarmTheme.Font.wordmarkBold(22) : WarmTheme.Font.wordmark(18))
                .foregroundStyle(rankColor)
                .frame(width: 30, alignment: .center)

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

            Text(String(format: "%.1f", score))
                .font(WarmTheme.Font.bodyBold(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(WarmTheme.accent, in: RoundedRectangle(cornerRadius: 8))
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

// MARK: - Coming Soon (Watchlist / Lists placeholder)

private struct ComingSoonListView: View {
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
