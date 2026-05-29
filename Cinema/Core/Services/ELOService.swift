import Foundation

enum ELOService {
    static let kFactor: Double = 32

    static func expectedScore(ratingA: Double, ratingB: Double) -> Double {
        1.0 / (1.0 + pow(10.0, (ratingB - ratingA) / 400.0))
    }

    static func newRatings(winnerRating: Double, loserRating: Double) -> (winner: Double, loser: Double) {
        let expectedWinner = expectedScore(ratingA: winnerRating, ratingB: loserRating)
        let expectedLoser = expectedScore(ratingA: loserRating, ratingB: winnerRating)
        let newWinner = winnerRating + kFactor * (1.0 - expectedWinner)
        let newLoser = loserRating + kFactor * (0.0 - expectedLoser)
        return (winner: newWinner, loser: newLoser)
    }
}
