# Cinema — Post-Production Features

Features to build once the core app has users. Do not build these prematurely.

---

## Monthly Recaps (Spotify Wrapped)
- End-of-month shareable card: films ranked, battles fought, #1 film of the month, biggest ranking upset
- Year-in-review version: "Your 2026 in Film"
- Auto-generated, push notification to open, one-tap share to Instagram Stories
- Requires: enough ranking data per user (~20+ films/month to be interesting)

## MovieNight
- Select 2–6 friends from your contacts
- App cross-references everyone's ranked lists + watchlists
- Surfaces films everyone would enjoy: high on at least one person's list, not low on anyone's
- Shows a ranked shortlist of recommendations with "% match" for the group
- Requires: multiple users with populated ranked lists in the same friend group

## Taste Challenges / Debates
- When two users disagree sharply on a film's rank, app detects it
- Either user can "challenge" the other: the challenged user re-runs That or That with that film vs. films at the position the challenger claims it belongs
- Result card: gap closed or held, both positions shown
- Shareable: "I think Inception is top 5. Jordan disagrees. Who's right?"
- Non-user web fallback: deeplink lets non-users see the challenge and prompts download to respond

## Invite-to-Unlock
- After N battles or some time in the app, surface a feature gate
- Unlock by sharing a personal invite link that results in a friend downloading + completing onboarding
- What they unlock: TBD (early ideas: profile themes, extended taste stats, seeing friends' full ranked lists)

## Sponsored Recommendations (Monetization)
- Discovery tab: 2 engine-generated picks + 1 sponsored pick
- Sponsored pick must be a real film, clearly labeled "Suggested"
- Matched to user's taste profile (genre + ELO data), not random
- Revenue model: studios/streamers pay to surface titles to relevant audiences

## TV Shows
- Evaluate after movies are stable: separate ELO pool or cross-media battles?
- Core question to resolve: do you battle a film against a show? (probably not — keep pools separate)
- Complicates catalog, onboarding seed list, and taste profile significantly
- Do not add until movies product is proven

## Social Feed (v2)
- Show only high-signal events, not every ranking
- Events worth surfacing: #1 changes, 100-film milestones, sharp disagreements with friends
- "You and Jordan disagree on Parasite" → tap to see both lists side by side
- Requires: populated friend graphs (meaningless without friends)

## Global Leaderboard
- Most-ranked film of the week globally
- Most controversial film (highest variance in rank position across users)
- "Your city's taste" — aggregated rankings by geography (requires enough density)

## Letterboxd Sync (v2)
- Currently: one-time CSV import during onboarding
- Future: periodic re-sync via CSV to catch new ratings
- Stretch: if Letterboxd ever opens an API, replace CSV flow

## MovieNight Reservations / Ticket Integration
- Once MovieNight exists, integrate with Fandango/AMC/Regal
- "You picked Dune 3 for tonight — buy tickets?"
- Much later, requires partnerships
