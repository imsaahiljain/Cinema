import SwiftUI
import Supabase

// MARK: - FeedMarqueeView — "Marquee": warm ticket-stub card feed
//
// Wired to real data: `ranked_items` for the users the current user follows
// (via `follows`), most-recently-updated first — same pattern already proven
// in DiscoverView.loadSocial and ProfileViewModel.loadRecentActivity. There
// is no `feed_events` table wired up yet (it exists in Docs/schema.sql but
// nothing writes to it) — see FeedMarqueeViewModel.load for why this reuses
// `ranked_items` instead.
//
// Two real gaps, solved rather than papered over:
// - No public-caption field exists on a ranking event, and `film_notes` is a
//   private per-user table (RLS-restricted to its owner) — showing it in a
//   friend's feed would leak private data. Captions are auto-generated
//   instead, following Docs/feed-design-spec.md §3's tone rules ("popped
//   [Movie]" — present-tense, no "review"/"rating" language).
// - No likes/comments schema exists yet either. Reaction counts are kept
//   exactly as session-local UI state (matches the mock's prior behavior) —
//   nothing is persisted, and counts reset to 0 on every load rather than
//   faking a baseline.
//
// Rating pill is computed, not editorial: a film's displayed X/10 is
// derived from the poster's rank position within the friend's own ranked
// list (10.0 = their #1, scaling down to their lowest-ranked film) — see
// `ratingOutOf10(rankPosition:totalRanked:)`.

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

// MARK: - Pop (a real friend's ranked-item, turned into a feed card)

struct FeedPop: Identifiable {
    let id: UUID
    let friendUserID: UUID
    let friendName: String
    let avatarURL: String?
    let media: MediaItem
    let updatedAt: Date
    let rankPosition: Int
    let totalRanked: Int

    var avatarColor: Color { paletteColor(for: friendUserID) }
    var timeLabel: String { relativeTimeLabel(from: updatedAt) }
    var rating: Double { ratingOutOf10(rankPosition: rankPosition, totalRanked: totalRanked) }
    var ratingLabel: String { String(format: "%.1f", rating) }
    // Docs/feed-design-spec.md §3: "popped [Movie]" — present-tense, no forced
    // hype, never "review"/"rating" in pop copy.
    var caption: String { "popped \(media.title)" }
    // Real signal (genres from the TMDB details already fetched for the
    // poster), not fabricated director/studio flavor text — no extra
    // credits call needed.
    var tags: [String] { Array(media.genreNames.prefix(2)) }
}

// MARK: - ViewModel

@Observable
@MainActor
final class FeedMarqueeViewModel {
    var pops: [FeedPop] = []
    var isLoading = false
    var hasLoaded = false

