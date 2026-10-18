import Testing
@testable import Cinema

struct ELOServiceTests {
    private let tolerance = 1e-9

    private let ratingPairs: [(Double, Double)] = [
        (1500, 1500), (1500, 1100), (1100, 1500), (1800, 1200),
        (1200, 1800), (2000, 1000), (1000, 2000), (1523.7, 1488.2),
    ]

    @Test func equalRatingsMoveExactlySixteen() {
        let result = ELOService.newRatings(winnerRating: 1500, loserRating: 1500)
        #expect(abs(result.winner - 1516) < tolerance)
        #expect(abs(result.loser - 1484) < tolerance)
    }

    @Test func updateIsZeroSum() {
        for (winner, loser) in ratingPairs {
            let result = ELOService.newRatings(winnerRating: winner, loserRating: loser)
            let gain = result.winner - winner
            let loss = loser - result.loser
            #expect(abs(gain - loss) < tolerance, "gain \(gain) vs loss \(loss) for \(winner) over \(loser)")
        }
    }

    @Test func expectedScoresSumToOne() {
        for (a, b) in ratingPairs {
            let sum = ELOService.expectedScore(ratingA: a, ratingB: b)
                + ELOService.expectedScore(ratingA: b, ratingB: a)
            #expect(abs(sum - 1.0) < tolerance, "sum \(sum) for \(a) vs \(b)")
        }
    }

    @Test func fourHundredPointFavoriteExpectsAboutNinetyOnePercent() {
        let favorite = ELOService.expectedScore(ratingA: 1900, ratingB: 1500)
        #expect(abs(favorite - 0.909) < 0.001)
    }

    @Test func upsetsMoveMoreThanExpectedWins() {
        let upset = ELOService.newRatings(winnerRating: 1100, loserRating: 1500)
        let expectedWin = ELOService.newRatings(winnerRating: 1500, loserRating: 1100)
        let underdogGain = upset.winner - 1100
        let favoriteGain = expectedWin.winner - 1500
        #expect(underdogGain > favoriteGain)
    }

    @Test func winnerNeverLosesAndLoserNeverGains() {
        for (winner, loser) in ratingPairs {
            let result = ELOService.newRatings(winnerRating: winner, loserRating: loser)
            #expect(result.winner >= winner)
            #expect(result.loser <= loser)
        }
    }
}
