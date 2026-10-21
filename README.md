# Popcorn

A social app for movie taste: rank films by picking between two at a time, build a personal ranked list, and see what your friends are watching. Think Beli, but for film.

> **Status:** in development, not launched. It runs on the iOS Simulator and on a physical device; there is no App Store build, and the social features run against a small seeded backend.

<p>
  <img src="Docs/screenshots/feed.png" width="240" alt="Friends feed">
  <img src="Docs/screenshots/rankings.png" width="240" alt="Ranked list with scores">
  <img src="Docs/screenshots/discover.png" width="240" alt="Discover">
</p>

## Tech stack

- **iOS app:** SwiftUI, `@Observable` MVVM, async/await, iOS 26 (Liquid Glass), Swift Package Manager only
- **Backend:** Supabase: Postgres, Auth, Row Level Security, Realtime
- **Movie data:** [TMDB API](https://www.themoviedb.org/) (metadata is fetched live, never stored)
- **Tests:** Swift Testing unit tests for the ranking math (`CinemaTests/`), XCUITest for gesture checks
- **Tooling:** XcodeGen (`project.yml` generates `Cinema.xcodeproj`)

The Xcode project, scheme and bundle ID say `Cinema` (the original working name). The product name is Popcorn.

## How ranking works

There are no star ratings. A film's place in your list comes from head-to-head choices.

1. **Tier selection.** After you add a film you say whether you *liked it*, *it was fine*, or *didn't like it*. Each tier is an ELO band (liked ≥ 1650, fine 1350–1650, disliked < 1350) and seeds the film's starting score.
2. **Binary search placement.** The new film is dueled against films already in that tier. Each pick halves the range of slots it could belong in, so a list of *n* films needs about log₂ *n* duels to find the exact position. (`RankingView.swift`)
3. **Bradley-Terry refit.** Updating one duel at a time leaves scores out of step with the placement the search found. Instead, `RatingFitter.fit` fits every film to the whole duel history at once (a Bradley-Terry model with a Gaussian prior on each film's tier seed, solved by coordinate-wise Newton steps). The result doesn't depend on the order duels were played in.
4. **Isotonic regression.** The refit supplies score *magnitudes*, but the *order* belongs to binary search (and manual reordering). `RatingFitter.rate` uses pool-adjacent-violators to adjust the fitted scores so they sort in exactly that order, then clamps each film into its tier's band.

**Example.** You rank four liked films A > B > C > D and then add E. Binary search slots E between B and C. Suppose the fit gives B ≈ 1810, E ≈ 1835, C ≈ 1790. E scores higher than B, which contradicts the slot. Isotonic regression pools B and E and sets them to roughly their average (about 1822), then separates them by a minimum 0.5-point gap so the order is B > E > C. The scores stay close to what the duels implied, and the order matches the slot binary search chose.

Code: [`RatingFitter.swift`](Cinema/Core/Services/RatingFitter.swift). Tests: [`RatingFitterTests.swift`](CinemaTests/RatingFitterTests.swift), which cover:
- scores sorting into the binary-search slot
- scores staying inside their band
- contradictory duels not reordering the list
- fit results independent of match-log order
- undefeated films staying finite

## Data integrity

Each duel in the ranking flow writes a match row and updates two scores through one Postgres function, [`record_duel`](Docs/schema.sql). A single duel is designed not to half-apply or double-apply (a whole ranking is several requests; see Known limitations):

- **Atomic.** The match insert and both `ranked_items` upserts run in one function body, so they commit or fail together.
- **Idempotent.** The client generates a UUID per duel and sends it as `p_match_id`. If that match already exists, the insert is skipped via `on conflict (id) do nothing` and the function returns `false`. Re-sending a duel with the same `p_match_id` doesn't apply it twice.
- **RLS enforced.** The function is `security invoker`, so Row Level Security stays in force. The user is always `auth.uid()` and never a parameter, and execute is granted only to `authenticated`.

## Known limitations

Found by auditing the ranking code paths. None are fixed yet. File references are to `RankingView.swift` unless noted.

1. **A failed duel save has no working retry.** If `record_duel` errors (including a lost response after the server committed), `choose` (L210–254) shows "Pick not saved" and keeps the pending `p_match_id`, but `BattleView.pressedSide` is never reset (L894, L944–951), so the pick screen ignores further taps and the sheet has to be dismissed. The ID-reuse logic is unreachable from the UI, a new `RankingViewModel` generates new IDs, and a duel that did commit stays in `elo_matches` with no refit and no feed post. Fix: clear `pressedSide` on error and derive the idempotency key from (film, opponent).
2. **A ranking is several requests, not one transaction.** The seed upsert (L177), each `record_duel`, the score refit (L334) and the `feed_events` insert (L311) are separate calls. Seed, refit and feed failures are only logged and the result screen still shows "ranked!". List order is a sort on `elo_score`, so a failed refit leaves sequential-ELO scores that can put the film somewhere other than the "#N" shown; a failed seed now stops the ranking with an error instead of letting `record_duel` create the row with column defaults. Fix: one server-side function that does the refit and all writes in a transaction.
3. **Two devices ranking at once can overwrite each other.** Each device reads `ranked_items` once (L150) and later writes absolute scores for every film in that snapshot (L360), with no version check or row lock, so the last writer wins and a stale snapshot can shift a film the other device just placed. Fix: do placement and refit in a SQL function that locks the user's rows.
4. **The server stores client-computed values unchecked.** `record_duel` accepts the before/after scores, winner flag and both TMDB IDs as sent: it doesn't verify the scores follow from the ELO formula, that the two IDs differ, or that the opponent is already ranked (it upserts it). Impact is confined to the caller's own list and feed, since RLS already lets a user write their own `ranked_items` rows directly. Fix: read current scores in SQL and compute the update there.
5. **Placement order is locked.** `RatingFitter.rate` takes the order from binary search and never revises it (`duelsThatContradictTheOrderCannotReorderIt`). A later duel that contradicts an earlier placement only pools the two scores to within 0.5 points, and "Too tough" accepts the midpoint. Fix: a re-place flow triggered when contradicting duels accumulate.
6. **Refit cost grows with history and runs on the main thread.** Each ranking pages the user's entire `elo_matches` log (L371, 1,000 rows per sequential request) before the result screen appears, runs up to 200 sweeps over it in `RatingFitter.fit` inside a `@MainActor` view model (L64), and upserts every film whose score moved more than 0.001, potentially the whole list. Not measured; fine at tens of films. The `ranked_items` read at L150 is unpaged despite the 1,000-row cap noted at L370. Fix: fit off the main actor and incrementally, or server-side.
7. **Tests cover only the math.** `RatingFitterTests` and `ELOServiceTests` are the only unit tests. Nothing exercises `record_duel` (idempotency, atomicity, RLS), `RankingViewModel` (retry paths, cross-tier position math; the slot test uses one band), `loadMatches` paging, or refit-then-write. Fix: SQL-level tests for the function and an injectable client for the view model.
8. **Docs drift.** Onboarding wall duels bypass `record_duel` and `elo_matches`: `completeOnboarding` upserts rows one by one, logs failures and still completes. `CLAUDE.md` still describes stored scores as K=32 ELO and cites `RankingViewModel.selectPair`, which doesn't exist. A comment in `FeedMarqueeView.swift` (L189–198) blames `choose` upserting `elo_score` directly, which `record_duel` replaced.

## How it's built

I designed and directed Popcorn, and built it with [Claude Code](https://claude.com/claude-code) as the implementation partner. I made the product decisions (the ranking model, the tier-then-duel flow, what the app should and shouldn't do), reviewed and tested each feature in the simulator and on my own phone, and steered the design through many rounds of feedback. [`CLAUDE.md`](CLAUDE.md) is the engineering spec that kept the work consistent: architecture, product rules, conventions, and a one-feature-at-a-time workflow with a build and verify step before anything is committed.

## Setup

Requires Xcode 26+ and an iOS 26 simulator.

1. Clone the repo.
2. Create `Cinema/Core/Network/Secrets.swift`. It is gitignored and the app won't compile without it:
   ```swift
   enum Secrets {
       static let supabaseURL = "https://<your-project>.supabase.co"
       static let supabaseAnonKey = "<anon key>"
       static let tmdbReadAccessToken = "<TMDB v4 read access token>"
       static let qaEmail = "<test account email>"      // DEBUG auto-sign-in + UI tests
       static let qaPassword = "<test account password>"
   }
   ```
3. Create a Supabase project and run [`Docs/schema.sql`](Docs/schema.sql) in its SQL editor. Create a test user and put its credentials in `qaEmail` / `qaPassword`.
4. Get a free TMDB API read access token.
5. Optional: regenerate the project after adding files with `xcodegen generate --spec project.yml`. You'll also need to set your own `DEVELOPMENT_TEAM` in `project.yml` for device builds.
6. Open `Cinema.xcodeproj`, choose the `Cinema` scheme and an iPhone simulator, and run. Run unit tests with ⌘U.

Movie data is provided by TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.

## License

All rights reserved. The code is public for viewing and evaluation only; see [LICENSE](LICENSE).
