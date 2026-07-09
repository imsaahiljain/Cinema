import SwiftUI

enum RankingDuelSide: Equatable {
    case left, right
}

/// One of several planned win animations for the This or That swipe duel — the
/// winning poster slides diagonally across and overarches (visually covers) the
/// losing one. Saved here as-is (rather than left inline) so the eventual
/// "multiple winning animations" rotation feature (see CLAUDE.md's
/// Post-Production Backlog) can add sibling effects next to this one and pick
/// between them per battle, instead of reconstructing this from scratch.
enum DiagonalOverarchWinEffect {
    struct Params {
        let isWinner: Bool
        let isLoser: Bool
        let side: RankingDuelSide
        let progress: CGFloat
        let travel: CGFloat
    }

    // Winner travels toward the loser's side but caps short of fully replacing
    // it. Each side panel is itself `travel` (half the screen) wide, so an
    // offset of `travel * fraction` lands the panel's far edge at the
    // (50 + 50*fraction)% mark of the full screen — 0.5 here means a full
    // swipe stops at the 75% mark, leaving the loser's back quarter visible.
    private static let maxTravelFraction: CGFloat = 0.5

    @ViewBuilder
    static func apply<Content: View>(_ content: Content, _ p: Params) -> some View {
        let maxOffset = p.travel * maxTravelFraction

        content
            .scaleEffect(p.isWinner ? 1 + p.progress * 0.1 : (p.isLoser ? 1 - p.progress * 0.05 : 1))
            .brightness(p.isWinner ? p.progress * 0.06 : 0)
            .opacity(p.isLoser ? 1 - p.progress * 0.35 : 1)
            .rotationEffect(.degrees(p.isWinner ? (p.side == .left ? p.progress * 6 : -p.progress * 6) : 0))
            .offset(
                x: p.isWinner ? (p.side == .left ? p.progress * maxOffset : -p.progress * maxOffset) : 0,
                y: p.isWinner ? -p.progress * 14 : 0
            )
            .shadow(color: .black.opacity(p.isWinner ? p.progress * 0.5 : 0), radius: 16, x: 0, y: 8)
            .zIndex(p.isWinner ? 2 : (p.isLoser ? 0 : 1))
    }
}
