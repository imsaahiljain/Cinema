import SwiftUI

private struct MockFilm: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let year: String
    let color: Color
}

private let mockFilmPool: [MockFilm] = [
    MockFilm(title: "Past Lives", year: "2023", color: Color(red: 0.23, green: 0.14, blue: 0.20)),
    MockFilm(title: "Whiplash", year: "2014", color: Color(red: 0.12, green: 0.23, blue: 0.22)),
    MockFilm(title: "Parasite", year: "2019", color: Color(red: 0.20, green: 0.19, blue: 0.11)),
    MockFilm(title: "Her", year: "2013", color: Color(red: 0.16, green: 0.14, blue: 0.22)),
    MockFilm(title: "Moonlight", year: "2016", color: Color(red: 0.10, green: 0.16, blue: 0.24)),
    MockFilm(title: "The Batman", year: "2022", color: Color(red: 0.15, green: 0.15, blue: 0.15)),
    MockFilm(title: "Dune", year: "2021", color: Color(red: 0.22, green: 0.17, blue: 0.09)),
    MockFilm(title: "Portrait of a Lady on Fire", year: "2019", color: Color(red: 0.22, green: 0.10, blue: 0.10)),
    MockFilm(title: "Everything Everywhere", year: "2022", color: Color(red: 0.10, green: 0.20, blue: 0.18)),
    MockFilm(title: "The Lighthouse", year: "2019", color: Color(red: 0.17, green: 0.17, blue: 0.19)),
    MockFilm(title: "Call Me by Your Name", year: "2017", color: Color(red: 0.20, green: 0.18, blue: 0.08)),
    MockFilm(title: "Nightcrawler", year: "2014", color: Color(red: 0.18, green: 0.10, blue: 0.08)),
]

@Observable
@MainActor
private final class PrototypeViewModel {
    var left: MockFilm = mockFilmPool[0]
    var right: MockFilm = mockFilmPool[1]
    var upNext: MockFilm = mockFilmPool[2]
    var collected: [MockFilm] = []
    var totalBattles = 0

    private var pool: [MockFilm] = []

    init() {
        reset()
    }

    // Reshuffles when the pool runs dry, so `avoiding` guards against the
    // fresh shuffle coincidentally handing back a film already on screen
    // (otherwise a film could occasionally end up facing itself).
    private static func draw(_ pool: inout [MockFilm], avoiding: Set<UUID> = []) -> MockFilm {
        if pool.isEmpty { pool = mockFilmPool.shuffled() }
        if let index = pool.firstIndex(where: { !avoiding.contains($0.id) }) {
            return pool.remove(at: index)
        }
        return pool.removeFirst()
    }

    func commit(_ side: RankingDuelSide) {
        totalBattles += 1
        let winner = side == .left ? left : right
        collected.append(winner)
        if collected.count > 8 { collected.removeFirst() }
        if side == .left {
            right = upNext
        } else {
            left = upNext
        }
        upNext = Self.draw(&pool, avoiding: [left.id, right.id])
    }

    func reset() {
        pool = mockFilmPool.shuffled()
        left = Self.draw(&pool)
        right = Self.draw(&pool, avoiding: [left.id])
        upNext = Self.draw(&pool, avoiding: [left.id, right.id])
        collected = []
        totalBattles = 0
    }
}

// MARK: - RankingPrototypeView

struct RankingPrototypeView: View {
    @State private var vm = PrototypeViewModel()
    @State private var dragTranslation: CGFloat = 0
    @State private var winnerStartSide: RankingDuelSide?
    @State private var thresholdCrossed = false
    @State private var pulseSide: RankingDuelSide?

    private let commitProgress: CGFloat = 0.6

    var body: some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width / 2
            let progress = revealProgress(travel: halfWidth)

            ZStack {
                CinemaTheme.Colors.background.ignoresSafeArea()

                HStack(spacing: 0) {
                    posterSide(.left, geo: geo, progress: progress, travel: halfWidth)
                    posterSide(.right, geo: geo, progress: progress, travel: halfWidth)
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

                VStack {
                    topBar
                    Spacer()
                    collectionStrip
                        .padding(.bottom, 20)
                }
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
        .sensoryFeedback(.impact(weight: .medium), trigger: vm.totalBattles)
    }

    private func revealProgress(travel: CGFloat) -> CGFloat {
        guard let winnerStartSide else { return 0 }
        let signed = winnerStartSide == .left ? dragTranslation : -dragTranslation
        return max(0, min(1, signed / travel))
    }

    @ViewBuilder
    private func posterSide(_ side: RankingDuelSide, geo: GeometryProxy, progress: CGFloat, travel: CGFloat) -> some View {
        let film = side == .left ? vm.left : vm.right
        let isWinner = winnerStartSide == side
        let isLoser = winnerStartSide != nil && winnerStartSide != side

        let base = PrototypePosterSide(film: film, isPulsing: pulseSide == side)
            .id(film.id)
            .frame(width: geo.size.width / 2)
            .transition(.asymmetric(
                insertion: .move(edge: side == .left ? .leading : .trailing).combined(with: .opacity),
                removal: .move(edge: side == .left ? .leading : .trailing).combined(with: .opacity)
            ))

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
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            vm.commit(side)
            dragTranslation = 0
        }
        thresholdCrossed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pulseSide = nil
            winnerStartSide = nil
        }
    }

    private var topBar: some View {
        HStack {
            Button { vm.reset() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            Spacer()
            Text("This or that")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
            Spacer()
            Text("\(vm.totalBattles)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private var collectionStrip: some View {
        HStack(spacing: -14) {
            ForEach(Array(vm.collected.enumerated()), id: \.element.id) { index, film in
                RoundedRectangle(cornerRadius: 5)
                    .fill(film.color)
                    .frame(width: 26, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(
                                index == vm.collected.count - 1
                                    ? CinemaTheme.Colors.gold
                                    : Color.white.opacity(0.2),
                                lineWidth: index == vm.collected.count - 1 ? 1.5 : 1
                            )
                    )
                    .rotationEffect(.degrees(Double(index - vm.collected.count / 2) * 4))
                    .scaleEffect(index == vm.collected.count - 1 ? 1.08 : 1.0)
            }
        }
        .animation(.spring(duration: 0.4), value: vm.collected.count)
    }
}

// MARK: - Poster Side

private struct PrototypePosterSide: View {
    let film: MockFilm
    let isPulsing: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                film.color.opacity(0.7)

                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(film.color)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.25))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: geo.size.width * 0.62, height: geo.size.width * 0.62 * 1.5)

                    VStack(spacing: 2) {
                        Text(film.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                        Text(film.year)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(CinemaTheme.Colors.gold.opacity(isPulsing ? 0.9 : 0), lineWidth: 3)
        )
        .scaleEffect(isPulsing ? 1.02 : 1.0)
        .animation(.spring(duration: 0.3), value: isPulsing)
    }
}

#Preview {
    RankingPrototypeView()
}
