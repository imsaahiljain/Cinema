import Foundation

// Bradley-Terry fit over a user's full duel history, as an alternative to
// updating ratings one duel at a time. Sequential ELO only ever moves the two
// films in the latest duel, so a film's score can end up out of step with the
// slot binary search placed it in. Fitting every film to every duel at once
// makes the score a function of the whole history, so the order of the scores
// is the order the duels imply.
//
// Each film gets a Gaussian prior centered on `priors[id]` (its Liked/Okay/
// Disliked seed), which keeps a film that has only won — or has no duels yet —
// at a finite, sensible rating instead of drifting to infinity.
enum RatingFitter {
    struct Match: Hashable {
        let winner: Int
        let loser: Int
    }

    // Prior width in ELO points: one standard deviation of how far the duels are
    // allowed to pull a film away from its seed before the prior pushes back.
    static let defaultPriorSigma: Double = 200

    private static let eloPerNat = 400.0 / log(10.0)

    static func fit(
        priors: [Int: Double],
        matches: [Match],
        priorSigma: Double = defaultPriorSigma,
        maxIterations: Int = 200,
        tolerance: Double = 1e-9
    ) -> [Int: Double] {
        let sigma = priorSigma / eloPerNat
        let priorPrecision = 1.0 / (sigma * sigma)

        let mean = priors.mapValues { $0 / eloPerNat }
        var rating = mean

        var opponents: [Int: [(other: Int, won: Bool)]] = [:]
        for match in matches where priors[match.winner] != nil && priors[match.loser] != nil {
            opponents[match.winner, default: []].append((match.loser, true))
            opponents[match.loser, default: []].append((match.winner, false))
        }

        // Coordinate-wise Newton on a concave objective: every sweep can only
        // raise the log-posterior, so the loop converges rather than oscillates.
        for _ in 0..<maxIterations {
            var largestStep = 0.0
            for id in priors.keys.sorted() {
                guard let games = opponents[id], let current = rating[id], let center = mean[id] else { continue }
                var gradient = -(current - center) * priorPrecision
                var curvature = priorPrecision
                for game in games {
                    let diff = current - (rating[game.other] ?? 0)
                    let pWin = 1.0 / (1.0 + exp(-diff))
                    gradient += (game.won ? 1.0 : 0.0) - pWin
                    curvature += pWin * (1.0 - pWin)
                }
                let step = gradient / curvature
                rating[id] = current + step
                largestStep = max(largestStep, abs(step))
            }
            if largestStep < tolerance { break }
        }

        return rating.mapValues { $0 * eloPerNat }
    }
}
