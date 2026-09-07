import SwiftUI
import Supabase

// MARK: - FeedMarqueeView — "Marquee": warm ticket-stub card feed
//
// Wired to real data: `feed_events` for the users the current user follows
// (via `follows`). Each row is written by RankingView.finish() the moment a
// "This or That" ranking completes (skipped entirely for a private ranking —
// see the comment there). This is the "battle pop" from
// Docs/feed-design-spec.md §3, minus the win-effect replay (still tracked as
// separate, larger work).
//
// Captions, likes, and comments are all real now, not session-local:
// - Caption: the text the user optionally typed on RankingView's result
//   screen, stored on the feed_events row itself. Falls back to an
//   auto-generated "popped [Movie]" only when they left it blank — never
//   shown as if it were their own words.
// - Likes: `pop_likes` (one row per person per pop — toggling is just
//   insert/delete of your own row).
// - Comments: `pop_comments`, read via a sheet (CommentsSheet below) opened
//   from the comment button.
//
// Rating pill is still computed, not editorial: a film's displayed X/10 is
// derived from the poster's rank position within the friend's own ranked
// list (10.0 = their #1, scaling down to their lowest-ranked film) — see
// `ratingOutOf10(rankPosition:totalRanked:)`. Deliberately computed live
// from `ranked_items.elo_score` (same method ListsView already uses) rather
// than trusted from a stored position — see the long comment in
// FeedMarqueeViewModel.load for why `ranked_items.rank_position` isn't safe
// to read directly.

// MARK: - Rating formula

func ratingOutOf10(rankPosition: Int, totalRanked: Int) -> Double {
    guard totalRanked > 1 else { return 10 }
    let fraction = Double(rankPosition - 1) / Double(totalRanked - 1)
    return 10 * (1 - fraction)
}

// MARK: - Relative time label ("2h", "1d", "3w" — matches the design's compact style)

private func relativeTimeLabel(from date: Date) -> String {
    let seconds = max(0, Date.now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m"
    case ..<86400: return "\(Int(seconds / 3600))h"
    case ..<604800: return "\(Int(seconds / 86400))d"
    default: return "\(Int(seconds / 604800))w"
    }
}

// MARK: - Avatar color (deterministic from user id — no per-friend art direction to key off anymore)

private let avatarPalette: [Color] = [
    Color(red: 183 / 255, green: 116 / 255, blue: 61 / 255),
    Color(red: 79 / 255, green: 138 / 255, blue: 198 / 255),
    Color(red: 159 / 255, green: 113 / 255, blue: 180 / 255),
    Color(red: 191 / 255, green: 105 / 255, blue: 106 / 255),
    Color(red: 169 / 255, green: 126 / 255, blue: 44 / 255),
    Color(red: 0 / 255, green: 155 / 255, blue: 149 / 255),
]

private func paletteColor(for userID: UUID) -> Color {
    avatarPalette[abs(userID.uuidString.hashValue) % avatarPalette.count]
}

// Fraction of the card's content width the poster takes up — shared by both
// call sites (the feed list and PopDetailView) so they can't drift apart.
// Sized down from an earlier 0.30: smaller keeps the poster from ever
// needing to grow to chase a tall text column (name row + title + 2-line
// caption + reaction row) — the poster stays fixed either way, so the fix
// for "text taller than the poster" has to come from the text side, and a
// narrower poster hands the text column the extra width it needs for that.
let feedPosterWidthFraction: CGFloat = 0.26

// MARK: - Pop (a real feed_events row, turned into a feed card)

struct FeedPop: Identifiable {
    let id: UUID // feed_events.id
    let friendUserID: UUID
    let friendName: String
    let avatarURL: String?
    let media: MediaItem
    let createdAt: Date
    let rankPosition: Int
    let totalRanked: Int
    let userCaption: String?
    var likeCount: Int
    var isLikedByMe: Bool
    var commentCount: Int

    var avatarColor: Color { paletteColor(for: friendUserID) }
    var timeLabel: String { relativeTimeLabel(from: createdAt) }
    var rating: Double { ratingOutOf10(rankPosition: rankPosition, totalRanked: totalRanked) }
    var ratingLabel: String { String(format: "%.1f", rating) }
    // Docs/feed-design-spec.md §3 tone: present-tense, no forced hype. Only
    // falls back to this when the user skipped writing their own caption.
    var caption: String {
        if let userCaption, !userCaption.isEmpty { return userCaption }
        return "popped \(media.title)"
    }
    // Real signal (genres from the TMDB details already fetched for the
    // poster), not fabricated director/studio flavor text — no extra
    // credits call needed.
    var tags: [String] { Array(media.genreNames.prefix(2)) }
}

