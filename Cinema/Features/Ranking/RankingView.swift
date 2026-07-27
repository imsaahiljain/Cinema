import SwiftUI
import Supabase

// MARK: - Rank Bucket

// Liked/Okay/Disliked map onto ELO bands rather than a separate stored column —
// a film's bucket is just where its elo_score lands, so Lists' existing live
// sort-by-elo-score keeps working unmodified.
enum RankBucket: CaseIterable {
    case liked, okay, disliked

    var label: String {
        switch self {
        case .liked: "Liked it"
        case .okay: "It was fine"
        case .disliked: "Didn't like it"
        }
    }

    var color: Color {
        switch self {
        case .liked: Color(red: 0.39, green: 0.6, blue: 0.13)
        case .okay: Color(red: 0.73, green: 0.46, blue: 0.09)
        case .disliked: Color(red: 0.64, green: 0.18, blue: 0.18)
        }
    }

    var startingElo: Double {
        switch self {
        case .liked: 1800
        case .okay: 1500
        case .disliked: 1200
        }
    }

    var lowerBound: Double {
        switch self {
        case .liked: 1650
        case .okay: 1350
        case .disliked: -.infinity
        }
    }

    var upperBound: Double {
        switch self {
        case .liked: .infinity
        case .okay: 1650
        case .disliked: 1350
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class RankingViewModel {
    enum Stage { case rate, loadingOpponent, compare, ranked }

    let film: MediaItem
    var stage: Stage = .rate
    var chosenBucket: RankBucket?
    var opponent: MediaItem?
    var lastPosition = 1
    var lastBucketSize = 1

    // Only offer "Too tough" once narrowing has nearly converged — accepting the
    // midpoint early would throw away real information, not just skip a hard call.
    var tooToughAvailable: Bool { chosenBucket != nil && (hi - lo) <= 2 }

    var pickTick = 0
    var rankedTick = 0
    var tooToughTick = 0

    private var lo = 0
    private var hi = 0
    private var comparisonCount = 0
    private var filmElo: Double = 1500
    private var bucketItems: [RankedItem] = []
    private var opponentItem: RankedItem?

    init(film: MediaItem) {
        self.film = film
    }

    func chooseBucket(_ bucket: RankBucket, userID: UUID?) async {
        guard let userID else { return }
        chosenBucket = bucket
        filmElo = bucket.startingElo

        do {
            var query = SupabaseClient.shared
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .eq("media_type", value: film.mediaType.rawValue)
                .neq("tmdb_id", value: film.id)
            if bucket.lowerBound.isFinite { query = query.gte("elo_score", value: bucket.lowerBound) }
            if bucket.upperBound.isFinite { query = query.lt("elo_score", value: bucket.upperBound) }
            let items: [RankedItem] = try await query
                .order("elo_score", ascending: false)
                .execute().value
            bucketItems = items
        } catch {
            bucketItems = []
        }

        do {
            try await SupabaseClient.shared.from("ranked_items").upsert([
                "user_id": userID.uuidString, "tmdb_id": String(film.id),
                "media_type": film.mediaType.rawValue, "elo_score": String(filmElo),
            ]).execute()
        } catch {}

        lo = 0; hi = bucketItems.count; comparisonCount = 0
        if bucketItems.isEmpty {
            await finish()
        } else {
            await loadOpponent()
        }
    }

    private func loadOpponent() async {
        stage = .loadingOpponent
        let idx = min((lo + hi) / 2, bucketItems.count - 1)
        let item = bucketItems[max(0, idx)]
        opponentItem = item
        opponent = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType)
        stage = .compare
    }

    // filmWon: true if the film being ranked won this comparison
    func choose(filmWon: Bool, userID: UUID?) async {
        guard let userID, let oppItem = opponentItem else { return }
        pickTick += 1
        comparisonCount += 1

        let newFilmElo: Double
        let newOppElo: Double
        if filmWon {
            (newFilmElo, newOppElo) = ELOService.newRatings(winnerRating: filmElo, loserRating: oppItem.eloScore)
        } else {
            (newOppElo, newFilmElo) = ELOService.newRatings(winnerRating: oppItem.eloScore, loserRating: filmElo)
        }
        filmElo = newFilmElo

        do {
            try await SupabaseClient.shared.from("ranked_items").upsert([
                "user_id": userID.uuidString, "tmdb_id": String(film.id),
                "media_type": film.mediaType.rawValue, "elo_score": String(filmElo),
            ]).execute()
            try await SupabaseClient.shared.from("ranked_items").upsert([
                "user_id": userID.uuidString, "tmdb_id": String(oppItem.tmdbID),
                "media_type": oppItem.mediaType.rawValue, "elo_score": String(newOppElo),
            ]).execute()
            try await SupabaseClient.shared.from("elo_matches").insert([
                "user_id": userID.uuidString,
                "winner_tmdb_id": String(filmWon ? film.id : oppItem.tmdbID),
                "loser_tmdb_id": String(filmWon ? oppItem.tmdbID : film.id),
                "media_type": film.mediaType.rawValue,
            ]).execute()
        } catch {}

        let idx = min((lo + hi) / 2, bucketItems.count - 1)
        if filmWon { hi = idx } else { lo = idx + 1 }
        if lo >= hi || comparisonCount >= 4 {
            await finish()
        } else {
            await loadOpponent()
        }
    }

    func tooTough() async {
        guard tooToughAvailable else { return }
        tooToughTick += 1
        await finish()
    }

    private func finish() async {
        rankedTick += 1
        lastPosition = lo + 1
        lastBucketSize = bucketItems.count + 1
        stage = .ranked
    }
}

// MARK: - RankingView

struct RankingView: View {
    let film: MediaItem
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm: RankingViewModel

    init(film: MediaItem) {
        self.film = film
        _vm = State(initialValue: RankingViewModel(film: film))
    }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            Group {
                switch vm.stage {
                case .rate:
                    RateItView(film: film) { bucket in
                        Task { await vm.chooseBucket(bucket, userID: appState.currentUser?.id) }
                    }
                case .loadingOpponent:
                    ProgressView().tint(CinemaTheme.Colors.gold).scaleEffect(1.5)
                case .compare:
                    if let opponent = vm.opponent, let bucket = vm.chosenBucket {
                        BattleView(
                            left: opponent, right: film, bucketColor: bucket.color,
                            tooToughAvailable: vm.tooToughAvailable,
                            onPick: { side in
                                Task { await vm.choose(filmWon: side == .right, userID: appState.currentUser?.id) }
                            },
                            onTooTough: {
                                Task { await vm.tooTough() }
                            }
                        )
                    }
                case .ranked:
                    RankedResultView(
                        film: film, position: vm.lastPosition, bucketSize: vm.lastBucketSize,
                        bucketLabel: vm.chosenBucket?.label ?? ""
                    ) { dismiss() }
                }
            }

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
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }
        }
    }
}

