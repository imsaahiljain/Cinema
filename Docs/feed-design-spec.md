# Popcorn Feed — Design Spec (v1)

*Companion to `beli-design-notes.md`. Feed is the one screen that deliberately diverges from the Beli clone — everywhere else in the app still borrows Beli's system.*

*Branding note: this spec uses the "Popcorn" rename (app name, popcorn-bucket tab icon, "pop" as the post unit) per product direction. The rename itself — bundle ID, `project.yml`, Supabase project name, all in-code "Cinema" references — has NOT been executed and is a separate, larger task; see "Rebrand scope" at the bottom.*

---

## 1. Root cause: why Beli's feed reads as static

Grounded in `Docs/beli-design-notes.md` (Feed Screen section), not a guess:

- It's a **plain reverse-chronological scroll** of cards. No card ever changes state after it renders — no live counters, no autoplay, nothing happens on its own.
- **Engagement is passive-icon-only**: heart / comment / share row at the bottom of a static card, identical to a 2012 Instagram post. Tapping a like just fills an icon; nothing animates, nothing responds.
- **Every card looks the same shape**: avatar + name + score badge + 3-photo grid + notes + icon row. A feed of 50 posts is 50 repeats of one template — the monotony isn't the food photos, it's the *lack of template variation*.
- **No sense of "happening now."** There's no indicator that anyone else is active, no live/ephemeral content, no urgency to open the app at a particular moment. It's a database dump, sorted by time.

That's the actual thing to design away from — not "make the colors less white," but *give cards more than one shape, give the feed live state, and give interactions a visible/felt response instead of a silent icon-fill.*

Popcorn's advantage the notes already call out: **posters are inherently more dynamic source material than food photos** (motion stills, trailers, matched-geometry poster transitions already exist in the This-or-That flow) — Feed should spend that advantage instead of flattening it into another static card grid.

---

## 2. Prior art (mechanics, not vibes)

| App | Mechanic actually used | What Popcorn borrows |
|---|---|---|
| **BeReal** | Everyone is notified at the same moment and posts within a tight window; feed fills in real time while it's open | A live "friends ranking right now" presence strip — makes the feed feel like something is happening *while you're in it*, not a static archive |
| **TikTok / Reels** | Full-bleed media autoplays the instant a card is >50% on screen; sound and motion are the default, not a tap-to-play state | Feed cards autoplay a short backdrop/trailer loop (muted, Ken-Burns or clip) the moment they enter the viewport, instead of a static poster thumbnail |
| **Poparazzi** | Reactions are large emoji/sticker taps with a spring-in animation and haptic, not a small heart icon | "Pop reactions" are big, spring-animated stickers (🍿, 🔥, 🤯, etc.) that visibly fly onto the card and trigger a haptic — not a silent icon fill |
| **Strava (Kudos + segments)** | Kudos count updates live in front of you; the tap has a distinct fill+bounce animation on the exact button you pressed | Reaction counts update in-place with the same spring physics already used for the This-or-That win reveal, not a re-render |
| **Instagram Stories** | Progress-segmented ring around the avatar signals "new, unseen, time-boxed" before you tap in | Friends who ranked something in the last few hours get a gold ring around their avatar in the feed header row — signals "fresh" without needing a timestamp read |
| **Letterboxd diary** | A rating event is a first-class content type (star rating + optional review), distinct from a generic post | A "pop" that's just a ranking result (no note) renders as a compact result card; a pop *with* a note/comment renders as an expanded card — two card shapes, not one template repeated |

---

## 3. What a "pop" is

A **pop** is the atomic unit of Feed content. Every pop is generated from something that actually happened in the app — never a free-floating text post with no underlying action. Three kinds:

1. **Battle pop** — auto-generated when a user finishes a This-or-That comparison. Shows the winner beating the loser using the *same visual language* as the live duel screen (poster slide + overarch, reusing `DiagonalOverarchWinEffect` — see §7), compressed into a feed-card-sized replay instead of full-screen.
2. **Milestone pop** — auto-generated on rank-order-changing events worth surfacing: a film entering someone's top 10, a #1 spot changing, a genre streak ("5 horror films ranked this week").
3. **Recommendation pop** — user-composed. The explicit "watch this" social note: pick a film, write a short take, optionally tag friends. This is the only pop type with a compose flow; the other two are byproducts of using the app.

Every pop carries: poster/backdrop media, the acting user, an optional short note, reaction stickers, and — for battle pops — the two films involved.

### Tone & language guidelines for pop text

- Popcorn's own voice, not Beli's: short, casual, present-tense, like a text to a friend — not a review-site sentence.
- Auto-generated captions read as an event, not a headline: **"picked *Whiplash* over *Birdman*"**, not "Whiplash defeats Birdman in an epic showdown."
- Milestone captions stay factual and light: **"*Parasite* just took the #1 spot"** — no forced hype language, no exclamation-point stacking.
- User-written notes are left as-is, un-edited, un-templated — it's their voice, not the app's.
- Never say "review" or "rating" in UI copy for a pop — say **"popped"** as the verb ("Maya popped *Whiplash*"), consistent with the noun.
- No em-dash-stacked marketing copy in any UI string. One idea per line.
- `[FILL: exact reaction-sticker set — needs a short list of 4-6 icons/emoji that read as "movie reactions" rather than generic social icons; picking these is a visual-design decision, not interaction-design]`

---

## 4. User flow

