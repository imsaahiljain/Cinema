# Polish Log

A running list of the small "give it personality" details in Popcorn — the kind of stuff worth pointing to later in marketing content, App Store screenshots, or a launch post. Not a full changelog (git history covers that) — just the deliberate, opinionated touches.

Whenever a change like this gets decided or built, add an entry here (newest on top).

---

**2026-07-11 — Rankings screen: warm cream/serif redesign**
Replaced the old dark/gold flat list with a "Rankings" screen built from a real design handoff — cream background, Libre Caslon serif for titles, brick-red accent, rank numbers colored for the top 3 only. Real TMDB posters, same design language as the Marquee feed (shared in `WarmTheme.swift` so the two screens can't drift apart). A `Watched | Watchlist | Lists` pill switcher replaces the flat single list — Watchlist and custom Lists are placeholders until their backend exists. *(Note: this uses one flat accent-red color for every score badge, which conflicts with the "score color-coding by band" idea below — still needs a decision, see Open Action Items conversation.)*

**2026-07-09 — Score color-coding by band** *(decided, not yet built — now conflicts with the shipped Rankings design, needs revisiting)*
Ranked-item scores won't just be a flat gold number — they'll shift color by how good the score is: green above 8, yellow 5–8, red below 5. Makes a glance at the list tell a story instead of just a stat. Comes up when the redesigned Lists/Ranked screen gets built.

**2026-07-09 — "Rank it" promotion flow (Want to Watch → Ranked)**
Unranked lists (Want to Watch, custom lists) show a "Rank it" button instead of a score — tapping it launches a This-or-That battle and the film graduates into the Ranked list once battled. Nothing sits in limbo as just a static bookmark.

**2026-07-09 — Real TMDB posters + native reaction icons on Marquee feed cards**
Feed cards use actual poster art (not placeholders) and native SF Symbol reaction icons instead of generic emoji, with tap targets split so tapping the poster vs. the reaction area do different things. (`2ce259d`)

**2026-07-09 — Ticket-perforation motif tried, then cut**
Feed cards originally had a torn-ticket-stub perforated edge (movie ticket visual pun). Looked worse in practice than it sounded — removed in favor of a clean flush poster rectangle with all four corners rounded. Worth remembering as "sounded fun, didn't survive contact with the actual screen." (`971084d`, `cea11c9`)

**2026-07-09 — This or That rebuilt as a real swipe duel**
The core ranking mechanic (pairwise ELO battles) is a Tinder-style swipe interaction, not tap-to-pick buttons — built with real device gesture support. This is the app's signature interaction, worth leading with in any demo. (`b2a03fe`)

**2026-06-02 — "Film Fingerprint" taste profile, gamified unlock**
Profile has a "Film Fingerprint" section (top genres, favorite director, favorite actors) that's locked behind ranking 25 films, shown as a visual progress bar climbing toward unlock rather than a flat "locked" label. Turns ranking activity into a mini reward loop. (`d09ac3f`, `e432129`)

**2026-06-02 — Top 9 grid, camera-roll style**
Profile's top films render as a 3×3 poster grid (no gaps, no rounded card per tile) with a gold "#1" badge on the top film — deliberately reads like a photo grid / camera roll rather than a list, which is why it doubles as the shareable image (`ShareCardView`). (`d09ac3f`)

**2026-06-02 — Popcorn icon on the Feed tab**
Tab bar uses `popcorn.fill` for the Feed tab instead of a generic home/house icon — a small on-brand touch that ties the tab bar back to the app name. Discover tab uses `sparkles`. (`ef4efed`)

**2026-06-02 — Top 10 panel with a "hollow" peeking 0**
Discover's Top 10 numbering treats the trailing "0" as a large hollow/outlined digit that peeks out from behind the poster stack rather than sitting flush inline — a deliberate typographic flourish, not just "here's a number 10." (`1156a17`, `0b02297`)