struct PopComment: Identifiable {
    let id: UUID
    let userID: UUID
    let authorName: String
    let avatarURL: String?
    let body: String
    let createdAt: Date
}

// MARK: - ViewModel

@Observable
@MainActor
final class FeedMarqueeViewModel {
    var pops: [FeedPop] = []
    var isLoading = false
    var hasLoaded = false
    private var currentUserID: UUID?

    func load(currentUserID: UUID?) async {
        self.currentUserID = currentUserID
        guard let currentUserID else { hasLoaded = true; return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }

        struct FollowEdge: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        guard let edges: [FollowEdge] = try? await SupabaseClient.shared
            .from("follows").select("following_id")
            .eq("follower_id", value: currentUserID)
            .execute().value, !edges.isEmpty else {
            pops = []
            return
        }
        let followingIDs = edges.map(\.followingID)

        struct FeedEvent: Decodable {
            let id: UUID
            let userID: UUID
            let tmdbID: Int
            let mediaType: MediaType
            let caption: String?
            let createdAt: Date
            enum CodingKeys: String, CodingKey {
                case id
                case userID = "user_id"
                case tmdbID = "tmdb_id"
                case mediaType = "media_type"
                case caption
                case createdAt = "created_at"
            }
        }
        guard let events: [FeedEvent] = try? await SupabaseClient.shared
            .from("feed_events").select()
            .in("user_id", values: followingIDs.map(\.uuidString))
            .order("created_at", ascending: false).limit(30)
            .execute().value, !events.isEmpty else {
            pops = []
            return
        }
        let items = Array(events.prefix(20))

        let userIDs = Array(Set(items.map(\.userID)))
        guard let profiles: [CinemaUser] = try? await SupabaseClient.shared
            .from("users").select()
            .in("id", values: userIDs.map(\.uuidString))
            .execute().value else {
            pops = []
            return
        }
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        // `ranked_items.rank_position` looks like the obvious source for this
        // but is stale/unreliable in practice: it's only ever written once,
        // during onboarding (OnboardingView.completeOnboarding) — every later
        // "This or That" duel (RankingView.choose) upserts elo_score alone,
        // which wipes rank_position back to null on conflict (confirmed
        // against the live QA account: 19/19 ranked_items, rank_position
        // null on all of them). The screen that actually shows a working
        // rank — ListsView (My Lists) — never reads that column either; it
        // sorts by elo_score and uses the sorted array's index. Mirroring
        // that same on-the-fly approach here instead of the DB column.
        //
        // Keyed by tmdb_id+media_type (not the ranked_items row id) because a
        // pop references a film by tmdb_id, not by any ranked_items row.
        struct RankRow: Decodable { let tmdbID: Int; let mediaType: MediaType; let eloScore: Double
            enum CodingKeys: String, CodingKey { case tmdbID = "tmdb_id"; case mediaType = "media_type"; case eloScore = "elo_score" }
        }
        var rankByKey: [String: Int] = [:]
        var totalByUser: [UUID: Int] = [:]
        for uid in userIDs {
            let sorted: [RankRow] = (try? await SupabaseClient.shared
                .from("ranked_items").select("tmdb_id,media_type,elo_score").eq("user_id", value: uid)
                .order("elo_score", ascending: false)
                .execute().value) ?? []
            totalByUser[uid] = sorted.count
            for (index, row) in sorted.enumerated() {
                rankByKey["\(uid)-\(row.tmdbID)-\(row.mediaType.rawValue)"] = index + 1
            }
        }
        let totals = totalByUser
        let ranks = rankByKey

        let eventIDs = items.map(\.id)

        struct LikeRow: Decodable { let feedEventID: UUID; let userID: UUID
            enum CodingKeys: String, CodingKey { case feedEventID = "feed_event_id"; case userID = "user_id" }
        }
        let likeRows: [LikeRow] = (try? await SupabaseClient.shared
            .from("pop_likes").select("feed_event_id,user_id")
            .in("feed_event_id", values: eventIDs.map(\.uuidString))
            .execute().value) ?? []
        var likeCounts: [UUID: Int] = [:]
        var likedByMe: Set<UUID> = []
        for row in likeRows {
            likeCounts[row.feedEventID, default: 0] += 1
            if row.userID == currentUserID { likedByMe.insert(row.feedEventID) }
        }

        struct CommentCountRow: Decodable { let feedEventID: UUID
            enum CodingKeys: String, CodingKey { case feedEventID = "feed_event_id" }
        }
        let commentRows: [CommentCountRow] = (try? await SupabaseClient.shared
            .from("pop_comments").select("feed_event_id")
            .in("feed_event_id", values: eventIDs.map(\.uuidString))
            .execute().value) ?? []
        var commentCounts: [UUID: Int] = [:]
        for row in commentRows { commentCounts[row.feedEventID, default: 0] += 1 }
        let likes = likeCounts
        let likedSet = likedByMe
        let comments = commentCounts

        // Fetched concurrently (TMDB detail lookups are the slow part), then
        // reassembled in original most-recent-first order — a TaskGroup
        // doesn't preserve completion order on its own.
        let fetched: [(Int, FeedPop)] = await withTaskGroup(of: (Int, FeedPop?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard let user = profileMap[item.userID],
                          let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType)
                    else { return (index, nil) }
                    let key = "\(item.userID)-\(item.tmdbID)-\(item.mediaType.rawValue)"
                    // If the film has since been removed from the owner's list
                    // (unranked/deleted), it can't have a rank — skip rather
                    // than showing a broken score.
                    guard let rankPosition = ranks[key] else { return (index, nil) }
                    let pop = FeedPop(
                        id: item.id,
                        friendUserID: item.userID,
                        friendName: user.displayName ?? user.username,
                        avatarURL: user.avatarURL,
                        media: media,
                        createdAt: item.createdAt,
                        rankPosition: rankPosition,
                        totalRanked: totals[item.userID] ?? 1,
                        userCaption: item.caption,
                        likeCount: likes[item.id] ?? 0,
                        isLikedByMe: likedSet.contains(item.id),
                        commentCount: comments[item.id] ?? 0
                    )
                    return (index, pop)
                }
            }
            var results: [(Int, FeedPop)] = []
            for await (index, pop) in group {
                if let pop { results.append((index, pop)) }
            }
            return results
        }
        pops = fetched.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // Loads exactly one pop by its feed_events.id, for a permalink-style detail
    // view (e.g. tapping a friend's take on MovieInfoView) rather than the full
    // following-feed batch load above. Mirrors that same load()'s per-item
    // logic (same live-rank-position computation, same "skip if the film's
    // since been unranked" guard) but scoped to a single row.
    func loadSinglePop(feedEventID: UUID, currentUserID: UUID?) async -> FeedPop? {
        self.currentUserID = currentUserID

        struct FeedEventRow: Decodable {
            let id: UUID; let userID: UUID; let tmdbID: Int; let mediaType: MediaType
            let caption: String?; let createdAt: Date
            enum CodingKeys: String, CodingKey {
                case id; case userID = "user_id"; case tmdbID = "tmdb_id"
                case mediaType = "media_type"; case caption; case createdAt = "created_at"
            }
        }
        guard let event: FeedEventRow = try? await SupabaseClient.shared
            .from("feed_events").select()
            .eq("id", value: feedEventID)
            .single().execute().value else { return nil }

        guard let user: CinemaUser = try? await SupabaseClient.shared
            .from("users").select().eq("id", value: event.userID)
            .single().execute().value,
            let media = try? await TMDBClient.shared.details(tmdbID: event.tmdbID, mediaType: event.mediaType)
        else { return nil }

        struct RankRow: Decodable { let tmdbID: Int; let mediaType: MediaType; let eloScore: Double
            enum CodingKeys: String, CodingKey { case tmdbID = "tmdb_id"; case mediaType = "media_type"; case eloScore = "elo_score" }
        }
        let sorted: [RankRow] = (try? await SupabaseClient.shared
            .from("ranked_items").select("tmdb_id,media_type,elo_score").eq("user_id", value: event.userID)
            .order("elo_score", ascending: false)
            .execute().value) ?? []
        // Same "film's since been unranked" guard as the batch load — no
        // rank means nothing honest to show.
        guard let idx = sorted.firstIndex(where: { $0.tmdbID == event.tmdbID && $0.mediaType == event.mediaType }) else { return nil }

        struct LikeRow: Decodable { let userID: UUID
            enum CodingKeys: String, CodingKey { case userID = "user_id" }
        }
        let likeRows: [LikeRow] = (try? await SupabaseClient.shared
            .from("pop_likes").select("user_id").eq("feed_event_id", value: feedEventID)
            .execute().value) ?? []

        struct JustID: Decodable { let id: UUID }
        let commentRows: [JustID] = (try? await SupabaseClient.shared
            .from("pop_comments").select("id").eq("feed_event_id", value: feedEventID)
            .execute().value) ?? []

        let pop = FeedPop(
            id: event.id, friendUserID: event.userID, friendName: user.displayName ?? user.username,
            avatarURL: user.avatarURL, media: media, createdAt: event.createdAt,
            rankPosition: idx + 1, totalRanked: sorted.count, userCaption: event.caption,
            likeCount: likeRows.count, isLikedByMe: likeRows.contains { $0.userID == currentUserID },
            commentCount: commentRows.count
        )
        pops = [pop]
        return pop
    }

    func toggleLike(popID: UUID) async {
        guard let currentUserID, let idx = pops.firstIndex(where: { $0.id == popID }) else { return }
        let wasLiked = pops[idx].isLikedByMe
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
            pops[idx].isLikedByMe.toggle()
            pops[idx].likeCount += wasLiked ? -1 : 1
        }
        do {
            if wasLiked {
                try await SupabaseClient.shared.from("pop_likes")
                    .delete().eq("feed_event_id", value: popID).eq("user_id", value: currentUserID)
                    .execute()
            } else {
                try await SupabaseClient.shared.from("pop_likes")
                    .insert(["feed_event_id": popID.uuidString, "user_id": currentUserID.uuidString])
                    .execute()
            }
        } catch {
            guard let revertIdx = pops.firstIndex(where: { $0.id == popID }) else { return }
            withAnimation {
                pops[revertIdx].isLikedByMe = wasLiked
                pops[revertIdx].likeCount += wasLiked ? 1 : -1
            }
        }
    }

    func loadComments(popID: UUID) async -> [PopComment] {
        struct CommentRow: Decodable {
            let id: UUID; let userID: UUID; let body: String; let createdAt: Date
            enum CodingKeys: String, CodingKey { case id; case userID = "user_id"; case body; case createdAt = "created_at" }
        }
        guard let rows: [CommentRow] = try? await SupabaseClient.shared
            .from("pop_comments").select("id,user_id,body,created_at")
            .eq("feed_event_id", value: popID)
            .order("created_at", ascending: true)
            .execute().value, !rows.isEmpty else { return [] }

        let userIDs = Array(Set(rows.map(\.userID)))
        let profiles: [CinemaUser] = (try? await SupabaseClient.shared
            .from("users").select()
            .in("id", values: userIDs.map(\.uuidString))
            .execute().value) ?? []
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return rows.map { row in
            let user = profileMap[row.userID]
            return PopComment(
                id: row.id, userID: row.userID,
                authorName: user?.displayName ?? user?.username ?? "Someone",
                avatarURL: user?.avatarURL, body: row.body, createdAt: row.createdAt
            )
        }
    }

    func postComment(popID: UUID, body: String, author: CinemaUser) async -> PopComment? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let newID = UUID()
        struct NewComment: Encodable {
            let id: String; let feed_event_id: String; let user_id: String; let body: String
        }
        do {
            try await SupabaseClient.shared.from("pop_comments")
                .insert(NewComment(id: newID.uuidString, feed_event_id: popID.uuidString, user_id: author.id.uuidString, body: trimmed))
                .execute()
        } catch {
            return nil
        }
        if let idx = pops.firstIndex(where: { $0.id == popID }) {
            pops[idx].commentCount += 1
        }
        return PopComment(
            id: newID, userID: author.id,
            authorName: author.displayName ?? author.username,
            avatarURL: author.avatarURL, body: trimmed, createdAt: Date()
        )
    }
}