// MARK: - Rate It (bucket triage)

private struct RateItView: View {
    let film: MediaItem
    let onPick: (RankBucket) -> Void
    @State private var selected: RankBucket?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            HStack(spacing: 12) {
                PosterImage(path: film.posterPath, cornerRadius: 8).frame(width: 56, height: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text(film.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Text("Marked as watched").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            Spacer()

            Text("How was it?")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 40)

            HStack(spacing: 0) {
                ForEach(RankBucket.allCases, id: \.self) { bucket in
                    Button {
                        selected = bucket
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPick(bucket) }
                    } label: {
                        VStack(spacing: 12) {
                            Circle()
                                .fill(bucket.color)
                                .frame(width: 76, height: 76)
                                .overlay(Circle().strokeBorder(.white, lineWidth: selected == bucket ? 2 : 0))
                                .scaleEffect(selected == bucket ? 1.08 : 1.0)
                            Text(bucket.label)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .animation(.spring(duration: 0.25), value: selected)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Battle View (tap-to-pick duel)

private struct BattleView: View {
    let left: MediaItem
    let right: MediaItem
    let bucketColor: Color
    let tooToughAvailable: Bool
    let onPick: (RankingDuelSide) -> Void
    let onTooTough: () -> Void

    @State private var winnerSide: RankingDuelSide?
    @State private var committedProgress: CGFloat = 0
    @State private var commitTick = 0

    var body: some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width / 2
            ZStack {
                HStack(spacing: 0) {
                    posterSide(.left, item: left, geo: geo, travel: halfWidth)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                    posterSide(.right, item: right, geo: geo, travel: halfWidth)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                Text("Which do you prefer?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 8)
                    .opacity(winnerSide == nil ? 1 : 0)
                    .padding(.top, 66)
                    .frame(maxHeight: .infinity, alignment: .top)

                Button(action: onTooTough) {
                    Text("Too tough")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(tooToughAvailable ? 0.9 : 0.25))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial.opacity(tooToughAvailable ? 1 : 0.4))
                        .clipShape(Capsule())
                }
                .disabled(!tooToughAvailable)
                .opacity(winnerSide == nil ? 1 : 0)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .medium), trigger: commitTick)
        .id("\(left.id)-\(right.id)")
    }

    @ViewBuilder
    private func posterSide(_ side: RankingDuelSide, item: MediaItem, geo: GeometryProxy, travel: CGFloat) -> some View {
        let isWinner = winnerSide == side
        let isLoser = winnerSide != nil && winnerSide != side

        let base = RealPosterSide(item: item)
            .frame(width: geo.size.width / 2)
            .contentShape(Rectangle())
            .onTapGesture { commit(side) }

        DiagonalOverarchWinEffect.apply(base, .init(
            isWinner: isWinner, isLoser: isLoser, side: side,
            progress: committedProgress, travel: travel
        ))
    }

    private func commit(_ side: RankingDuelSide) {
        guard winnerSide == nil else { return }
        winnerSide = side
        commitTick += 1
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { committedProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onPick(side)
        }
    }
}

// One image per side, full stop — the old version layered a cropped, blurred
// backdrop behind a separate poster card, which read as two competing pieces
// of art (and the backdrop, built for 16:9, only ever showed a random sliver
// once squeezed into a half-screen-wide column). Just the poster now, sized to
// stay fully legible, on the app's own quiet surface color — no second image.
private struct RealPosterSide: View {
    let item: MediaItem

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CinemaTheme.Colors.surface

                VStack(spacing: 14) {
                    PosterImage(path: item.posterPath, cornerRadius: 14)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: geo.size.width * 0.78)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    VStack(spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 14)
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
    }
}

// MARK: - Ranked Result

private struct RankedResultView: View {
    let film: MediaItem
    let position: Int
    let bucketSize: Int
    let bucketLabel: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(CinemaTheme.Colors.gold)
            Text("\(film.title) ranked!")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("#\(position) of \(bucketSize) in \"\(bucketLabel)\"")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CinemaTheme.Colors.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
