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
}