// MARK: - FeedMarqueeView

struct FeedMarqueeView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = FeedMarqueeViewModel()
    @State private var expandedIDs: Set<UUID> = []
    @State private var selectedFilm: MediaItem?
    @State private var activeCommentsPop: FeedPop?

    var body: some View {
        GeometryReader { screenGeo in
            // Poster size is a fixed fraction of screen width — computed once
            // here, not derived from each card's own text height (see
            // PopCard) — so every card's poster is the same real 2:3 poster
            // shape regardless of how long that pop's title/caption is.
            let cardContentWidth = screenGeo.size.width - 32 // 16pt horizontal padding each side
            let posterWidth = cardContentWidth * feedPosterWidthFraction

            ScrollView {
                // Not pinned: a sticky header here has no divider/shadow of
                // its own, so it just reads as a solid rectangle slicing
                // through whatever card is scrolling underneath it — letting
                // it scroll away with the rest of the content avoids that
                // instead of dressing up a floating-header treatment nothing
                // else in the app uses.
                LazyVStack(spacing: 16) {
                    header
                    if vm.pops.isEmpty && vm.hasLoaded {
                        emptyState
                    } else {
                        ForEach(vm.pops) { pop in
                            PopCard(
                                pop: pop,
                                posterWidth: posterWidth,
                                isExpanded: expandedIDs.contains(pop.id),
                                onExpandTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedIDs.contains(pop.id) {
                                            expandedIDs.remove(pop.id)
                                        } else {
                                            expandedIDs.insert(pop.id)
                                        }
                                    }
                                },
                                onLikeTap: { Task { await vm.toggleLike(popID: pop.id) } },
                                onCommentTap: { activeCommentsPop = pop },
                                onPosterTap: { selectedFilm = pop.media }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(WarmTheme.background.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .sheet(item: $selectedFilm) { film in
            MovieInfoView(film: film)
        }
        .sheet(item: $activeCommentsPop) { pop in
            CommentsSheet(pop: pop, vm: vm, currentUser: appState.currentUser)
        }
        .task { await vm.load(currentUserID: appState.currentUser?.id) }
        .refreshable { await vm.load(currentUserID: appState.currentUser?.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Popcorn")
                .font(WarmTheme.Font.wordmark(30))
                .foregroundStyle(WarmTheme.wordmark)
            Text("What your friends are watching")
                .font(WarmTheme.Font.body(12))
                .foregroundStyle(WarmTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(WarmTheme.background)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No pops yet")
                .font(WarmTheme.Font.wordmarkBold(18))
                .foregroundStyle(WarmTheme.titleText)
            Text("Follow friends to see what they're ranking here.")
                .font(WarmTheme.Font.body(13.5))
                .foregroundStyle(WarmTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }
}

// MARK: - Pop Detail (permalink to one friend's specific post — not their whole profile)
//
// Reached from MovieInfoView's Friends' Takes row: tapping a friend's take opens the actual
// "pop" they posted for that film (poster, caption, like/comment) instead of dumping the user
// on that friend's entire profile grid. Falls back to the profile sheet in MovieInfoView itself
// when the take predates feed_events or was ranked privately (no post exists to open).
struct PopDetailView: View {
    let feedEventID: UUID
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm = FeedMarqueeViewModel()
    @State private var comments: [PopComment] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var draft = ""
    @State private var isPosting = false
    @State private var selectedFilm: MediaItem?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let pop = vm.pops.first(where: { $0.id == feedEventID }) {
                    GeometryReader { geo in
                        let posterWidth = (geo.size.width - 32) * feedPosterWidthFraction
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                PopCard(
                                    pop: pop,
                                    posterWidth: posterWidth,
                                    isExpanded: true,
                                    onExpandTap: {},
                                    onLikeTap: { Task { await vm.toggleLike(popID: pop.id) } },
                                    onCommentTap: {},
                                    onPosterTap: { selectedFilm = pop.media }
                                )
                                commentsSection
                            }
                            .padding(16)
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("This post is gone")
                            .font(WarmTheme.Font.wordmarkBold(18))
                            .foregroundStyle(WarmTheme.titleText)
                        Text("It may have been deleted or unranked.")
                            .font(WarmTheme.Font.body(13.5))
                            .foregroundStyle(WarmTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(WarmTheme.background)
            .navigationTitle("Pop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            let pop = await vm.loadSinglePop(feedEventID: feedEventID, currentUserID: appState.currentUser?.id)
            loadFailed = pop == nil
            isLoading = false
            if let pop { comments = await vm.loadComments(popID: pop.id) }
        }
        .sheet(item: $selectedFilm) { film in
            MovieInfoView(film: film)
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(WarmTheme.Font.bodyBold(15))
                .foregroundStyle(WarmTheme.titleText)

            if comments.isEmpty {
                Text("No comments yet.")
                    .font(WarmTheme.Font.body(13.5))
                    .foregroundStyle(WarmTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Add a comment...", text: $draft)
                    .font(WarmTheme.Font.body(14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(WarmTheme.chipBackground, in: Capsule())
                Button {
                    Task { await postComment() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? WarmTheme.tertiaryText : WarmTheme.accent
                        )
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting || appState.currentUser == nil)
            }
            .padding(.top, 4)
        }
    }

    private func postComment() async {
        guard let currentUser = appState.currentUser, let popID = vm.pops.first?.id else { return }
        let text = draft
        draft = ""
        isPosting = true
        defer { isPosting = false }
        if let comment = await vm.postComment(popID: popID, body: text, author: currentUser) {
            withAnimation { comments.append(comment) }
        } else {
            draft = text
        }
    }
}

// MARK: - Pop Card

private struct PopCard: View {
    let pop: FeedPop
    // Fixed 2:3 poster ratio (TMDB's real ratio), a set width passed down
    // from FeedMarqueeView (same value for every card, proportional to
    // screen width) rather than measured from this card's own text height.
    // That measurement approach — matching the poster to the text column —
    // sounded deterministic but wasn't: real captions and titles vary a lot
    // in how many lines they wrap to, so posters ended up visibly different
    // sizes card to card (a short one-line caption produced a squashed,
    // near-square poster next to a two-line caption's proper tall one).
    // Fixing the poster's own size and letting the text column just be
    // whatever height its own content needs keeps every poster the same
    // real poster shape regardless of what that pop's text looks like.
    let posterWidth: CGFloat
    let isExpanded: Bool
    let onExpandTap: () -> Void
    let onLikeTap: () -> Void
    let onCommentTap: () -> Void
    let onPosterTap: () -> Void

    private var posterHeight: CGFloat { posterWidth * 3 / 2 }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            poster
                .frame(width: posterWidth, height: posterHeight)
                // Own corner radius matching the card's, not just relying on
                // the outer card clip — that only rounds the two corners
                // that happen to sit on the card's own boundary (left side),
                // leaving the right side (against the text column) sharp.
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture(perform: onPosterTap)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    FeedAvatar(name: pop.friendName, urlString: pop.avatarURL, color: pop.avatarColor, size: 22)
                    Text(pop.friendName)
                        .font(WarmTheme.Font.bodyBold(12.5))
                        .foregroundStyle(WarmTheme.nameText)
                    Text("· \(pop.timeLabel)")
                        .font(WarmTheme.Font.body(11.5))
                        .foregroundStyle(WarmTheme.tertiaryText)
                }

                HStack(alignment: .firstTextBaseline) {
                    // Capped to 1 line (was 2) — a title's line count was the
                    // biggest source of the gap below the poster on cards
                    // with a long title: the text column would need more
                    // room than the poster's fixed height, so the card grew
                    // past it and left the poster short of the card's own
                    // bottom edge. A long title just truncates now instead.
                    Text(pop.media.title)
                        .font(WarmTheme.Font.wordmark(19))
                        .foregroundStyle(WarmTheme.titleText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(pop.ratingLabel)
                        .font(WarmTheme.Font.wordmarkBold(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(WarmTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                }

                Text(pop.caption)
                    .font(WarmTheme.Font.body(13.5))
                    .foregroundStyle(WarmTheme.captionText)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded && !pop.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(pop.tags, id: \.self) { tag in
                            Text(tag)
                                .font(WarmTheme.Font.bodySemiBold(11))
                                .foregroundStyle(WarmTheme.tagText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(WarmTheme.tagBackground, in: Capsule())
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Pushes the reaction row to the bottom of the text column
                // instead of sitting right under however tall the caption
                // happens to be — so heart/comment land in the same spot on
                // every card. Only actually pushes anything once the column
                // is given a minimum height to grow into, below.
                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    ReactionButton(
                        outlineSymbol: "heart", filledSymbol: "heart.fill",
                        count: pop.likeCount, isActive: pop.isLikedByMe,
                        activeColor: WarmTheme.accent, onTap: onLikeTap
                    )
                    ReactionButton(
                        outlineSymbol: "bubble.right", filledSymbol: "bubble.right.fill",
                        count: pop.commentCount, isActive: false,
                        activeColor: WarmTheme.accent, onTap: onCommentTap
                    )
                }
            }
            // Matches the poster's own height (minus this column's own
            // vertical padding) as a *minimum* — short text still fills the
            // full poster height so the Spacer above can park the reaction
            // row at the bottom; an expanded card with tags can still grow
            // taller than the poster if it genuinely needs to.
            .frame(minHeight: max(0, posterHeight - 28), alignment: .top)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpandTap)
        }
        .background(WarmTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 60/255, green: 30/255, blue: 10/255).opacity(0.06), radius: 1, x: 0, y: 1)
        .shadow(color: Color(red: 60/255, green: 30/255, blue: 10/255).opacity(0.08), radius: 10, x: 0, y: 6)
    }

    // Real poster from the film's actual tmdb_id — falls back to the
    // striped placeholder (also the loading state) rather than PosterImage's
    // built-in dark-themed placeholder, which would clash with Marquee's
    // warm light palette.
    @ViewBuilder
    private var poster: some View {
        if let path = pop.media.posterPath, let url = TMDBClient.shared.posterURL(path: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    PosterPlaceholder(dark: WarmTheme.tertiaryText, darker: WarmTheme.nameText)
                }
            }
        } else {
            PosterPlaceholder(dark: WarmTheme.tertiaryText, darker: WarmTheme.nameText)
        }
    }
}

// MARK: - Reaction button (native icon, fills with color on tap — not emoji)

private struct ReactionButton: View {
    let outlineSymbol: String
    let filledSymbol: String
    let count: Int
    let isActive: Bool
    let activeColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? filledSymbol : outlineSymbol)
                    .font(.system(size: 14, weight: .regular))
                Text("\(count)")
                    .font(WarmTheme.Font.bodySemiBold(12))
            }
            .foregroundStyle(isActive ? activeColor : WarmTheme.secondaryText)
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
    }
}

// MARK: - Comments sheet

private struct CommentsSheet: View {
    let pop: FeedPop
    let vm: FeedMarqueeViewModel
    let currentUser: CinemaUser?

    @State private var comments: [PopComment] = []
    @State private var isLoading = true
    @State private var draft = ""
    @State private var isPosting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if comments.isEmpty {
                        VStack(spacing: 6) {
                            Text("No comments yet")
                                .font(WarmTheme.Font.bodyBold(14))
                                .foregroundStyle(WarmTheme.titleText)
                            Text("Be the first to say something.")
                                .font(WarmTheme.Font.body(13))
                                .foregroundStyle(WarmTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(comments) { comment in
                                    CommentRow(comment: comment)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    TextField("Add a comment...", text: $draft)
                        .font(WarmTheme.Font.body(14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(WarmTheme.chipBackground, in: Capsule())
                    Button {
                        Task { await post() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? WarmTheme.tertiaryText : WarmTheme.accent
                            )
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting || currentUser == nil)
                }
                .padding(12)
            }
            .background(WarmTheme.background)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            comments = await vm.loadComments(popID: pop.id)
            isLoading = false
        }
    }

    private func post() async {
        guard let currentUser else { return }
        let text = draft
        draft = ""
        isPosting = true
        defer { isPosting = false }
        if let comment = await vm.postComment(popID: pop.id, body: text, author: currentUser) {
            withAnimation { comments.append(comment) }
        } else {
            draft = text // restore on failure so the user doesn't lose what they typed
        }
    }
}

private struct CommentRow: View {
    let comment: PopComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FeedAvatar(name: comment.authorName, urlString: comment.avatarURL, color: paletteColor(for: comment.userID), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(WarmTheme.Font.bodyBold(13))
                        .foregroundStyle(WarmTheme.nameText)
                    Text(relativeTimeLabel(from: comment.createdAt))
                        .font(WarmTheme.Font.body(11))
                        .foregroundStyle(WarmTheme.tertiaryText)
                }
                Text(comment.body)
                    .font(WarmTheme.Font.body(13.5))
                    .foregroundStyle(WarmTheme.captionText)
            }
        }
    }
}

// MARK: - Avatar

private struct FeedAvatar: View {
    let name: String
    let urlString: String?
    let color: Color
    let size: CGFloat

    private var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        initialsFill
                    }
                }
            } else {
                initialsFill
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsFill: some View {
        Circle()
            .fill(color)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

#Preview {
    FeedMarqueeView()
        .environment(AppState())
}
