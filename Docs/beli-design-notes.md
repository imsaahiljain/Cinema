# Beli Design Reference Notes
*Analyzed from 470 screenshots (Beli iOS, Nov 2025) in `Beli Design References/`*
*Do not re-analyze the images — use these notes instead.*

---

## Color & Typography

- **Background**: Pure white `#FFFFFF` throughout — no dark mode, no gradients on core screens
- **Primary color**: Deep teal `#1D5F5E` (approximately) — used on CTAs, selected states, scores, nav header tint
- **Text**: Near-black `#1A1A1A` for headings, medium gray `#888` for secondary info
- **Score badges**: Circular, teal-outlined, white fill — number inside, no label
- **Typography**: Serif (looks like a custom or licensed serif) for large headings ("What's your name?", "beli" wordmark, screen titles) — creates warmth and premium feel. System sans-serif for body, lists, UI chrome.
- **Button style**: Full-width pill/capsule, teal fill, white text — disabled state is muted blue-gray
- **No emojis, no heavy iconography** — minimal line icons only

---

## Tab Bar (5 tabs)

`Feed | Your Lists | [+] Search | Leaderboard | Profile`

- Center `+` button is teal circle — triggers the rank/add flow
- Tab icons are simple line icons, labels below
- Active tab: teal tint on icon
- Bar is plain white with a hairline top border — no blur, no glass

---

## Feed Screen

- Header: `beli` wordmark (teal serif) top-left, calendar icon + bell + hamburger top-right
- Search bar below header (rounded rect, gray placeholder "Search a restaurant, member, etc.")
- Quick-action pills: `Reserve now`, `Recs Nearby`, `Trending` — horizontal scroll
- **Invite CTA card**: "You have 3 invites left! Unlock features as friends join" with feature unlock icons in a row — teal button "Invite friends"
- **Feed items**: Each item is a card with:
  - Avatar (circle, ~36pt) + name + "ranked [Place Name] with [tagged friends]"
  - Score badge (teal circle, e.g. "9.2") — right-aligned
  - Subtitle: neighborhood, borough, city + visit count
  - **3 food photos in a grid** below (2 left column + 1 right, or 2 wide) — photos are the visual weight
  - Notes text if added
  - Like count + bookmark count at bottom
  - Heart / Comment / Share icons row
  - Timestamp ("4 hours ago")
- Feed is very content-dense but readable — photos do ALL the visual heavy lifting
- No background color on cards — they sit directly on white with just spacing as separator

**Cinema adaptation note**: Replace food photos with movie poster + still frames. The poster IS our visual weight, same role as food photos.

---

## Your Lists Screen (= our My Films)

- Header: `MY LISTS` centered, share + `...` top-right
- Dropdown: "Restaurants ∨" — selects list type
- Tab row: `Been | Want to Try | Recs | Playlists | More∨`
- **Filter chips**: horizontal scroll — `City`, `Reserve`, `Open now`, `Cuisine` — pill style with dropdown arrows
- **List view** (default):
  - Sort label top-left (`↕ Score`)
  - Search icon top-right
  - Each row: `#. Restaurant Name` (bold, large) + `$$` + cuisine + city/neighborhood on next line + score badge (teal circle, right)
  - Rows separated by generous whitespace (not a divider line — just vertical padding ~20pt)
  - No thumbnail/image in the list row — pure text + score
- **Map toggle**: `View Map` button bottom-right — switches to map view with score pins
- Progress bar at top of empty state: "Your progress to Personalized Recs!" with unlock milestones

**Cinema adaptation note**: Our list rows can include a small poster thumbnail (44×66pt) since posters are the identity of a film, unlike restaurants. Score circle stays right-aligned.

---

## Item Detail Screen (Restaurant = our Film Detail)

- **Top**: Full-width map with location pin — we replace this with backdrop/still image from TMDB
- **Below map**: Name (large bold serif), cuisine tags as pills, price + cuisine + location
- **Action buttons**: `Website | Call | Directions` — we use `Trailer | TMDB | Letterboxd`
- **Scores section**:
  - `Your Beli Rating` — your ELO score + rank position ("# on your Been list")
  - `Friend Score` — avg score from friends who've rated it
  - `Average Score` — all Beli users (unlockable)
- **Photos from Beli members**: horizontal scroll of user-submitted food photos — we use TMDB stills
- **What your friends think**: search-filtered friend list with their scores
- **Notes & photos**: personal notes, labels ("After Work", "Bad Ambiance"), tagged friends, visit dates, favorite dishes

**Cinema adaptation note**: Replace map with TMDB backdrop. "Favorite Dishes" → "Favorite Scenes/Moments". Labels → moods/vibes ("Date Night", "Mind-bending", "Comfort Watch").

---

## Pairwise / Ranking Flow

