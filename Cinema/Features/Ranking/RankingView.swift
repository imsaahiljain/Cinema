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
            let items: [RankedItem] = try await SupabaseClient.shared
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
                withAnimation(.easeInOut(duration: 0.25)) { currentPair = (left, right) }
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
            try await SupabaseClient.shared
                .from("ranked_items")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(winner.id),
                    "media_type": "movie",
                    "elo_score": String(newWinner),
                ])
                .execute()

            // Upsert loser
            try await SupabaseClient.shared
                .from("ranked_items")
                .upsert([
                    "user_id": userID.uuidString,
                    "tmdb_id": String(loser.id),
                    "media_type": "movie",
                    "elo_score": String(newLoser),
                ])
                .execute()

            // Log match
            try await SupabaseClient.shared
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

    @State private var dragTranslation: CGFloat = 0
    @State private var winnerStartSide: RankingDuelSide?
    @State private var thresholdCrossed = false
    @State private var pulseSide: RankingDuelSide?
    @State private var commitTick = 0

    private let commitProgress: CGFloat = 0.6

    var body: some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width / 2
            let progress = revealProgress(travel: halfWidth)

            ZStack {
                HStack(spacing: 0) {
                    posterSide(.left, item: pair.0, geo: geo, progress: progress, travel: halfWidth)
                    posterSide(.right, item: pair.1, geo: geo, progress: progress, travel: halfWidth)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()

                VStack(spacing: 26) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                    Circle()
                        .strokeBorder(CinemaTheme.Colors.gold.opacity(0.8), lineWidth: 1)
                        .background(Circle().fill(CinemaTheme.Colors.background.opacity(0.6)))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text("vs")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CinemaTheme.Colors.gold)
                        )
                }
                .opacity(1 - progress)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if winnerStartSide == nil {
                            winnerStartSide = value.startLocation.x < halfWidth ? .left : .right
                        }
                        dragTranslation = value.translation.width
                        let p = revealProgress(travel: halfWidth)
                        let crossed = p > commitProgress
                        if crossed != thresholdCrossed { thresholdCrossed = crossed }
                    }
                    .onEnded { _ in
                        let p = revealProgress(travel: halfWidth)
                        if p > commitProgress, let winner = winnerStartSide {
                            commitPick(winner)
                        } else {
                            withAnimation(.spring(duration: 0.35)) { dragTranslation = 0 }
                            thresholdCrossed = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                winnerStartSide = nil
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: thresholdCrossed)
        .sensoryFeedback(.impact(weight: .medium), trigger: commitTick)
        .id("\(pair.0.id)-\(pair.1.id)")
    }

    private func revealProgress(travel: CGFloat) -> CGFloat {
        guard let winnerStartSide else { return 0 }
        let signed = winnerStartSide == .left ? dragTranslation : -dragTranslation
        return max(0, min(1, signed / travel))
    }

    @ViewBuilder
    private func posterSide(_ side: RankingDuelSide, item: MediaItem, geo: GeometryProxy, progress: CGFloat, travel: CGFloat) -> some View {
        let isWinner = winnerStartSide == side
        let isLoser = winnerStartSide != nil && winnerStartSide != side

        let base = RealPosterSide(item: item, isPulsing: pulseSide == side)
            .frame(width: geo.size.width / 2)

        DiagonalOverarchWinEffect.apply(base, .init(
            isWinner: isWinner,
            isLoser: isLoser,
            side: side,
            progress: progress,
            travel: travel
        ))
        .animation(.easeOut(duration: 0.15), value: progress)
    }

    private func commitPick(_ side: RankingDuelSide) {
        pulseSide = side
        commitTick += 1
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { dragTranslation = 0 }
        thresholdCrossed = false
        let winner = side == .left ? pair.0 : pair.1
        let loser = side == .left ? pair.1 : pair.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onChoose(winner, loser)
        }
    }
}

private struct RealPosterSide: View {
    let item: MediaItem
    let isPulsing: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Color.black.opacity(0.35)

                VStack(spacing: 10) {
                    PosterImage(path: item.posterPath, cornerRadius: 12)
                        .frame(width: geo.size.width * 0.62, height: geo.size.width * 0.62 * 1.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    VStack(spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                        if let year = item.releaseYear {
                            Text(year)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(
            Rectangle()
                .strokeBorder(CinemaTheme.Colors.gold.opacity(isPulsing ? 0.9 : 0), lineWidth: 3)
        )
        .scaleEffect(isPulsing ? 1.02 : 1.0)
        .animation(.spring(duration: 0.3), value: isPulsing)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let path = item.backdropPath, let url = TMDBClient.shared.backdropURL(path: path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    CinemaTheme.Colors.surface
                }
            }
        } else if let path = item.posterPath, let url = TMDBClient.shared.posterURL(path: path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill).blur(radius: 18)
                } else {
                    CinemaTheme.Colors.surface
                }
            }
        } else {
            CinemaTheme.Colors.surface
        }
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
