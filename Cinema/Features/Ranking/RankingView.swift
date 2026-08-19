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

    let film: MediaItem
    var stage: Stage = .rate
    var chosenBucket: RankBucket?
    var opponent: MediaItem?
    var overallPosition = 1
    var flavorText = ""
    var captionDraft = ""
    // Only set once `finish()` has written the (non-private) feed_events row for
    // this ranking — postCaption attaches to that specific row rather than
    // guessing at one by tmdb_id, since a private ranking has no row to attach to.
    private var feedEventID: UUID?

    var friends: [CinemaUser] = []
    var selectedFriendIDs: Set<UUID> = []
    var watchedDate: Date = Date()
    var isPrivate = false

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

    // Someone found via search rather than already followed — added to the same
    // chip row, pre-selected, so there's no second UI for "people you searched for".
    func addWatchedWithPerson(_ user: CinemaUser) {
        if !friends.contains(where: { $0.id == user.id }) { friends.append(user) }
        selectedFriendIDs.insert(user.id)
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
            let is_private: Bool
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
                    watched_date: formatter.string(from: watchedDate),
                    is_private: isPrivate
                ),
                onConflict: "user_id,tmdb_id,media_type"
            ).execute()
        } catch {
            Log.ranking.error("Seed upsert failed: \(String(describing: error), privacy: .public)")
        }

        lo = 0; hi = bucketItems.count; comparisonCount = 0
        if bucketItems.isEmpty {
            await finish(userID: userID)
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
            await finish(userID: userID)
        } else {
            await loadOpponent()
        }
    }

    func tooTough(userID: UUID?) async {
        guard tooToughAvailable else { return }
        tooToughTick += 1
        await finish(userID: userID, viaTooTough: true)
    }

    // Position and flavor text deliberately don't mention which bucket this
    // landed in — the bucket is an internal signal for score color-coding on
    // the watched list later, not something to spell out in this moment.
    private func finish(userID: UUID?, viaTooTough: Bool = false) async {
        rankedTick += 1
        let bucketPosition = lo + 1

        var higherBandCount = 0
        if let userID, let bucket = chosenBucket, bucket.upperBound.isFinite {
            struct IDOnly: Decodable { let id: UUID }
            let items: [IDOnly] = (try? await SupabaseClient.shared
                .from("ranked_items").select("id")
                .eq("user_id", value: userID)
                .eq("media_type", value: film.mediaType.rawValue)
                .gte("elo_score", value: bucket.upperBound)
                .execute().value) ?? []
            higherBandCount = items.count
        }
        overallPosition = higherBandCount + bucketPosition

        if viaTooTough {
            flavorText = "Right in the mix."
        } else if bucketItems.isEmpty {
            flavorText = "First one on this list."
        } else if lo < bucketItems.count {
            let neighborItem = bucketItems[lo]
            if let neighbor = try? await TMDBClient.shared.details(tmdbID: neighborItem.tmdbID, mediaType: neighborItem.mediaType) {
                flavorText = "Beat \(neighbor.title) in your rankings."
            } else {
                flavorText = ""
            }
        } else {
            flavorText = ""
        }

        // Every completed ranking is a "pop" — except a private one, which by
        // definition shouldn't post to anyone's feed. feed_events is
        // insert-only (never upserted), so unlike ranked_items it isn't at risk
        // of a later partial upsert silently wiping this row's fields.
        if let userID, !isPrivate {
            let newID = UUID()
            do {
                try await SupabaseClient.shared.from("feed_events").insert([
                    "id": newID.uuidString,
                    "user_id": userID.uuidString,
                    "event_type": "ranked",
                    "tmdb_id": String(film.id),
                    "media_type": film.mediaType.rawValue,
                    "elo_score": String(filmElo),
                    "rank_position": String(overallPosition),
                ]).execute()
                feedEventID = newID
            } catch {
                Log.ranking.error("Feed event insert failed: \(String(describing: error), privacy: .public)")
            }
        }

        stage = .ranked
    }

    // Attaches the caption the user wrote on the result screen to the pop
    // `finish()` already created. A no-op if they left it blank, or if the
    // ranking was private (no feedEventID exists to attach to).
    func postCaption() async {
        let trimmed = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let feedEventID, !trimmed.isEmpty else { return }
        do {
            try await SupabaseClient.shared.from("feed_events")
                .update(["caption": trimmed])
                .eq("id", value: feedEventID)
                .execute()
        } catch {
            Log.ranking.error("Caption post failed: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - RankingView

struct RankingView: View {
    let film: MediaItem
    // Called (in addition to this view's own dismiss) when "Done" is tapped on the
    // result screen — lets a presenter that's itself a modal (MovieInfoView) close
    // too, so finishing a rank returns you to the tab you were on, not the poster.
    var onFinished: (() -> Void)? = nil
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm: RankingViewModel
    @State private var selectedDetent: PresentationDetent = .height(380)

    init(film: MediaItem, onFinished: (() -> Void)? = nil) {
        self.film = film
        self.onFinished = onFinished
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
                            watchedDate: Binding(get: { vm.watchedDate }, set: { vm.watchedDate = $0 }),
                            isPrivate: Binding(get: { vm.isPrivate }, set: { vm.isPrivate = $0 }),
                            onToggleFriend: { vm.toggleFriend($0) },
                            onAddPerson: { vm.addWatchedWithPerson($0) },
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
                                    Task { await vm.tooTough(userID: appState.currentUser?.id) }
                                }
                            )
                            .frame(maxHeight: .infinity)
                        }
                    }
                case .ranked:
                    RankedResultView(
                        film: film, position: vm.overallPosition, flavorText: vm.flavorText,
                        caption: Binding(get: { vm.captionDraft }, set: { vm.captionDraft = $0 })
                    ) {
                        Task { await vm.postCaption() }
                        dismiss()
                        onFinished?()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CinemaTheme.Colors.background)
        .ignoresSafeArea(edges: .bottom)
        .presentationDetents([.height(380), .height(600), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(CinemaTheme.Colors.background)
        // Small custom-height detents default to leaving the presenter still
        // scrollable behind the sheet — that's very likely how a bright provider
        // logo ended up positioned right behind the small "How was it" sheet in
        // the first place. Lock the background while ranking is in progress.
        .presentationBackgroundInteraction(.disabled)
        .onChange(of: vm.stage) { _, newStage in
            withAnimation(.easeInOut(duration: 0.3)) { selectedDetent = detent(for: newStage) }
        }
    }

    private func detent(for stage: RankingViewModel.Stage) -> PresentationDetent {
        switch stage {
        case .rate: .height(380)
        case .ranked: .height(520)
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
    @Binding var watchedDate: Date
    @Binding var isPrivate: Bool
    let onToggleFriend: (UUID) -> Void
    let onAddPerson: (CinemaUser) -> Void
    let onContinue: () -> Void

    @State private var showAddPerson = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HowWasItSummary(bucket: bucket)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Who did you watch it with?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    if !friends.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(friends) { friend in
                                    friendChip(friend)
                                }
                            }
                        }
                    }
                    Button { showAddPerson = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(CinemaTheme.Colors.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    if friends.isEmpty { Spacer() }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Date")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                DatePicker("", selection: $watchedDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .tint(CinemaTheme.Colors.gold)
            }

            HStack(spacing: 10) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stealth mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Keep this private, don't post it")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Toggle("", isOn: $isPrivate)
                    .labelsHidden()
                    .tint(CinemaTheme.Colors.gold)
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
        .sheet(isPresented: $showAddPerson) {
            AddPersonSheet(excludingIDs: Set(friends.map(\.id))) { user in
                onAddPerson(user)
                showAddPerson = false
            }
        }
    }

    private func friendChip(_ friend: CinemaUser) -> some View {
        let selected = selectedFriendIDs.contains(friend.id)
        return Button { onToggleFriend(friend.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "person.circle.fill")
                    .font(.system(size: 15))
                Text(friend.displayName ?? friend.username)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? CinemaTheme.Colors.background : .white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? CinemaTheme.Colors.gold : CinemaTheme.Colors.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Person (search anyone, not just already-followed friends)

private struct AddPersonSheet: View {
    let excludingIDs: Set<UUID>
    let onPick: (CinemaUser) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CinemaUser] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("Search by username...", text: $query)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .tint(CinemaTheme.Colors.gold)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onChange(of: query) { _, _ in onQueryChange() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(CinemaTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer()
                    Text("Search for a username to tag them.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text("No one found for \u{201C}\(query)\u{201D}")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { user in
                                Button {
                                    onPick(user)
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(CinemaTheme.Colors.surface)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Text((user.displayName ?? user.username).prefix(1).uppercased())
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(.white)
                                            )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName ?? user.username)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text("@\(user.username)")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .background(CinemaTheme.Colors.background.ignoresSafeArea())
            .navigationTitle("Add Someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func onQueryChange() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let currentUserID = appState.currentUser?.id
            let matches: [CinemaUser] = (try? await SupabaseClient.shared
                .from("users").select()
                .ilike("username", pattern: "%\(q.lowercased())%")
                .limit(20).execute().value) ?? []
            results = matches.filter { !excludingIDs.contains($0.id) && $0.id != currentUserID }
        }
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
    let flavorText: String
    @Binding var caption: String
    let onDone: () -> Void

    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(CinemaTheme.Colors.gold)
            Text("\(film.title) ranked!")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("#\(position) in your list")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            if !flavorText.isEmpty {
                Text(flavorText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Optional — this is what actually shows on friends' Feed cards
            // instead of an auto-generated "popped [Movie]" line. Skippable:
            // leaving it blank just falls back to that auto caption.
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a caption")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                TextField("What'd you think?", text: $caption, axis: .vertical)
                    .focused($captionFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            Spacer(minLength: 8)
            Button(action: onDone) {
                Text(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Done" : "Post")
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
