import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class MyFilmsViewModel {
    var rankedItems: [RankedItem] = []
    var films: [Int: MediaItem] = [:]
    var isLoading = false

    func load(userID: UUID?) async {
        guard let userID else { return }
        isLoading = rankedItems.isEmpty
        do {
            let items: [RankedItem] = try await SupabaseClient.shared.database
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .order("elo_score", ascending: false)
                .execute()
                .value
            rankedItems = items

            // Re-rank positions based on ELO order
            for (i, item) in items.enumerated() {
                if films[item.tmdbID] == nil {
                    if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                        films[item.tmdbID] = media
                    }
                    // Yield between fetches so UI stays responsive
                    if i % 5 == 0 { await Task.yield() }
                }
            }
        } catch {}
        isLoading = false
    }
}

// MARK: - MyFilmsView (the home "ranked list" tab)

struct MyFilmsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = MyFilmsViewModel()

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold)
            } else if vm.rankedItems.isEmpty {
                EmptyFilmsView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.rankedItems.enumerated()), id: \.element.id) { rank, item in
                            FilmRow(
                                rank: rank + 1,
                                item: item,
                                media: vm.films[item.tmdbID]
                            )
                            Divider()
                                .background(CinemaTheme.Colors.border)
                                .padding(.leading, 76)
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable { await vm.load(userID: appState.currentUser?.id) }
            }
        }
        .navigationTitle("My Films")
        .task { await vm.load(userID: appState.currentUser?.id) }
    }
}

// MARK: - Film Row

private struct FilmRow: View {
    let rank: Int
    let item: RankedItem
    let media: MediaItem?

    var body: some View {
        HStack(spacing: 16) {
            // Rank number
            Text("\(rank)")
                .font(.system(size: rank <= 9 ? 22 : 18, weight: .bold, design: .monospaced))
                .foregroundStyle(rank == 1 ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textSecondary)
                .frame(width: 32, alignment: .center)

            // Poster thumbnail
            PosterImage(path: media?.posterPath, cornerRadius: CinemaTheme.Radius.sm)
                .frame(width: 44, height: 66)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(media?.title ?? "Loading...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(2)

                if let year = media?.releaseYear {
                    Text(year)
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }

            Spacer()

            // ELO score (shown subtly)
            Text(String(format: "%.0f", item.eloScore))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Empty State

private struct EmptyFilmsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 52))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Text("No films ranked yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
            Text("Search for films and start ranking them")
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
