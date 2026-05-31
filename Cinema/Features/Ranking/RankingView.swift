import SwiftUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class RankingViewModel {
    var currentPair: (MediaItem, MediaItem)?
    var rankedItems: [RankedItem] = []
    var isLoading = false
    var flashMessage: String?
    var totalBattles = 0

    private var recentMatchups: [(Int, Int)] = []

    func loadNextPair(userID: UUID?) async {
        guard let userID else { return }
        isLoading = currentPair == nil
        do {
            let items: [RankedItem] = try await SupabaseClient.shared.database
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .order("elo_score", ascending: false)
                .execute()
                .value
            rankedItems = items
            if let pair = selectPair(from: items) {
                let left  = try await TMDBClient.shared.details(tmdbID: pair.0, mediaType: .movie)
                let right = try await TMDBClient.shared.details(tmdbID: pair.1, mediaType: .movie)
                currentPair = (left, right)
            }
        } catch {}
        isLoading = false
    }

    // 70% ELO proximity, 20% new entrant fast-calibration, 10% stress test
    private func selectPair(from items: [RankedItem]) -> (Int, Int)? {
        guard items.count >= 2 else { return nil }
        let roll = Double.random(in: 0...1)
        let pair: (Int, Int)?
        if roll < 0.70 {
            pair = proximityPair(items)
        } else if roll < 0.90 {
            pair = newEntrantPair(items)
        } else {
            pair = stressTestPair(items)
        }
        return pair ?? proximityPair(items)
    }

    private func proximityPair(_ items: [RankedItem]) -> (Int, Int)? {
        let sorted = items.sorted { $0.eloScore > $1.eloScore }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i].tmdbID
            let b = sorted[i + 1].tmdbID
            if !wasRecentlyMatched(a, b) { return (a, b) }
        }
        return (sorted[0].tmdbID, sorted[1].tmdbID)
    }

    private func newEntrantPair(_ items: [RankedItem]) -> (Int, Int)? {
        let newbies = items.filter { abs($0.eloScore - 1500) < 20 }
        guard let newbie = newbies.randomElement(),
              let opponent = items.filter({ $0.tmdbID != newbie.tmdbID }).randomElement()
        else { return nil }
        return (newbie.tmdbID, opponent.tmdbID)
    }

    private func stressTestPair(_ items: [RankedItem]) -> (Int, Int)? {
        guard let top = items.max(by: { $0.eloScore < $1.eloScore }),
              let challenger = items.filter({ $0.tmdbID != top.tmdbID }).randomElement()
        else { return nil }
        return (top.tmdbID, challenger.tmdbID)
    }

    private func wasRecentlyMatched(_ a: Int, _ b: Int) -> Bool {
        recentMatchups.contains { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }
    }

    func choose(winner: MediaItem, loser: MediaItem, userID: UUID?) async {
        guard let userID else { return }

        let winnerItem = rankedItems.first { $0.tmdbID == winner.id }
        let loserItem  = rankedItems.first { $0.tmdbID == loser.id }
        let wElo = winnerItem?.eloScore ?? 1500
        let lElo = loserItem?.eloScore ?? 1500

        let (newWinner, newLoser) = ELOService.newRatings(winnerRating: wElo, loserRating: lElo)

        // Track matchup to avoid repeats
        recentMatchups.append((winner.id, loser.id))
        if recentMatchups.count > 30 { recentMatchups.removeFirst() }
        totalBattles += 1

        do {
            // Upsert winner
            try await SupabaseClient.shared.database
                .from("ranked_items")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(winner.id),
                    "media_type": "movie",
                    "elo_score": String(newWinner),
                ])
                .execute()

            // Upsert loser
            try await SupabaseClient.shared.database
                .from("ranked_items")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(loser.id),
                    "media_type": "movie",
                    "elo_score": String(newLoser),
                ])
                .execute()

            // Log match
            try await SupabaseClient.shared.database
                .from("elo_matches")
                .insert([
                    "user_id": userID.uuidString,
                    "winner_tmdb_id": String(winner.id),
                    "loser_tmdb_id": String(loser.id),
                    "media_type": "movie",
                ])
                .execute()
        } catch {}

        await loadNextPair(userID: userID)
        await showFlash(for: winner, newElo: newWinner)
    }

    private func showFlash(for film: MediaItem, newElo: Double) async {
        let sortedElos = rankedItems.map { $0.eloScore }.sorted(by: >)
        let rank = (sortedElos.firstIndex { newElo >= $0 } ?? sortedElos.count) + 1
        withAnimation { flashMessage = "\(film.title) — #\(rank)" }
        try? await Task.sleep(for: .seconds(1.8))
        withAnimation { flashMessage = nil }
    }
}

// MARK: - RankingView

struct RankingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm = RankingViewModel()

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold).scaleEffect(1.5)
            } else if let pair = vm.currentPair {
                BattleView(pair: pair) { winner, loser in
                    Task { await vm.choose(winner: winner, loser: loser, userID: appState.currentUser?.id) }
                }
            } else {
                EmptyRankingView()
            }

            // Top bar
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("This or That")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    Spacer()
                    Text("\(vm.totalBattles)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .frame(width: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)

                // Flash
                if let flash = vm.flashMessage {
                    Text(flash)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 12)
                }

                Spacer()
            }
        }
        .task { await vm.loadNextPair(userID: appState.currentUser?.id) }
    }
}

// MARK: - Battle View

private struct BattleView: View {
    let pair: (MediaItem, MediaItem)
    let onChoose: (MediaItem, MediaItem) -> Void
    @State private var chosen: Side?

    enum Side { case left, right }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                PosterSide(
                    item: pair.0,
                    isWinner: chosen == .left,
                    isLoser: chosen == .right,
                    width: geo.size.width / 2
                )
                .onTapGesture { pick(.left) }

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)

                PosterSide(
                    item: pair.1,
                    isWinner: chosen == .right,
                    isLoser: chosen == .left,
                    width: geo.size.width / 2
                )
                .onTapGesture { pick(.right) }
            }
            .ignoresSafeArea()
        }
        .id("\(pair.0.id)-\(pair.1.id)")
    }

    private func pick(_ side: Side) {
        guard chosen == nil else { return }
        withAnimation(.spring(duration: 0.35)) { chosen = side }
        let winner = side == .left ? pair.0 : pair.1
        let loser  = side == .left ? pair.1 : pair.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onChoose(winner, loser)
        }
    }
}

private struct PosterSide: View {
    let item: MediaItem
    let isWinner: Bool
    let isLoser: Bool
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            PosterImage(path: item.posterPath, cornerRadius: 0)
                .frame(width: width)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 4) {
                if let year = item.releaseYear {
                    Text(year)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
                Text(item.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 60)

            if isWinner {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(CinemaTheme.Colors.gold)
                    .padding(.bottom, 160)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: width)
        .scaleEffect(isLoser ? 0.93 : 1.0)
        .opacity(isLoser ? 0.3 : 1.0)
        .animation(.spring(duration: 0.35), value: isWinner)
        .animation(.spring(duration: 0.35), value: isLoser)
    }
}

private struct EmptyRankingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 52))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Text("Search for films to start ranking")
                .font(.system(size: 17))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
