import Testing
@testable import Cinema

struct RatingFitterTests {
    private typealias Match = RatingFitter.Match

    @Test func noMatchesLeavesRatingsAtTheirPriors() {
        let fitted = RatingFitter.fit(priors: [1: 1800, 2: 1500], matches: [])
        #expect(fitted[1] == 1800)
        #expect(fitted[2] == 1500)
    }

    @Test func winnerEndsAboveLoserFromEqualPriors() {
        let fitted = RatingFitter.fit(priors: [1: 1500, 2: 1500], matches: [Match(winner: 1, loser: 2)])
        #expect(fitted[1]! > 1500)
        #expect(fitted[2]! < 1500)
    }

    @Test func undefeatedFilmStaysFinite() {
        let matches = (2...6).map { Match(winner: 1, loser: $0) }
        let priors = Dictionary(uniqueKeysWithValues: (1...6).map { ($0, 1500.0) })
        let fitted = RatingFitter.fit(priors: priors, matches: matches)
        #expect(fitted[1]!.isFinite)
        #expect(fitted[1]! < 3000)
    }

    @Test func fitIsOrderIndependentOfMatchLogOrder() {
        let priors: [Int: Double] = [1: 1500, 2: 1500, 3: 1500]
        let matches = [Match(winner: 1, loser: 2), Match(winner: 2, loser: 3), Match(winner: 1, loser: 3)]
        let forward = RatingFitter.fit(priors: priors, matches: matches)
        let backward = RatingFitter.fit(priors: priors, matches: matches.reversed())
        for id in priors.keys { #expect(abs(forward[id]! - backward[id]!) < 1e-6) }
    }

    private let okay = RatingFitter.Band(lower: 1350, upper: 1650, center: 1500)
    private let liked = RatingFitter.Band(lower: 1650, upper: .infinity, center: 1800)
    private let disliked = RatingFitter.Band(lower: -.infinity, upper: 1350, center: 1200)

    // The mismatch this exists to fix: for every landing slot in a 16-film tier,
    // run the binary search RankingViewModel runs, then check the scores sort
    // into exactly the slot the search chose.
    @Test func scoresSortIntoTheBinarySearchSlot() {
        let tierSize = 16
        let newFilm = 100
        let tier = Array(0..<tierSize)
        let history = (0..<(tierSize - 1)).map { Match(winner: tier[$0], loser: tier[$0 + 1]) }

        for trueSlot in 0...tierSize {
            var lo = 0, hi = tierSize
            var matches = history
            while lo < hi {
                let mid = (lo + hi) / 2
                let filmWins = trueSlot <= mid
                matches.append(filmWins ? Match(winner: newFilm, loser: tier[mid]) : Match(winner: tier[mid], loser: newFilm))
                if filmWins { hi = mid } else { lo = mid + 1 }
            }
            #expect(lo == trueSlot)

            var order = tier
            order.insert(newFilm, at: lo)
            let bands = Dictionary(uniqueKeysWithValues: order.map { ($0, okay) })
            let scores = RatingFitter.rate(order: order, currentScores: [:], bands: bands, matches: matches)
            let sorted = scores.sorted { $0.value > $1.value }.map(\.key)
            #expect(sorted == order, "true slot \(trueSlot)")
        }
    }

    @Test func scoresStayInsideEachBand() {
        let order = [1, 2, 3, 4, 5, 6]
        let bands: [Int: RatingFitter.Band] = [1: liked, 2: liked, 3: okay, 4: okay, 5: disliked, 6: disliked]
        let matches = [
            Match(winner: 1, loser: 2), Match(winner: 2, loser: 3), Match(winner: 3, loser: 4),
            Match(winner: 4, loser: 5), Match(winner: 5, loser: 6), Match(winner: 1, loser: 6),
        ]
        let scores = RatingFitter.rate(order: order, currentScores: [:], bands: bands, matches: matches)
        for id in order {
            let band = bands[id]!
            #expect(scores[id]! >= band.lower && scores[id]! < band.upper, "film \(id) score \(scores[id]!)")
        }
        #expect(order.map { scores[$0]! } == order.map { scores[$0]! }.sorted(by: >))
    }

    @Test func duelsThatContradictTheOrderCannotReorderIt() {
        let order = [1, 2, 3]
        let bands = Dictionary(uniqueKeysWithValues: order.map { ($0, okay) })
        let matches = (0..<5).map { _ in Match(winner: 3, loser: 1) }
        let scores = RatingFitter.rate(order: order, currentScores: [:], bands: bands, matches: matches)
        #expect(scores[1]! > scores[2]! && scores[2]! > scores[3]!)
    }

    @Test func filmsWithNoDuelsKeepTheirScore() {
        let order = [1, 2, 3]
        let bands = Dictionary(uniqueKeysWithValues: order.map { ($0, okay) })
        let scores = RatingFitter.rate(
            order: order, currentScores: [1: 1600, 2: 1500, 3: 1400], bands: bands, matches: []
        )
        #expect(scores == [1: 1600, 2: 1500, 3: 1400])
    }
}
