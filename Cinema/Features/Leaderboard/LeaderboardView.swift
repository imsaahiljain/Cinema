import SwiftUI
import Supabase

// MARK: - WatchlistViewModel

@Observable
@MainActor
final class WatchlistViewModel {
    struct WatchlistEntry: Identifiable {
        let id: Int
        let media: MediaItem?
    }

    var entries: [WatchlistEntry] = []
    var isLoading = false

    func load(userID: UUID?) async {
        guard let userID else { return }
        isLoading = entries.isEmpty
        do {
            struct WatchlistRow: Decodable {
                let tmdbID: Int
                let mediaType: String
                enum CodingKeys: String, CodingKey {
                    case tmdbID = "tmdb_id"
                    case mediaType = "media_type"
                }
            }
            let rows: [WatchlistRow] = try await SupabaseClient.shared.database
                .from("watchlist")
                .select()
                .eq("user_id", value: userID)
                .order("added_at", ascending: false)
                .execute()
                .value
            var loaded: [WatchlistEntry] = []
            for row in rows {
                let type = MediaType(rawValue: row.mediaType) ?? .movie
                let media = try? await TMDBClient.shared.details(tmdbID: row.tmdbID, mediaType: type)
                loaded.append(WatchlistEntry(id: row.tmdbID, media: media))
            }
            entries = loaded
        } catch {}
        isLoading = false
    }

    func remove(tmdbID: Int, userID: UUID?) async {
        guard let userID else { return }
        entries.removeAll { $0.id == tmdbID }
        try? await SupabaseClient.shared.database
            .from("watchlist")
            .delete()
            .eq("user_id", value: userID)
            .eq("tmdb_id", value: tmdbID)
            .execute()
    }
}

// MARK: - WatchlistView

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = WatchlistViewModel()

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold)
            } else if vm.entries.isEmpty {
                EmptyWatchlistView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.entries) { entry in
                            WatchlistRow(
                                entry: entry,
                                onRemove: {
                                    Task { await vm.remove(tmdbID: entry.id, userID: appState.currentUser?.id) }
                                }
                            )
                            Divider().background(CinemaTheme.Colors.border).padding(.leading, 76)
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable { await vm.load(userID: appState.currentUser?.id) }
            }
        }
        .navigationTitle("Watchlist")
        .task { await vm.load(userID: appState.currentUser?.id) }
    }
}

private struct WatchlistRow: View {
    let entry: WatchlistViewModel.WatchlistEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(path: entry.media?.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                .frame(width: 44, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.media?.title ?? "Loading...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(2)
                if let year = entry.media?.releaseYear {
                    Text(year).font(.system(size: 13)).foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(CinemaTheme.Colors.surface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct EmptyWatchlistView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark")
                .font(.system(size: 52))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Text("Your watchlist is empty")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
            Text("Bookmark films from Search to save them here")
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - LeaderboardView (kept for future social leaderboard)

struct LeaderboardView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(CinemaTheme.Colors.gold)
                Text("Leaderboard")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Text("Coming soon — global taste rankings")
                    .font(.system(size: 15))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }
        }
    }
}
