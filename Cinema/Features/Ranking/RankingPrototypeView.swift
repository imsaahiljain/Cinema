import SwiftUI

// MARK: - Mock Data

private struct MockFilm: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let color: Color
}

// RankBucket (liked/okay/disliked) now lives in RankingView.swift — the real
// implementation this prototype validated. Reused here rather than duplicated.

private let unratedPool: [MockFilm] = [
    MockFilm(title: "Past Lives", color: Color(red: 0.23, green: 0.14, blue: 0.20)),
    MockFilm(title: "Parasite", color: Color(red: 0.20, green: 0.19, blue: 0.11)),
    MockFilm(title: "Her", color: Color(red: 0.16, green: 0.14, blue: 0.22)),
    MockFilm(title: "The Batman", color: Color(red: 0.15, green: 0.15, blue: 0.15)),
    MockFilm(title: "Dune", color: Color(red: 0.22, green: 0.17, blue: 0.09)),
    MockFilm(title: "Everything Everywhere", color: Color(red: 0.10, green: 0.20, blue: 0.18)),
    MockFilm(title: "The Lighthouse", color: Color(red: 0.17, green: 0.17, blue: 0.19)),
    MockFilm(title: "Call Me by Your Name", color: Color(red: 0.20, green: 0.18, blue: 0.08)),
]

// MARK: - View Model

@Observable
@MainActor
private final class PrototypeViewModel {
    enum Mode { case normal, onboarding }
    enum Stage { case rate, compare, ranked }

    var mode: Mode = .normal
    var stage: Stage = .rate

    var currentNew: MockFilm?
    var chosenBucket: RankBucket?
    var opponent: MockFilm?
    var comparisonCount = 0
    var lastPosition = 1
    var lastBucketSize = 1

    // "Too tough" only makes sense once narrowing has nearly converged — accepting
    // the midpoint early would throw away real information, not just skip a hard call.
    var tooToughAvailable: Bool { chosenBucket != nil && (hi - lo) <= 2 }

    var pickTick = 0
    var rankedTick = 0
    var tooToughTick = 0

    // Onboarding
    var wallLeft: MockFilm?
    var wallRight: MockFilm?
    var wallSeenCount = 0

    private var pool: [MockFilm] = []
    private var buckets: [RankBucket: [MockFilm]] = [.liked: [], .okay: [], .disliked: []]
    private var lo = 0
    private var hi = 0
    private var bucketFilms: [MockFilm] = []

    init() {
        // Seed each bucket with a couple of already-rated mock films so there's
        // something real to compare against, like a user who already has a watched list.
        buckets[.liked] = [
            MockFilm(title: "Whiplash", color: Color(red: 0.12, green: 0.23, blue: 0.22)),
            MockFilm(title: "Moonlight", color: Color(red: 0.10, green: 0.16, blue: 0.24)),
            MockFilm(title: "Spirited Away", color: Color(red: 0.09, green: 0.20, blue: 0.20)),
            MockFilm(title: "No Country for Old Men", color: Color(red: 0.16, green: 0.16, blue: 0.10)),
            MockFilm(title: "The Social Network", color: Color(red: 0.11, green: 0.13, blue: 0.19)),
            MockFilm(title: "Zodiac", color: Color(red: 0.14, green: 0.14, blue: 0.16)),
        ]
        buckets[.okay] = [
            MockFilm(title: "Nightcrawler", color: Color(red: 0.18, green: 0.10, blue: 0.08)),
            MockFilm(title: "Gone Girl", color: Color(red: 0.20, green: 0.17, blue: 0.10)),
            MockFilm(title: "Prisoners", color: Color(red: 0.15, green: 0.15, blue: 0.15)),
        ]
        buckets[.disliked] = [
            MockFilm(title: "Cats", color: Color(red: 0.17, green: 0.17, blue: 0.19)),
            MockFilm(title: "mother!", color: Color(red: 0.21, green: 0.11, blue: 0.09)),
        ]
        pool = unratedPool.shuffled()
        startNextNormal()
        startNextOnboardingPair()
    }

    func startNextNormal() {
        if pool.isEmpty { pool = unratedPool.shuffled() }
        currentNew = pool.removeFirst()
        stage = .rate
        chosenBucket = nil
        comparisonCount = 0
    }

    func chooseBucket(_ bucket: RankBucket) {
        chosenBucket = bucket
        bucketFilms = buckets[bucket] ?? []
        lo = 0
        hi = bucketFilms.count
        comparisonCount = 0
        if bucketFilms.isEmpty {
            finishNormal(position: 1, bucketSize: 1)
        } else {
            stage = .compare
            pickOpponent()
        }
    }

    private func pickOpponent() {
        let idx = min((lo + hi) / 2, bucketFilms.count - 1)
        opponent = bucketFilms[max(0, idx)]
    }

    // newFilmWon: true if the film being added won this comparison
    func choose(newFilmWon: Bool) {
        pickTick += 1
        comparisonCount += 1
        let idx = min((lo + hi) / 2, bucketFilms.count - 1)
        if newFilmWon { hi = idx } else { lo = idx + 1 }
        if lo >= hi || comparisonCount >= 4 {
            finishNormal(position: lo + 1, bucketSize: bucketFilms.count + 1)
        } else {
            pickOpponent()
        }
    }

    func tooTough() {
        guard tooToughAvailable else { return }
        tooToughTick += 1
        let position = (lo + hi) / 2 + 1
        finishNormal(position: position, bucketSize: bucketFilms.count + 1)
    }

