import SwiftUI

// MARK: - Mock data (isolated prototype — no network calls, no Supabase writes)
//
// v2: two content types instead of one. See Docs/feed-design-spec.md for the
// content model — milestone pops (rank-threshold crossings, broadcast to all
// followers) vs comparison pops (only from new-entrant/stress-test battles,
// never proximity rematches, audience-filtered to followers who've ranked
// either referenced film).
//
// Hand-test on a physical device via Xcode Previews (select the connected
// iPhone as the preview destination) — the milestone success haptic and the
// reaction-tap haptic can't be felt in the simulator.

private struct MockFilm: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let color: Color
}

private enum MilestoneTier {
    case top10Percent
    case top3
    case dethroned

    var caption: (String, String) -> String {
        switch self {
        case .top10Percent: return { name, film in "\(film) just landed in \(name)'s top 10%" }
        case .top3: return { name, film in "\(film) cracked \(name)'s top 3" }
        case .dethroned: return { name, film in "\(name)'s new #1: \(film)" }
        }
    }

    var accentGlow: Bool { self == .dethroned }
    var accentBorder: Bool { self == .top3 || self == .dethroned }
}

extension MilestoneTier: Equatable {}

private enum ComparisonSource {
    case newEntrant, stressTest

    func caption(name: String, film: String, opponent: String) -> String {
        switch self {
        case .newEntrant: return "\(name) is placing \(film) — first look vs \(opponent)"
        case .stressTest: return "\(film) is challenging \(name)'s #1, \(opponent)"
        }
    }
}

private struct MockMilestone: Identifiable {
    let id = UUID()
    let friendName: String
    let film: MockFilm
    let tier: MilestoneTier
    let rankFrom: Int
    let rankTo: Int
}

private struct MockComparison: Identifiable {
    let id = UUID()
    let friendName: String
    let winner: MockFilm
    let loser: MockFilm
    let source: ComparisonSource
    // Prototype-only visibility flag standing in for the real audience-filter
    // query (has the viewer ranked either referenced film?) — see spec §"Audience-targeting logic".
    let viewerEligible: Bool
}

private enum MockPop: Identifiable {
    case milestone(MockMilestone)
    case comparison(MockComparison)

    var id: UUID {
        switch self {
        case .milestone(let m): return m.id
        case .comparison(let c): return c.id
        }
    }
}

private let mockPops: [MockPop] = [
    .milestone(MockMilestone(
        friendName: "Renn", film: MockFilm(title: "Dune", color: Color(red: 0.22, green: 0.17, blue: 0.09)),
        tier: .dethroned, rankFrom: 3, rankTo: 1
    )),
    .comparison(MockComparison(
        friendName: "Maya",
        winner: MockFilm(title: "Whiplash", color: Color(red: 0.12, green: 0.23, blue: 0.22)),
        loser: MockFilm(title: "Birdman", color: Color(red: 0.20, green: 0.14, blue: 0.10)),
        source: .newEntrant, viewerEligible: true
    )),
    .comparison(MockComparison(
        friendName: "Ivy",
        winner: MockFilm(title: "Nightcrawler", color: Color(red: 0.18, green: 0.10, blue: 0.08)),
        loser: MockFilm(title: "Nocturnal Animals", color: Color(red: 0.10, green: 0.10, blue: 0.16)),
        source: .newEntrant, viewerEligible: false // neither film ranked by viewer — hidden
    )),
    .milestone(MockMilestone(
        friendName: "Theo", film: MockFilm(title: "Parasite", color: Color(red: 0.20, green: 0.19, blue: 0.11)),
        tier: .top3, rankFrom: 6, rankTo: 3
    )),
    .comparison(MockComparison(
        friendName: "Theo",
        winner: MockFilm(title: "Everything Everywhere", color: Color(red: 0.10, green: 0.20, blue: 0.18)),
        loser: MockFilm(title: "Parasite", color: Color(red: 0.20, green: 0.19, blue: 0.11)),
        source: .stressTest, viewerEligible: true
    )),
    .milestone(MockMilestone(
        friendName: "Ivy", film: MockFilm(title: "Past Lives", color: Color(red: 0.23, green: 0.14, blue: 0.20)),
        tier: .top10Percent, rankFrom: 14, rankTo: 9
    )),
    .comparison(MockComparison(
        friendName: "Renn",
        winner: MockFilm(title: "The Lighthouse", color: Color(red: 0.17, green: 0.17, blue: 0.19)),
        loser: MockFilm(title: "The Batman", color: Color(red: 0.15, green: 0.15, blue: 0.15)),
        source: .newEntrant, viewerEligible: false // hidden
    )),
]

private let reactionStickers = ["🍿", "🔥", "😭", "🤯"]

// MARK: - FeedPrototypeView

