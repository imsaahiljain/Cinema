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
    enum Stage { case rate, details, loadingOpponent, compare, ranked }

    enum WatchDateOption: CaseIterable, Hashable {
        case today, yesterday, twoDaysAgo

        var label: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .twoDaysAgo: "2 days ago"
            }
        }

        var date: Date {
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: Date())
            switch self {
            case .today: return startOfToday
            case .yesterday: return cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            case .twoDaysAgo: return cal.date(byAdding: .day, value: -2, to: startOfToday) ?? startOfToday
            }
        }
    }

    let film: MediaItem
    var stage: Stage = .rate
    var chosenBucket: RankBucket?
    var opponent: MediaItem?
    var lastPosition = 1
    var lastBucketSize = 1

    var friends: [CinemaUser] = []
    var selectedFriendIDs: Set<UUID> = []
    var selectedDateOption: WatchDateOption = .today

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
        chosenBucket = bucket
        filmElo = bucket.startingElo
        withAnimation(.easeInOut(duration: 0.25)) { stage = .details }
        await loadFriends(userID: userID)
    }

    private func loadFriends(userID: UUID?) async {
        guard let userID else { return }
        struct FollowEdge: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        do {
            let edges: [FollowEdge] = try await SupabaseClient.shared
                .from("follows").select("following_id").eq("follower_id", value: userID)
                .execute().value
            guard !edges.isEmpty else { friends = []; return }
            let profiles: [CinemaUser] = try await SupabaseClient.shared
                .from("users").select().in("id", values: edges.map { $0.followingID.uuidString })
                .execute().value
            friends = profiles
        } catch {
            friends = []
        }
    }

    func toggleFriend(_ id: UUID) {
        if selectedFriendIDs.contains(id) { selectedFriendIDs.remove(id) } else { selectedFriendIDs.insert(id) }
    }

    func proceedToRanking(userID: UUID?) async {
        guard let userID, let bucket = chosenBucket else { return }

        do {
            var query = SupabaseClient.shared
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .eq("media_type", value: film.mediaType.rawValue)
                .neq("tmdb_id", value: film.id)
            if bucket.lowerBound.isFinite { query = query.gte("elo_score", value: bucket.lowerBound) }
            if bucket.upperBound.isFinite { query = query.lt("elo_score", value: bucket.upperBound) }
            bucketItems = try await query.order("elo_score", ascending: false).execute().value
        } catch {
            bucketItems = []
        }

        struct SeedUpsert: Encodable {
            let user_id: String
            let tmdb_id: String
            let media_type: String
            let elo_score: String
            let watched_with: [String]?
            let watched_date: String?
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let watchedWith = selectedFriendIDs.map { $0.uuidString }
        do {
            try await SupabaseClient.shared.from("ranked_items").upsert(
                SeedUpsert(
                    user_id: userID.uuidString, tmdb_id: String(film.id),
                    media_type: film.mediaType.rawValue, elo_score: String(filmElo),
                    watched_with: watchedWith.isEmpty ? nil : watchedWith,
                    watched_date: formatter.string(from: selectedDateOption.date)
                ),
                onConflict: "user_id,tmdb_id,media_type"
            ).execute()
        } catch {
            Log.ranking.error("Seed upsert failed: \(String(describing: error), privacy: .public)")
        }

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
            ], onConflict: "user_id,tmdb_id,media_type").execute()
            try await SupabaseClient.shared.from("ranked_items").upsert([
                "user_id": userID.uuidString, "tmdb_id": String(oppItem.tmdbID),
                "media_type": oppItem.mediaType.rawValue, "elo_score": String(newOppElo),
            ], onConflict: "user_id,tmdb_id,media_type").execute()
            try await SupabaseClient.shared.from("elo_matches").insert([
                "user_id": userID.uuidString,
                "winner_tmdb_id": String(filmWon ? film.id : oppItem.tmdbID),
                "loser_tmdb_id": String(filmWon ? oppItem.tmdbID : film.id),
                "media_type": film.mediaType.rawValue,
            ]).execute()
        } catch {
            Log.ranking.error("Choose upsert failed: \(String(describing: error), privacy: .public)")
        }

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
    @State private var selectedDetent: PresentationDetent = .height(380)

    init(film: MediaItem) {
        self.film = film
        _vm = State(initialValue: RankingViewModel(film: film))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeaderRow(film: film) { dismiss() }

            Group {
                switch vm.stage {
                case .rate:
                    RateItView { bucket in
                        Task { await vm.chooseBucket(bucket, userID: appState.currentUser?.id) }
                    }
                case .details:
                    if let bucket = vm.chosenBucket {
                        DetailsView(
                            bucket: bucket,
                            friends: vm.friends,
                            selectedFriendIDs: vm.selectedFriendIDs,
                            selectedDateOption: vm.selectedDateOption,
                            onToggleFriend: { vm.toggleFriend($0) },
                            onSelectDate: { vm.selectedDateOption = $0 },
                            onContinue: { Task { await vm.proceedToRanking(userID: appState.currentUser?.id) } }
                        )
                    }
                case .loadingOpponent:
                    VStack {
                        Spacer()
                        ProgressView().tint(CinemaTheme.Colors.gold).scaleEffect(1.3)
                        Spacer()
                    }
                case .compare:
                    if let opponent = vm.opponent, let bucket = vm.chosenBucket {
                        VStack(spacing: 10) {
                            HowWasItSummary(bucket: bucket).padding(.horizontal, 20)
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
                            .frame(maxHeight: .infinity)
                        }
                    }
                case .ranked:
                    RankedResultView(
                        film: film, position: vm.lastPosition, bucketSize: vm.lastBucketSize,
                        bucketLabel: vm.chosenBucket?.label ?? ""
                    ) { dismiss() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CinemaTheme.Colors.background)
        .presentationDetents([.height(380), .height(600), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(CinemaTheme.Colors.background)
        .onChange(of: vm.stage) { _, newStage in
            withAnimation(.easeInOut(duration: 0.3)) { selectedDetent = detent(for: newStage) }
        }
    }

    private func detent(for stage: RankingViewModel.Stage) -> PresentationDetent {
        switch stage {
        case .rate, .ranked: .height(380)
        case .details: .height(600)
        case .loadingOpponent, .compare: .large
        }
    }
}

// MARK: - Sheet Header (persists across every stage)

private struct SheetHeaderRow: View {
    let film: MediaItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: film.posterPath, cornerRadius: 6).frame(width: 36, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(film.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Marked as watched")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(CinemaTheme.Colors.surface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - How Was It (compact summary shown on later stages)

private struct HowWasItSummary: View {
    let bucket: RankBucket

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bucket.color)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text(bucket.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }
}

// MARK: - Rate It (bucket triage)

private struct RateItView: View {
    let onPick: (RankBucket) -> Void
    @State private var selected: RankBucket?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("How was it?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 32)

            HStack(spacing: 0) {
                ForEach(RankBucket.allCases, id: \.self) { bucket in
                    Button {
                        selected = bucket
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPick(bucket) }
                    } label: {
                        VStack(spacing: 10) {
                            Circle()
                                .fill(bucket.color)
                                .frame(width: 64, height: 64)
                                .overlay(Circle().strokeBorder(.white, lineWidth: selected == bucket ? 2 : 0))
                                .scaleEffect(selected == bucket ? 1.08 : 1.0)
                            Text(bucket.label)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .animation(.spring(duration: 0.25), value: selected)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }
}

// MARK: - Details (who with + when — collapses away once ranking starts)

private struct DetailsView: View {
    let bucket: RankBucket
    let friends: [CinemaUser]
    let selectedFriendIDs: Set<UUID>
    let selectedDateOption: RankingViewModel.WatchDateOption
    let onToggleFriend: (UUID) -> Void
    let onSelectDate: (RankingViewModel.WatchDateOption) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HowWasItSummary(bucket: bucket)

            VStack(alignment: .leading, spacing: 10) {
                Text("Who did you watch it with?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if friends.isEmpty {
                    Text("Follow friends to tag them here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(friends) { friend in
                                friendChip(friend)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("When did you watch it?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    ForEach(RankingViewModel.WatchDateOption.allCases, id: \.self) { option in
                        Button { onSelectDate(option) } label: {
                            Text(option.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(selectedDateOption == option ? CinemaTheme.Colors.background : .white.opacity(0.8))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedDateOption == option ? CinemaTheme.Colors.gold : CinemaTheme.Colors.surface)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            Button(action: onContinue) {
                Text("Rank it")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(CinemaTheme.Colors.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private func friendChip(_ friend: CinemaUser) -> some View {
        let selected = selectedFriendIDs.contains(friend.id)
        let initial = (friend.displayName ?? friend.username).first.map(String.init) ?? "?"
        return Button { onToggleFriend(friend.id) } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(CinemaTheme.Colors.surface)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(initial.uppercased())
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().strokeBorder(CinemaTheme.Colors.gold, lineWidth: selected ? 2 : 0))
                Text(friend.displayName ?? friend.username)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Battle View (tap-to-pick duel)

// No "winner" animation — checked how Beli actually handles a pick (real screen
// recording, frame-by-frame): it just cuts straight to the next comparison the
// instant you tap. No slide, no overarch, no lingering celebration per pick.
// A brief press-down on the tapped card is the only feedback before advancing.
private struct BattleView: View {
    let left: MediaItem
    let right: MediaItem
    let bucketColor: Color
    let tooToughAvailable: Bool
    let onPick: (RankingDuelSide) -> Void
    let onTooTough: () -> Void

    @State private var pressedSide: RankingDuelSide?
    @State private var commitTick = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    posterSide(.left, item: left)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                    posterSide(.right, item: right)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                Text("Which do you prefer?")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 8)
                    .opacity(pressedSide == nil ? 1 : 0)
                    .padding(.top, 14)
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
                .opacity(pressedSide == nil ? 1 : 0)
                .padding(.bottom, 20)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: commitTick)
        .id("\(left.id)-\(right.id)")
    }

    @ViewBuilder
    private func posterSide(_ side: RankingDuelSide, item: MediaItem) -> some View {
        RealPosterSide(item: item)
            .frame(maxWidth: .infinity)
            .scaleEffect(pressedSide == side ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressedSide)
            .contentShape(Rectangle())
            .onTapGesture { commit(side) }
    }

    private func commit(_ side: RankingDuelSide) {
        guard pressedSide == nil else { return }
        pressedSide = side
        commitTick += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onPick(side)
        }
    }
}

// Just the card — no title/year underneath. Matches the rest of the app's own
// poster grids (Search dropped captions the same way), and matches how Beli's
// own compare cards carry nothing but the identifying content itself.
private struct RealPosterSide: View {
    let item: MediaItem

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CinemaTheme.Colors.surface

                PosterImage(path: item.posterPath, cornerRadius: 14)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(width: geo.size.width * 0.82)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
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
                .font(.system(size: 44))
                .foregroundStyle(CinemaTheme.Colors.gold)
            Text("\(film.title) ranked!")
                .font(.system(size: 22, weight: .semibold))
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
                    .padding(.vertical, 15)
                    .background(CinemaTheme.Colors.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}
