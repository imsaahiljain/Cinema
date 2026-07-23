# Polish Log

A running list of the small "give it personality" details in Popcorn — the kind of stuff worth pointing to later in marketing content, App Store screenshots, or a launch post. Not a full changelog (git history covers that) — just the deliberate, opinionated touches.

Whenever a change like this gets decided or built, add an entry here (newest on top).

---

**2026-07-23 — Cast & Crew shows real key crew, "In Theaters Now" chip for pre-streaming releases**
Cast & Crew used to mean "cast + a single Director line" — TMDB's real crew list for a major release runs into the hundreds (camera department, sound, art department...), so rather than dump all of it we now surface the handful of jobs people actually look for: Director, Writer/Screenplay, Producer, Director of Photography, Original Music Composer, Editor, each only shown if credited. Also added a quiet "In Theaters Now" pill (ticket icon, same outlined-capsule style as a genre chip) that appears in the Where to Watch slot when a film is in its theatrical window and has no streaming/rental data yet — reuses the existing `isRecentRelease`/`isUpcoming` heuristic already built for Search's tags rather than a new API call, so a movie like a brand-new theatrical release doesn't just show an empty gap where Where to Watch would normally be.

**2026-07-23 — Movie info screen: reordered around "have you actually seen it," private notes added**
Rebuilt the content order below the (unchanged) hero banner: title/rating/trailer/genres → summary → Friends' Takes → Where to Watch → your private note → Cast & Crew, with Cast & Crew now always last. Reasoning: most films someone looks up on this screen are ones they find interesting but haven't watched — reference info (cast, crew) is only useful once you already know you care, so it shouldn't compete for the first screenful with the things that help you decide (what it's about, what your friends thought, where to watch it). Friends' Takes now also includes your own take ("You," if you've ranked it) and each friend row links through to their profile. Added a genuinely new feature alongside the reorder: a private per-film note (new `film_notes` table, RLS-restricted to the owning user — verified no other session, not even anon, can read it) for jotting something down about a film regardless of whether you've ranked or watchlisted it yet. Explicitly dropped an earlier gamification-heavy pass (medal badges, battle-history "beat X / lost to Y" language, streak chips) — decided it read as unattractive and presumed a watch history that, for browsing-stage films, doesn't exist yet.

---

**2026-07-21 — Search grid "tags": a gold "NEW" instead of a useless year**
Search results used to show each film's release year, but outside a brand-new release, the year does nothing to help identify a movie — nobody recognizes "Minions" is the right result because it says "2015." Replaced it with the start of a tag system: a small gold "NEW" label (plain text, no filled pill) appears in that same spot for anything released in the last 45 days, and disappears entirely otherwise — no date info at all for older titles, since none was needed. First of what's meant to become a small family of at-a-glance tags (a "well-known" / legitimacy tag is next, logged in `CLAUDE.md`'s Post-Production Backlog for after launch). Good content angle: "we replaced a number nobody could use with a badge that tells you something you actually want to know."

**2026-07-20 — Search rebuilt as a poster grid: recognition over reading**
Typed search results used to be a text-heavy list (poster, title, year, genre, rating all spelled out in a row) — the same shape as a lot of search UIs, but wrong for this app specifically. The insight: someone using Search has almost always already decided what they're looking for — they just watched it and want to log it, or a friend recommended it and they're adding it. That's a *confirm-and-select* task, not a *browse and discover* task (Discover already owns browsing). For confirming a title you already have in mind, recognizing the poster art is faster than reading a row of metadata, so Search now renders results as the same 3-column poster grid as the idle Trending browse — tap a poster to confirm on the detail screen, everything else (Add to List, Rank This or That) tucked behind a quiet "..." on the poster with a long-press shortcut on top of it. Good before/after material — the old row-based screen vs. this grid is a clean visual demonstration of "we didn't just copy a generic search UI, we designed for how people actually use this specific feature."

**2026-07-11 — Rankings screen: quiet "Lists" caption up top**
After dropping the big "Rankings" title/subtitle, the tab switcher sat flush against the safe area, which read as cramped rather than clean. Added a small, quiet "Lists" label above it — just enough breathing room, not a return to the big serif headline. Closer to how Beli gives "MY LISTS" a plain caption rather than no header at all.

**2026-07-11 — Hold a list to delete it, with a confirmation**
Long-pressing a custom list pill opens a context menu with "Delete List"; confirming shows an alert ("This can't be undone") before it actually deletes. Same pattern applied to individual Watchlist and custom-list rows ("Remove"). Small, but this is the kind of thing that makes an app feel finished rather than half-built.

**2026-07-11 — Lists screen: no headline, "+" to create your own**
Dropped the big "Rankings" title/subtitle — the tab switcher alone carries context, closer to how Beli treats its list tabs as plain furniture rather than a decorated headline. Replaced the fixed Watched/Watchlist/Lists three-way switcher with a horizontally scrolling row (Watched, Watchlist, then one pill per list you've made) and a fixed "+" button top-right to create a new one on the spot — scrolls sideways once you have more lists than fit on screen instead of hiding them behind a menu.

**2026-07-11 — Scores stay hidden until you've ranked 10 films**
Below 10 ranked films, the Rankings screen shows a "Rank N more films to reveal scores" progress hint instead of score badges — rank position, poster, and title still show immediately. Reason: the rank-based /10 formula always puts #1 at a flat 10.0 and last place at a flat 0.0 no matter how many films are ranked, and with only a couple films that reads as broken rather than earned. 10 was picked to match the app's existing 10-Movie Wall onboarding gate rather than invent a second arbitrary number — everyone who reaches this tab through normal onboarding has already cleared it, so in practice this only shows for accounts seeded outside onboarding (QA/dev).

**2026-07-11 — Rankings screen: warm cream/serif redesign**
Replaced the old dark/gold flat list with a "Rankings" screen built from a real design handoff — cream background, Libre Caslon serif for titles, brick-red accent, rank numbers colored for the top 3 only. Real TMDB posters, same design language as the Marquee feed (shared in `WarmTheme.swift` so the two screens can't drift apart). A `Watched | Watchlist | Lists` pill switcher replaces the flat single list — Watchlist and custom Lists are placeholders until their backend exists.

**2026-07-09 — Score color-coding by band** *(decided, cutoffs not yet chosen — see NOTES.md)*
Ranked-item scores won't just be a flat gold number — they'll shift color by how good the score is: green above 8, yellow 5–8, red below 5. Makes a glance at the list tell a story instead of just a stat. Currently the shipped Rankings screen uses one flat accent-red badge instead; revisit once the color cutoffs are decided.

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