    private func finishNormal(position: Int, bucketSize: Int) {
        rankedTick += 1
        if let new = currentNew, let bucket = chosenBucket {
            var films = buckets[bucket] ?? []
            films.insert(new, at: min(position - 1, films.count))
            buckets[bucket] = films
        }
        lastPosition = position
        lastBucketSize = bucketSize
        stage = .ranked
    }

    // MARK: Onboarding

    func startNextOnboardingPair() {
        let shuffled = unratedPool.shuffled()
        wallLeft = shuffled[0]
        wallRight = shuffled[1]
    }

    func onboardingPick() {
        pickTick += 1
        wallSeenCount += 1
        startNextOnboardingPair()
    }

    func onboardingHaventSeen() {
        startNextOnboardingPair()
    }
}

// MARK: - RankingPrototypeView

struct RankingPrototypeView: View {
    @State private var vm = PrototypeViewModel()

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                modeSwitcher
                Group {
                    if vm.mode == .normal {
                        normalFlow
                    } else {
                        onboardingFlow
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: vm.pickTick)
        .sensoryFeedback(.success, trigger: vm.rankedTick)
        .sensoryFeedback(.warning, trigger: vm.tooToughTick)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            modeButton("Normal", .normal)
            modeButton("Onboarding", .onboarding)
        }
        .padding(4)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 10)
    }

    private func modeButton(_ label: String, _ mode: PrototypeViewModel.Mode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { vm.mode = mode }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(vm.mode == mode ? CinemaTheme.Colors.background : CinemaTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(vm.mode == mode ? CinemaTheme.Colors.gold : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    // MARK: Normal flow

    @ViewBuilder
    private var normalFlow: some View {
        switch vm.stage {
        case .rate:
            if let film = vm.currentNew { RateItView(film: film) { vm.chooseBucket($0) } }
        case .compare:
            if let new = vm.currentNew, let opp = vm.opponent, let bucket = vm.chosenBucket {
                CompareView(
                    left: opp, right: new, bucketColor: bucket.color,
                    showHaventSeen: false,
                    tooToughAvailable: vm.tooToughAvailable,
                    onPick: { leftWon in vm.choose(newFilmWon: !leftWon) },
                    onTooTough: vm.tooTough, onHaventSeen: {}
                )
            }
        case .ranked:
            RankedResultView(
                title: vm.currentNew?.title ?? "",
                position: vm.lastPosition, bucketSize: vm.lastBucketSize,
                bucketLabel: vm.chosenBucket?.label ?? ""
            ) { vm.startNextNormal() }
        }
    }

    // MARK: Onboarding flow

    private var onboardingFlow: some View {
        Group {
            if let left = vm.wallLeft, let right = vm.wallRight {
                CompareView(
                    left: left, right: right, bucketColor: CinemaTheme.Colors.gold,
                    showHaventSeen: true,
                    tooToughAvailable: false,
                    onPick: { _ in vm.onboardingPick() },
                    onTooTough: {}, onHaventSeen: vm.onboardingHaventSeen,
                    progressLabel: "\(min(vm.wallSeenCount, 10)) of 10 films ranked"
                )
            }
        }
    }
}

// MARK: - Rate It (bucket triage)

private struct RateItView: View {
    let film: MockFilm
    let onPick: (RankBucket) -> Void
    @State private var selected: RankBucket?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill(film.color).frame(width: 56, height: 84)
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
                                .overlay(
                                    Circle().strokeBorder(.white, lineWidth: selected == bucket ? 2 : 0)
                                )
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

// MARK: - Compare (tap-to-pick duel)

private struct CompareView: View {
    let left: MockFilm
    let right: MockFilm
    let bucketColor: Color
    let showHaventSeen: Bool
    let tooToughAvailable: Bool
    let onPick: (Bool) -> Void  // true = left won
    let onTooTough: () -> Void
    let onHaventSeen: () -> Void
    var progressLabel: String? = nil

    @State private var pulsedSide: RankingDuelSide?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    card(left, side: .left, height: geo.size.height)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                    card(right, side: .right, height: geo.size.height)
                }

                VStack(spacing: 4) {
                    if let progressLabel {
                        Text(progressLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text("Which do you prefer?")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.7), radius: 8)
                .padding(.top, 22)
                .frame(maxHeight: .infinity, alignment: .top)

                if showHaventSeen {
                    Button(action: onHaventSeen) {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                            Text("I haven't seen one of these")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.3)))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
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
                    .padding(.bottom, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func card(_ film: MockFilm, side: RankingDuelSide, height: CGFloat) -> some View {
        Button {
            pulsedSide = side
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onPick(side == .left)
            }
        } label: {
            ZStack(alignment: .bottom) {
                film.color
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                Text(film.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(
                Rectangle().strokeBorder(pulsedSide == side ? bucketColor : Color.clear, lineWidth: 3)
            )
            .scaleEffect(pulsedSide == side ? 1.02 : 1.0)
            .brightness(pulsedSide == side ? 0.06 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: pulsedSide)
    }
}

// MARK: - Ranked Result

private struct RankedResultView: View {
    let title: String
    let position: Int
    let bucketSize: Int
    let bucketLabel: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(CinemaTheme.Colors.gold)
            Text("\(title) ranked!")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
            Text("#\(position) of \(bucketSize) in \"\(bucketLabel)\"")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button(action: onContinue) {
                Text("Rate another")
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

#Preview {
    RankingPrototypeView()
}