    func load(currentUserID: UUID?) async {
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

        guard let recent: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items").select()
            .in("user_id", values: followingIDs.map(\.uuidString))
            .order("updated_at", ascending: false).limit(30)
            .execute().value, !recent.isEmpty else {
            pops = []
            return
        }
        let items = Array(recent.prefix(20))

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
        struct RankRow: Decodable { let id: UUID; let eloScore: Double
            enum CodingKeys: String, CodingKey { case id; case eloScore = "elo_score" }
        }
        var rankByItemID: [UUID: Int] = [:]
        var totalByUser: [UUID: Int] = [:]
        for uid in userIDs {
            let sorted: [RankRow] = (try? await SupabaseClient.shared
                .from("ranked_items").select("id,elo_score").eq("user_id", value: uid)
                .order("elo_score", ascending: false)
                .execute().value) ?? []
            totalByUser[uid] = sorted.count
            for (index, row) in sorted.enumerated() {
                rankByItemID[row.id] = index + 1
            }
        }
        let rankByItem = rankByItemID
        let totals = totalByUser

        // Fetched concurrently (TMDB detail lookups are the slow part), then
        // reassembled in original most-recent-first order — a TaskGroup
        // doesn't preserve completion order on its own.
        let fetched: [(Int, FeedPop)] = await withTaskGroup(of: (Int, FeedPop?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard let user = profileMap[item.userID],
                          let rankPosition = rankByItem[item.id],
                          let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType)
                    else { return (index, nil) }
                    let pop = FeedPop(
                        id: item.id,
                        friendUserID: item.userID,
                        friendName: user.displayName ?? user.username,
                        avatarURL: user.avatarURL,
                        media: media,
                        updatedAt: item.updatedAt,
                        rankPosition: rankPosition,
                        totalRanked: totals[item.userID] ?? 1
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
}

// MARK: - FeedMarqueeView

struct FeedMarqueeView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = FeedMarqueeViewModel()
    @State private var expandedIDs: Set<UUID> = []
    @State private var likedIDs: Set<UUID> = []
    @State private var selectedFilm: MediaItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    if vm.pops.isEmpty && vm.hasLoaded {
                        emptyState
                    } else {
                        ForEach(vm.pops) { pop in
                            PopCard(
                                pop: pop,
                                isExpanded: expandedIDs.contains(pop.id),
                                isLiked: likedIDs.contains(pop.id),
                                onExpandTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedIDs.contains(pop.id) {
                                            expandedIDs.remove(pop.id)
                                        } else {
                                            expandedIDs.insert(pop.id)
                                        }
                                    }
                                },
                                onLikeTap: {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                                        if likedIDs.contains(pop.id) {
                                            likedIDs.remove(pop.id)
                                        } else {
                                            likedIDs.insert(pop.id)
                                        }
                                    }
                                },
                                onPosterTap: { selectedFilm = pop.media }
                            )
                        }
                    }
                } header: {
                    header
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(WarmTheme.background.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .sheet(item: $selectedFilm) { film in
            MovieInfoView(film: film)
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

// MARK: - Pop Card

private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PopCard: View {
    let pop: FeedPop
    let isExpanded: Bool
    let isLiked: Bool
    let onExpandTap: () -> Void
    let onLikeTap: () -> Void
    let onPosterTap: () -> Void

    // Measured from the text column so the poster can match it exactly —
    // an aspectRatio+maxHeight negotiation between two HStack children
    // with no other anchor produced an oversized, ambiguous row height
    // (dead white space below the text). A real measurement is
    // deterministic instead.
    @State private var contentHeight: CGFloat = 190

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Per the design spec: fixed 2:3 poster ratio (TMDB's real
            // ratio), spanning the full card height — width is derived
            // from that height, not fixed, so it's a tall narrow rectangle
            // that never needs to crop the image to fit.
            poster
                .frame(width: contentHeight * 2 / 3, height: contentHeight)
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
                    Text(pop.media.title)
                        .font(WarmTheme.Font.wordmark(19))
                        .foregroundStyle(WarmTheme.titleText)
                        .lineLimit(2)
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

                HStack(spacing: 16) {
                    // Reaction counts are session-local only — no likes/comments
                    // schema exists yet, so nothing here persists across a
                    // relaunch or is visible to anyone else. Starts at 0 rather
                    // than faking a baseline count.
                    ReactionButton(
                        outlineSymbol: "heart", filledSymbol: "heart.fill",
                        count: isLiked ? 1 : 0, isActive: isLiked,
                        activeColor: WarmTheme.accent, onTap: onLikeTap
                    )
                    ReactionButton(
                        outlineSymbol: "bubble.right", filledSymbol: "bubble.right.fill",
                        count: 0, isActive: false,
                        activeColor: WarmTheme.accent, onTap: {}
                    )
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                }
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpandTap)
        }
        .background(WarmTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 60/255, green: 30/255, blue: 10/255).opacity(0.06), radius: 1, x: 0, y: 1)
        .shadow(color: Color(red: 60/255, green: 30/255, blue: 10/255).opacity(0.08), radius: 10, x: 0, y: 6)
        .onPreferenceChange(CardHeightKey.self) { newHeight in
            if newHeight > 0 { contentHeight = newHeight }
        }
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