```
Feed tab (popcorn-bucket icon) opens to:
│
├─ Presence strip (top, horizontal scroll)
│   Avatars of friends currently mid-battle or active in the last hour,
│   gold "live" ring. Tap → jump to their profile / recent activity.
│
├─ Pop stream (vertical scroll, LazyVStack)
│   │
│   ├─ Battle pop card
│   │   Auto-plays winner/loser reveal once on-screen (one-shot, not looping)
│   │   Tap card → expands to full duel-style reveal (reuses RankingView's
│   │   win-effect layer, not a rebuild)
│   │   Tap poster → film detail
│   │   Reaction stickers row → tap explodes a sticker onto the card + haptic
│   │
│   ├─ Milestone pop card (compact, ~half height of a battle pop)
│   │   Single poster, rank badge, one-line caption
│   │
│   └─ Recommendation pop card
│       Poster/backdrop, user's note, reaction row
│       Tap "Add to my list" → queues the film into the user's own
│       This-or-That flow directly from Feed (this is the fix for the
│       "ranking flow never wired to a button" bug noted in CLAUDE.md —
│       Feed becomes another entry point into RankingView, same as
│       Search/Discover)
│
└─ Compose entry point ("+" in tab bar, existing pattern)
    → Search for a film → write note → optionally tag friends → post
    (this is the only pop type a user manually creates)
```

---

## 5. UI components

| Component | Notes |
|---|---|
| `PresenceStrip` | New. Horizontal avatar scroll, gold live-ring, matches tab-bar glass treatment |
| `BattlePopCard` | New. Full-bleed dual poster layout, autoplay win-effect on appear, expand-on-tap |
| `MilestonePopCard` | New. Compact single-poster card, rank badge reuses `FilmRow`'s rank-number styling |
| `RecommendationPopCard` | New. Poster/backdrop + note text + reaction row, closest in shape to a Beli card but full-bleed poster instead of a photo grid |
| `PopReactionBar` | New. Sticker buttons, spring-in + haptic on tap, live count |
| `PopComposeView` | New. Reuses `SearchView`'s film-search list as the picker |

**Visual style notes** (within the existing dark Popcorn theme, `CinemaTheme` — background `#0A0A0F`, gold accent):
- Cards sit full-bleed edge-to-edge for battle pops (maximize poster/motion impact), inset-padded for milestone/recommendation pops (keeps text-forward content readable) — this is the "two card shapes" fix from §1.
- No card background fill, consistent with the rest of the app's `ultraThinMaterial`-on-dark language — separation comes from spacing + a subtle top hairline, not boxed cards.
- Autoplay media is muted by default, respects Reduce Motion (falls back to static poster + a single subtle fade-in, no motion).

---

## 6. Motion & feel spec (the part that actually needs building, not just describing)

This is the section most likely to be wrong on first guess — per the methodology, it should be **built as an isolated prototype and hand-tested**, not shipped from this description alone.

- **Battle pop reveal**: reuse `DiagonalOverarchWinEffect` (`Cinema/Features/Ranking/WinEffects/DiagonalOverarchWinEffect.swift`) at feed-card scale instead of full-screen — it's already a validated Popcorn-native motion (not borrowed from a reference app), so Feed should feel like the *same app*, not a bolted-on social layer. Needs a scaled-down `Params` pass, not a rebuild.
- **Reaction sticker tap**: per-frame spring animation (not a linear fade), haptic fired at the exact moment the sticker visually lands — same principle as the swipe-duel commit haptic already tuned in This-or-That. **Must be validated on a physical device**, not the simulator (no Taptic Engine in `simctl`) — this is the same constraint already noted for the swipe gesture work.
- **Presence ring**: subtle looping pulse (opacity, not scale) on the gold ring for anyone *currently* mid-battle (vs. a static ring for "active in the last hour") — cheap way to make the strip feel alive without autoplaying video for every avatar.
- **New pop arrival**: if a friend posts while the user has Feed open, insert the card at the top with a brief slide+fade rather than a hard reload/jump — avoids the disorienting "list shifted under your thumb" problem common to naive live feeds.

---

## 7. Build plan (prototype before integration)

Per the app's existing working style (one feature at a time, verify before moving on):

1. Prototype `BattlePopCard` + the scaled win-effect reuse against **mock data only**, in an isolated preview/harness — no Supabase writes, no real feed query — same pattern as `RankingPrototypeView.swift` already in the repo.
2. Hand-test the reveal + reaction-sticker haptic on the physical device (a physical iPhone) before agreeing the motion is right.
3. Only after that's approved: wire real data (`feed_events` table, already in schema) and the real Feed tab entry point, plus the Recommendation-pop → RankingView hookup described in §4.
4. Milestone and Recommendation pop cards follow the same card shell but are lower motion-risk (no custom haptic-timed animation) — fine to build directly against real data once the battle-pop pattern is validated.

---

## 8. Open placeholders

- `[FILL: target audience / friend-graph size assumption]` — presence strip and "friends ranking now" only feel alive above some minimum active-friend count; below that it may look empty rather than dynamic. Needs a decision on what happens with 0-2 active friends (hide the strip? show a CTA to invite instead?).
- `[FILL: reaction sticker set]` — see §3.
- `[FILL: milestone event list]` — §3 lists three example milestone triggers; the full list of what counts as "milestone-worthy" needs a product decision (risk of over-notifying vs. feed feeling empty).
- `[FILL: feed_events schema fields]` — confirm `feed_events.event_type` values cover battle/milestone/recommendation distinctly, or whether a migration is needed.

---

## 9. Rebrand scope (flagged, not executed)

This spec uses "Popcorn" / popcorn-bucket icon / "pop" throughout per product direction, but the codebase, bundle ID (`com.mtgcardneeder.Cinema`), `project.yml`, `CLAUDE.md`, Supabase project naming, and every in-code `Cinema*` type/string still say Cinema. Actually executing the rename is a separate, higher-blast-radius task (touches signing/provisioning, not just find-replace) and should be scoped and confirmed on its own before starting.