struct FeedPrototypeView: View {
    private var visiblePops: [MockPop] {
        mockPops.filter {
            if case .comparison(let c) = $0 { return c.viewerEligible }
            return true
        }
    }
    private var hiddenCount: Int { mockPops.count - visiblePops.count }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 26) {
                if hiddenCount > 0 {
                    Text("\(hiddenCount) comparison pop\(hiddenCount == 1 ? "" : "s") hidden — you haven't ranked either film (prototype-only debug line)")
                        .font(.system(size: 11))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.6))
                        .padding(.horizontal, CinemaTheme.Spacing.lg)
                        .padding(.top, 8)
                }
                ForEach(visiblePops) { pop in
                    switch pop {
                    case .milestone(let m): MilestonePopCard(pop: m)
                    case .comparison(let c): ComparisonPopCard(pop: c)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(CinemaTheme.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Milestone Pop Card ("ascension")

private struct MilestonePopCard: View {
    let pop: MockMilestone

    @State private var displayedRank: Int
    @State private var posterProgress: CGFloat = 0
    @State private var hasRevealed = false
    @State private var successTick = 0

    private let cardHeight: CGFloat = 240

    init(pop: MockMilestone) {
        self.pop = pop
        _displayedRank = State(initialValue: pop.rankFrom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .bottom, spacing: 14) {
                ladder
                poster
                Spacer(minLength: 0)
                rankBadge
            }
            .frame(height: cardHeight)
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .onAppear(perform: revealOnce)

            HStack(spacing: 10) {
                ForEach(reactionStickers, id: \.self) { emoji in
                    ReactionButton(emoji: emoji)
                }
                Spacer()
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
        }
        .padding(.bottom, 4)
        .sensoryFeedback(.success, trigger: successTick)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CinemaTheme.Colors.gold.opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(pop.friendName.prefix(1)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                )
            Text(pop.tier.caption(pop.friendName, pop.film.title))
                .font(.system(size: 14, weight: pop.tier == .dethroned ? .semibold : .regular))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
    }

    private var ladder: some View {
        GeometryReader { geo in
            let rungCount = 4
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<rungCount, id: \.self) { i in
                    Capsule()
                        .fill(CinemaTheme.Colors.border)
                        .frame(width: 14, height: 2)
                        .offset(y: -geo.size.height * (CGFloat(i) / CGFloat(rungCount - 1)) + 1)
                }
                Circle()
                    .fill(pop.tier.accentGlow ? CinemaTheme.Colors.gold : CinemaTheme.Colors.gold.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .offset(y: -geo.size.height * posterProgress)
            }
        }
        .frame(width: 20)
    }

    private var poster: some View {
        ZStack(alignment: .bottomLeading) {
            pop.film.color
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .center)
            Text(pop.film.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(width: 130)
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                .strokeBorder(CinemaTheme.Colors.gold.opacity(pop.tier.accentBorder ? 0.7 : 0), lineWidth: 2)
        )
        .shadow(color: CinemaTheme.Colors.gold.opacity(pop.tier.accentGlow ? 0.45 * posterProgress : 0), radius: 20)
        .scaleEffect(0.9 + 0.1 * posterProgress)
        .offset(y: 40 * (1 - posterProgress))
        .opacity(0.4 + 0.6 * posterProgress)
    }

    private var rankBadge: some View {
        VStack(spacing: 2) {
            Text("#")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            Text("\(displayedRank)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(pop.tier.accentGlow ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textPrimary)
                .contentTransition(.numericText(value: Double(displayedRank)))
        }
        .padding(.trailing, CinemaTheme.Spacing.sm)
    }

    private func revealOnce() {
        guard !hasRevealed else { return }
        hasRevealed = true
        withAnimation(.spring(duration: 0.7, bounce: 0.28).delay(0.15)) {
            posterProgress = 1
        } completion: {
            successTick += 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
            displayedRank = pop.rankTo
        }
    }
}

// MARK: - Comparison Pop Card (duel reveal — unchanged mechanic, new scoping)

private struct ComparisonPopCard: View {
    let pop: MockComparison

    @State private var revealProgress: CGFloat = 0
    @State private var hasRevealed = false

    private let cardHeight: CGFloat = 210
    private let restingReveal: CGFloat = 0.72

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GeometryReader { geo in
                let halfWidth = geo.size.width / 2
                HStack(spacing: 0) {
                    posterHalf(.left, film: pop.winner, isWinner: true, halfWidth: halfWidth)
                    posterHalf(.right, film: pop.loser, isWinner: false, halfWidth: halfWidth)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
            }
            .frame(height: cardHeight)
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .onAppear(perform: revealOnce)

            HStack(spacing: 10) {
                ForEach(reactionStickers, id: \.self) { emoji in
                    ReactionButton(emoji: emoji)
                }
                Spacer()
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CinemaTheme.Colors.gold.opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(pop.friendName.prefix(1)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                )
            Text(pop.source.caption(name: pop.friendName, film: pop.winner.title, opponent: pop.loser.title))
                .font(.system(size: 14))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
    }

    private func revealOnce() {
        guard !hasRevealed else { return }
        hasRevealed = true
        withAnimation(.spring(duration: 0.6, bounce: 0.22).delay(0.15)) {
            revealProgress = restingReveal
        }
    }

    @ViewBuilder
    private func posterHalf(_ side: RankingDuelSide, film: MockFilm, isWinner: Bool, halfWidth: CGFloat) -> some View {
        let base = ZStack(alignment: .bottomLeading) {
            film.color
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
            Text(film.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .lineLimit(1)
        }
        .frame(width: halfWidth)

        DiagonalOverarchWinEffect.apply(base, .init(
            isWinner: isWinner,
            isLoser: !isWinner,
            side: side,
            progress: revealProgress,
            travel: halfWidth
        ))
    }
}

// MARK: - Reaction Button (unchanged — this mechanic wasn't the complaint)

private struct ReactionButton: View {
    let emoji: String

    @State private var count = 0
    @State private var burstTick = 0
    @State private var riseOffset: CGFloat = 0
    @State private var riseOpacity: Double = 0

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 18))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.06), in: Capsule())

            Text(emoji)
                .font(.system(size: 20))
                .offset(y: riseOffset)
                .opacity(riseOpacity)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: burstTick)
        .onTapGesture(perform: react)
    }

    private func react() {
        withAnimation(.spring(duration: 0.2)) { count += 1 }
        burstTick += 1
        riseOffset = 0
        riseOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            riseOffset = -30
            riseOpacity = 0
        }
    }
}

#Preview {
    FeedPrototypeView()
}
