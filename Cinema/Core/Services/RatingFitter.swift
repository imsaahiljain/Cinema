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

    // MARK: - Order-respecting scores

    // A score band (Liked / Okay / Disliked). `center` is the prior mean for
    // films in the band; a film's final score is kept inside [lower, upper).
    struct Band: Hashable {
        let lower: Double
        let upper: Double
        let center: Double
    }

    // Smallest gap kept between neighbouring films, so sorting by score
    // reproduces `order` exactly instead of leaving ties.
    static let minimumGap: Double = 0.5

    // Scores for every film in `order` (best first) that (1) sort in exactly
    // that order and (2) stay inside each film's band. The Bradley-Terry fit
    // supplies the magnitudes; the order — which binary search placement and
    // manual reordering own — is never up for revision. A film with no duels
    // has no evidence to fit, so it keeps its `currentScores` value.
    static func rate(
        order: [Int],
        currentScores: [Int: Double],
        bands: [Int: Band],
        matches: [Match]
    ) -> [Int: Double] {
        guard !order.isEmpty else { return [:] }

        let fitted = fit(priors: bands.mapValues(\.center), matches: matches)
        var withDuels = Set<Int>()
        for match in matches { withDuels.insert(match.winner); withDuels.insert(match.loser) }

        let target = order.map { id in
            withDuels.contains(id) ? (fitted[id] ?? currentScores[id] ?? 0) : (currentScores[id] ?? fitted[id] ?? 0)
        }

        // Isotonic regression for "strictly descending by at least minimumGap":
        // adding index * gap turns that into plain non-increasing, which
        // pool-adjacent-violators solves exactly.
        let gap = minimumGap
        var h = nonIncreasingFit(target.enumerated().map { $0.element + Double($0.offset) * gap })

        // Clamp each run of same-band films into its band. The clamp bounds are
        // constant within a run and non-increasing across runs, so the order
        // survives; the per-slot offsets keep the gaps strict at the band edge.
        var start = 0
        while start < order.count {
            let band = bands[order[start]]
            var end = start
            while end + 1 < order.count, bands[order[end + 1]] == band { end += 1 }
            if let band {
                let count = Double(end - start + 1)
                let lowerH = band.lower.isFinite ? band.lower + (count - 1 + Double(start)) * gap : -Double.infinity
                let upperH = band.upper.isFinite ? band.upper - gap + Double(start) * gap : Double.infinity
                if lowerH <= upperH {
                    for i in start...end { h[i] = min(max(h[i], lowerH), upperH) }
                }
            }
            start = end + 1
        }

        var result: [Int: Double] = [:]
        for (i, id) in order.enumerated() { result[id] = h[i] - Double(i) * gap }
        return result
    }

    private static func nonIncreasingFit(_ values: [Double]) -> [Double] {
        var blocks: [(sum: Double, count: Int)] = []
        for value in values {
            blocks.append((value, 1))
            while blocks.count > 1 {
                let last = blocks[blocks.count - 1]
                let previous = blocks[blocks.count - 2]
                guard previous.sum / Double(previous.count) < last.sum / Double(last.count) else { break }
                blocks.removeLast(2)
                blocks.append((previous.sum + last.sum, previous.count + last.count))
            }
        }
        return blocks.flatMap { block in Array(repeating: block.sum / Double(block.count), count: block.count) }
    }
}