Confirmed directly (screenshots 224, 249 — previously this section only inferred the flow existed; it's now been actually observed). Rating a place is one continuous bottom-sheet sequence, not separate screens:

1. **"How was it?"** — three plain color-fill circles, no borders, tap one: green "I liked it!", yellow "It was fine", pink "I didn't like it." This is a bucket/triage step, not the final score — it runs *before* any comparison.
2. **"Which do you prefer?"** — appears immediately below, same sheet. Two outlined rounded-rect cards side by side (place name + city, text only, no photos), a small filled teal "OR" badge sitting in the gap between them. Tap either card to pick it — **no swipe anywhere in this flow.**
3. Below the two cards, three text-link controls: **Undo** (back arrow, left), **Too tough** (bordered pill, center — logs "genuinely can't decide" rather than forcing a fake preference), **Skip** (forward arrow, right — defer this specific pairing, not a tie).
4. Comparisons repeat (implied same bucket only, given the "How was it" step runs first) until the score settles; detail screen then shows "Rank again" and a locked/decimal "Your Beli Rating."

Two affordances worth calling out because they're not just this app's polish, they're structural: **Undo** (a comparison can be walked back — nothing about pairwise rating is presented as irreversible) and **Too tough** (an explicit "no real preference" outcome distinct from skipping the pair entirely). Both are answers to a real problem any pairwise ranking system has — a forced binary choice with no escape hatch either corrupts the data (fake preference) or frustrates the user (no undo) — not cosmetic choices.

### Motion/behavior, confirmed from a real screen recording (2026-07-27)

The screenshots above only show static states. A user-supplied screen recording of the actual add-a-restaurant flow was frame-extracted to see the *motion* between them — the findings below came from that pass, and the recording itself is not needed again; the exact frames are saved in `Docs/beli-video-frames/` so this never has to be re-extracted.

1. **Entry is a bottom sheet that grows, not a full-screen takeover.** Tapping the rank affordance on the restaurant detail page brings up a *small* card anchored to the bottom — just the place name/X header, "Add to my list of," and "How was it?" — with the detail page still visible and dimmed above it. See `01-before-sheet-baseline-page.png` → `02-sheet-appears-small.png`.
2. **The card then expands on its own** to show the full form — "Who did you go with?", labels, notes, favorite dishes, photos, visit date, stealth mode, "Okay" button — filling most (not all) of the screen. See `03-sheet-expanded-full-fields.png`. This is the same growing-sheet behavior Popcorn's own redesigned "Your Take" flow now replicates (small → medium → large detents).
3. **Once comparisons start, the detail form collapses away entirely** — the sheet shows only the compact "How was it" confirmation (checked bucket) plus "Which do you prefer?", no wasted space where the form used to be. See `04-compare-stage-fields-collapsed.png`.
4. **There is no winner animation between picks — confirmed by dense frame sampling (0.26s intervals).** Between `05-instant-transition-before.png` (62.81s) and `06-instant-transition-after.png` (63.06s) the comparison pair changes completely with no in-between frame showing any slide, overarch, or celebration. It's an instant cut. This directly informed dropping Popcorn's `DiagonalOverarchWinEffect` from the real duel screen.
5. **Finishing the rating flow returns to the restaurant's detail page**, where a native share sheet with Beli's own branded link-preview card (place name + score) appears. See `07-completion-returns-to-detail-page.png`. This reads as the natural "you're done" endpoint, not a separate confirmation screen.

---

## Search Screen

- Full search bar at top
- Results show restaurant name, type/cuisine, location, score badge
- Filters sheet (bottom sheet): Category pills, Sort by segmented control, Filters accordion (City, Good For, Score, Cuisine)
- "Add labels" sheet: long searchable list of tags

---

## Leaderboard Screen

- Not deeply visible but tab exists — likely city/neighborhood ranking of places

---

## Profile Screen

- Name + share + `...` top-right
- Three tabs: `Cuisines | Cities | Countries` — shows taste breakdown by category with avg scores
- `Recent Activity | Taste Profile` tabs on friend profiles
- **Taste Profile card**: "Top 0.5% Diner in Menlo Park" — big stats card with teal background, restaurant count, cuisine count, activity percentile
- **Dining Map**: world map showing cities visited
- Stats: `Rank on Beli #832`, `Current Streak 125 weeks`
- Been count + Want to Try count at top
- Recent Activity: same format as feed items but scoped to one person

---

## Onboarding Flow

1. Splash — wordmark centered on white, fades in
2. Name (first + last, underline text fields)
3. Username / phone
4. "Any cuisines you don't like?" — plain list with checkboxes, "Nope, I like everything" CTA
5. "Select your school" — searchable list
6. Sync reservations (Resy/OpenTable via Gmail)
7. Contacts sync
8. Movie wall equivalent — seeded list of local restaurants to start ranking

**Key pattern**: One question per screen, large serif heading, muted continue button until input is valid, back chevron top-left.

---

## UI Patterns to Clone Exactly

| Pattern | Beli | Cinema |
|---|---|---|
| Score badge | Teal circle, decimal number | Same, our accent color |
| List row | #. Name + metadata + score right | Same + small poster thumb |
| Feed card | Avatar + name + score + photos | Avatar + name + score + poster |
| Tab bar | 5 tabs, center + | 4 tabs (drop leaderboard for now) |
| Detail header | Map | TMDB backdrop image |
| Taste profile | Category avg scores | Genre avg scores |
| Onboarding | One question/screen, serif heading | Same (already built) |
| Filter sheet | Bottom sheet, pill chips | Same |
| Progress bar | "X of Y ranked" on list | Same |

---

## Where We Improve on Beli

| Beli weakness | Cinema solution |
|---|---|
| Feed is all text + food photos — visually monotonous | Movie posters are inherently cinematic — use them full-bleed in feed cards |
| White background everywhere feels clinical | Dark background (`#0A0A0F`) — posters and stills pop against dark |
| No visual identity per item in the list | Poster thumbnail in every list row |
| Score is just a number | Show score + rank position prominently |
| Cluttered detail page | Simpler: backdrop → title → your score → friends' scores → where to watch |
| Taste profile is just cuisine stats | Genre breakdown + director affinity + decade preference + "your cinema DNA" |

---

## What We Skip (Beli-specific, doesn't apply)

- Map view (restaurants have location, films don't)
- Reservations feature
- "Reserve now" / OpenTable integration
- Price tiers ($$, $$$)
- Visit count / visit dates
- Dining challenges ("2025 Restaurant Challenge")
- Payment methods / credits system (we may do invite-to-unlock differently)
