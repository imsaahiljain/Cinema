# Popcorn — CLAUDE.md

## Naming (read this before assuming "Cinema" vs "Popcorn" is a mistake)
As of 2026-07-09, the app is branded **Popcorn** to users — app display name, in-app wordmark (splash/login/profile screens), and system permission dialogs all say "Popcorn."

The codebase internals still say **Cinema**: Xcode project/scheme name, bundle ID (`com.mtgcardneeder.Cinema`), Swift types (`CinemaTheme`, `CinemaApp`, `CinemaUser`, etc.), the `Cinema/` folder, the git remote, and the Supabase project name. This is intentional, not a stale/incomplete rename — none of that is visible to a user, and changing it (especially the bundle ID) risks breaking code signing/provisioning for no user-facing benefit. See `Docs/feed-design-spec.md` §9 for the reasoning. Don't "fix" the mismatch by renaming internals unless explicitly asked.

## Notes File
`NOTES.md` in this repo is a running scratchpad of freeform notes-to-self. Whenever the user says "note to self," append what they said (verbatim, with today's date) to `NOTES.md` — don't editorialize or fold it into this file. Check `NOTES.md` when asked what notes exist.

## Polish Log
`Docs/polish-log.md` tracks the small "give it personality" UI/UX details worth referencing later for marketing content — color-coded scores, gamified unlocks, signature interactions, that kind of thing. Not a full changelog (git history covers that); only the deliberate, opinionated touches. Add an entry (newest on top) whenever one of these gets decided or built, even if it hasn't been implemented yet — mark undecided/unbuilt ones `*(decided, not yet built)*` and update once shipped.

## Open Action Items (things only the user can do — check this whenever asked "any action items left?")
- ~~Apple Developer Team ID~~ — done. User's Xcode account has a free Personal Team, `PXH52A4CBY` ("Saahil Jain (Personal Team)"), now set as `DEVELOPMENT_TEAM` in `project.yml` with `CODE_SIGN_STYLE: Automatic`. Physical device (Saahil Jain's iPhone, an iPhone 17,5) is paired and shows up in both `xcrun devicectl list devices` and `xcrun xctrace list devices`. Personal Team signing means installed builds need re-signing every 7 days — if a device build stops launching after a week of inactivity, that's why; just rebuild and reinstall.
- ~~Supabase Personal Access Token~~ — done, saved at `~/.supabase/access-token` (outside the repo, never committed). Verified working against `api.supabase.com/v1/projects`.
- **Supabase `service_role` key** — still not held. Only needed for admin-level data operations that bypass Row Level Security; the PAT above covers schema/project-config changes. From the project's Settings → API in the Supabase dashboard, if it ever comes up.

## Pre-Launch Legal Checklist (must ship before the app goes public — not blocking current feature work)
User's explicit call (2026-08-15): draft/implement none of this now, "deal with it later," but track it so it doesn't get forgotten before a real public launch.
- **Terms of Service + Privacy Policy** — need actual documents linked from Settings. User wants them "ironclad" / "0 chance of lawsuit" — flagged back to them that no document makes real lawsuit risk zero, but a strong self-serve draft (liability cap, mandatory arbitration + class-action waiver, full UGC license grant-back, indemnification, age gate, termination rights) is the realistic target pre-launch, with a ~$300 real lawyer review once there's actual revenue.
- **DMCA takedown agent registration** — register at dmca.copyright.gov (~$6, five minutes). This is what actually shields the app from copyright liability for user-posted content — the ToS clause alone doesn't do this.
- **TMDB attribution line** — required by TMDB's API terms, not currently anywhere in the app: "This product uses the TMDB API but is not endorsed or certified by TMDB." Belongs somewhere in Settings.

## Post-Production Backlog (polish/features to come back to later — not blocking current work)
- ~~Multiple winning animations for This or That~~ — reversed, not just deferred. The premise (build several variants of a per-pick "winner" animation and rotate between them) assumed the duel screen should have one at all. Explicit user feedback (2026-07-27), backed by a frame-by-frame look at an actual Beli screen recording: Beli has *no* winner animation whatsoever — tapping a card cuts instantly to the next comparison, no slide, no overarch, no lingering celebration. `DiagonalOverarchWinEffect.swift` (the "winner slides diagonally across and overarches the loser" effect this item used to point at as the first candidate) was tried in the real tap-based rebuild and rejected outright ("looks really ass"). It's been removed from `RankingView.swift`'s duel screen; the file itself still exists and is still used by the unrelated `FeedPrototypeView.swift` prototype, so don't delete it, just don't reach for it here. Do not resurrect this item without new, explicit direction from the user.
- **Separate onboarding variant of This or That** — the 10-Movie Wall needs its own version of the ranking screen with an added "I haven't watched one of these" button. Tapping it changes the top prompt to ask which film the user *has* seen (put that phrasing in the question area at the top) and requires tapping the poster of the one they've watched, rather than a normal pairwise pick.
- **Decision-time-weighted ranking algorithm** — go beyond fixed-K ELO (K=32) by also factoring in how long the user took to decide (fast pick = high confidence = bigger rating swing, long hesitation = low confidence = smaller swing) plus other behavioral signals, closer to how Glicko/TrueSkill model rating confidence rather than plain ELO. Separate work from the visual/gesture rebuild — touches `ELOService` and `RankingViewModel.selectPair`/`choose`.
- **Custom sound effects for This or That** — swipe/commit/win moments should eventually have short custom SFX (not generic iOS system sounds) to match the haptic feedback. Needs either sourcing a few licensed/royalty-free short clips or synthesizing simple tones in-app; punt until the swipe + haptics interaction itself is built and feels right.
- **More Search grid tags beyond "New"** — the tag system (`Cinema/Features/Search/SearchView.swift`, `SearchGridTile`, sits in the year's slot in the caption) is deliberately launching with just `MediaItem.isRecentRelease` ("New"). The next candidate is a legitimacy/recognition tag (working name "Popular") based on `voteCount` clearing some threshold — the thing that actually would have disambiguated "Minions" from knockoffs like "Minion Scouts," which "New" doesn't address at all. Don't build it until there's real usage data to pick a sane vote-count cutoff — the one real number checked so far (Minions & Monsters, a real 2026 release the user watched and liked, sitting at ~208 votes) shows a naive high threshold (1,000+) would unfairly exclude a legitimately good, just-new movie. Needs a smarter rule than a flat cutoff, or needs to coexist with "New" rather than replace it for brand-new titles.
- **Affiliate links on Rent/Buy providers as a monetization path** — `ProviderLogo` tiles in Where to Watch (`Cinema/Features/Discover/MovieInfoView.swift`) aren't tappable at all right now, purely decorative. The real opportunity is rent/buy specifically (Apple TV Store, Google Play, Amazon, Fandango At Home all run real affiliate programs paying a commission on the actual transaction — this is literally part of JustWatch's own business model, the company whose data TMDB's watch-provider info comes from) — not streaming subscriptions (those generally only pay for a brand-new signup, not an existing subscriber opening one more title) and not the Trailer button (YouTube doesn't pay referral commissions for video views at all). Would need: sign up for each platform's affiliate program individually, make the Rent/Buy icons tappable/linking out, append each program's tracking parameter to the outbound URL. Known real limitation to keep in mind, not a blocker: affiliate credit is cookie/session-based per device, so it won't cross-device attribute (tap the link on phone, buy later on the TV instead = no credit) — a standard industry-wide limitation, not something specific to how we'd build it.
- **Real Rotten Tomatoes critic-score data for Discover's "Highly Rated" row** — `TMDBClient.highlyRated()` currently fakes "critically acclaimed" using TMDB's own user vote average/count (TMDB has no actual critic data — that's a separate, paid RT license). Worth buying and wiring in once the app is actually making money; until then the row stays honestly named "Highly Rated" rather than overclaiming real critic scores.
- **Release-countdown chip on Most Anticipated posters** — the "Most Anticipated" row (`TMDBClient.mostAnticipated()`) currently shows plain posters like every other row; a small "In theaters July 31" countdown chip per poster would make the hype framing more explicit than just the row title. Minor polish, not blocking.
- **Search's "Trending" row overlaps Discover's Top 10** — same underlying `trending()` call as Discover's Top 10 Right Now, being redesigned separately per the user's own request — don't touch `Cinema/Features/Search/SearchView.swift`'s trending logic until that conversation happens.
- **Profile "Guides" tab — decided against as a standing tab (2026-08-15).** During the Profile redesign the user referenced Beli's 3-tab profile (Activity / Taste Profile / Guides) and asked whether a Popcorn "Guides" tab was worth building. Take: skip it. Beli's guides work because they're curated by real local expertise (food publications, influencers) — genuine information Gen Z can't get elsewhere. Our only honest content source is TMDB Collections (franchise groupings with an overview blurb), which most users' ranked lists won't touch most of the time, so a permanent tab built on it would read as empty/unfinished rather than minimal. User agreed. If this comes back, build it as a contextual surface instead — e.g. a "Watch Order" chip on a movie's detail page when it belongs to a real franchise — not a tab. The broader Activity-feed half of that same Beli reference (a per-user feed of ranking posts with photos/notes/likes/comments) is a much bigger, separate feature — no schema for photos/likes/comments on a ranking exists yet — and hasn't been decided on at all; don't build it without explicit direction.

## What This Is
Popcorn is a high-velocity social media app for movie/TV taste. Think Beli for restaurants, but for film. Users rank media via pairwise ELO ("This or That"), build a ranked list, and share taste with friends via a social feed.

## Current Status & Working Agreement (as of 2026-07-08 — check git log before trusting this is still current)

**Branch:** `main` is the working branch. There was a `v2-rebuild` branch where features had been deliberately stripped to stubs for a from-scratch rebuild with a nicer tab bar; after comparing both live in the simulator, the user chose to consolidate back onto `main` instead, since it already has more built-out screens (Profile, Search, Discover all have real content; `v2-rebuild`'s equivalents were still stubs). Two things that note used to flag as worth cherry-picking from `v2-rebuild` are both resolved — don't act on them if this section is stale by the time you read it further back in history:
- ~~Floating glass-pill tab bar~~ — nothing to port. `Cinema/App/MainTabView.swift` is a completely stock SwiftUI `TabView`/`.tabItem`, no custom styling code at all; the floating glass-pill look is just iOS 26's native tab bar rendering by default. Confirmed 2026-07-25 after the user pointed out main already has it and loves how it looks — don't touch this file for visual reasons.
- ~~"This or That" ranking flow not wired to any button~~ — already fixed. `Cinema/Features/Search/SearchView.swift` launches `RankingView` after a film is added (`showRanking = true` once 2+ films are added), confirmed working.

**Working style the user has explicitly asked for:**
- **One feature at a time.** Implement it, verify it actually works (build + real interaction via the simulator, not just "it compiles"), then stop and let the user react before starting the next one. Don't batch multiple features into one pass even if they feel related — this was called out directly after Ranking/Search/Discover/Lists all got built together in one go.
- **Be transparent, not just fast, when something isn't working.** If a debugging approach is fundamentally wrong (e.g. screen-pixel clicking), say so and switch rather than iterating blindly on the wrong tool.
- **Mistakes themselves are fine — repeating one that's already been diagnosed is the actual problem.** Stated directly (2026-07-25) after a long, expensive tap-coordinate debugging loop: making the mistake once isn't the issue, so no need to over-apologize or be overly cautious afterward — just make sure the root cause gets written down somewhere durable (like this file) so a future session doesn't burn the same time re-discovering it.
- **Efficiency matters as much as correctness.** Stated directly (2026-08-17) after a session spent a full build+install+screenshot verification cycle on each of several small, related fixes in a row instead of batching them. When a single message bundles multiple small/related changes, make all the edits first, then run ONE build+verify pass over the whole batch — not one cycle per edit. Default to simulator-only verification (skip the physical-device install) unless the user asks for the device build or the work is a genuine ship-it checkpoint, not every micro-fix. This doesn't override "one feature at a time" for actually distinct features — it's about not re-running the full loop for small edits within the same feature/message that are naturally checked together.
- The user is non-technical — they will not know what "PR," "gh," "xcodegen," or similar terms mean. Explain in plain language, and don't ask them to run terminal commands themselves unless truly stuck (e.g. granting a macOS permission, which only they can click through).
- This is meant to run close to autonomously — the user wants to give feedback periodically, not approve every step.

## Pivot Context
We previously built Bookly/BookWyrm (reading tracker). It failed due to low content velocity (books take weeks), privacy concerns, and fragmented book APIs. Cinema solves all three: movies are consumed in hours, are socially trendy, and TMDB is an excellent API.

## Stack
- **UI**: SwiftUI, iOS 26+ target
- **Backend**: Supabase (PostgreSQL, Auth, Realtime)
- **Media Data**: TMDB API (movies + TV shows)
- **Dependencies**: Swift Package Manager only — no CocoaPods, no npm

## Architecture: MVVM + Feature Modules
```
Cinema/
├── App/                    ← CinemaApp.swift, AppState
├── Core/
│   ├── Network/            ← TMDBClient.swift, SupabaseClient.swift
│   ├── Models/             ← Movie, Show, CinemaUser, ELOMatch, RankedItem
│   └── Services/           ← ELOService, AuthService, MediaService, FeedService
├── Features/
│   ├── Auth/               ← Login, Signup views + ViewModels
│   ├── Onboarding/         ← 10-Movie Wall (must complete to unlock feed)
│   ├── Feed/               ← Social feed (friends' recent rankings)
│   ├── Ranking/            ← "This or That" ELO pairwise comparison flow
│   ├── Search/             ← TMDB search for movies/shows
│   ├── Profile/            ← Ranked grid, stats, taste profile
│   └── Leaderboard/        ← Global/friends ranking leaderboard
├── DesignSystem/           ← LiquidGlass modifiers, Color+Cinema, Typography
└── Resources/              ← Assets.xcassets, fonts
```

## Core Product Rules
1. **No star ratings** — ELO pairwise only. Every ranking comes from a "This or That" battle.
2. **10-Movie Wall** — New users must rank 10 films before accessing the social feed. Non-negotiable onboarding gate.
3. **ELO formula**: Standard ELO, K=32. Winner gains, loser loses. Stored per-user per-media-item.
4. **TMDB is source of truth** for all media metadata — never store poster URLs or titles locally, always fetch fresh.

## Design Language: Liquid Glass
- **The movies are the product — UI chrome should stay quiet and never compete with poster art for attention.** Tabs, badges, buttons: default to the lighter/quieter option (outlined over filled, plain text over solid color pills) so posters and titles stay the visual focus. Called out directly (2026-07-11) after a Rankings-screen pass leaned too hard on solid colored pills and solid score badges.
- Navigation bars and tab bars use `.glassEffect()` (iOS 26 native)
- Floating card surfaces: `ultraThinMaterial` background + 1px border at 20% white opacity
- Color palette: deep cinematic blacks (#0A0A0F), warm gold accents (#F5C842), white text
- Typography: SF Pro Display for headers, SF Pro Text for body
- Animations: spring-based, `.matchedGeometryEffect` for poster transitions
- Heavy reference: Beli iOS app (470 screenshots in `Beli Design References/`). **Read `Docs/beli-design-notes.md` instead of re-analyzing the screenshots** — it's a full written analysis of all 470 images (colors, tab bar, feed/list/detail/onboarding patterns, what to clone vs. skip). Only open the raw screenshots for something the notes don't cover.
- **Beli is inspiration, not a template to clone.** For each Beli pattern, identify the underlying *reason* it exists (e.g. "they compare items pairwise instead of star-rating because pairwise comparison is easier to judge than an absolute number" / "they split Been from Want to Try because a restaurant list needs a planning half") and then design Popcorn's own answer to that same problem — don't copy Beli's exact visual solution. Stated directly (2026-07-11): "I'm concerned we'd end up looking like a knockoff... I want us to innovate and be creative, not just replicate Beli for movies."
- **In transition, not the whole app yet**: the Marquee feed and the Rankings/Lists screen have moved to a second, warm palette (cream background, brick-red accent, Libre Caslon serif — see `Cinema/DesignSystem/WarmTheme.swift`) instead of this dark/gold system. This is deliberate, tracked in `NOTES.md`, and meant to be reconciled app-wide in a later recalibration pass — don't "fix" the mismatch by reverting one or the other without being asked.
- **Top-of-screen label on warm-palette screens**: use `ScreenTitle("...")` (`Cinema/DesignSystem/WarmTheme.swift`) — confirmed as the look to reuse (2026-07-11) after the Lists screen's "My Lists" header landed well. Don't hand-roll a new font/size/color combo for a screen title; reuse this component so they can't drift apart.

## Supabase Schema (source of truth in Docs/schema.sql)
- `users` — profile, username, avatar_url, created_at
- `ranked_items` — user_id, tmdb_id, media_type, elo_score, rank_position, updated_at
- `elo_matches` — id, user_id, winner_tmdb_id, loser_tmdb_id, media_type, created_at
- `follows` — follower_id, following_id, created_at
- `feed_events` — id, user_id, event_type, tmdb_id, media_type, elo_score, created_at

## Key Credentials (set as env/secrets, never commit)
- `TMDB_API_KEY` — get from themoviedb.org
- Supabase URL + anon key — from Supabase project dashboard

These live in `Cinema/Core/Network/Secrets.swift`, which is gitignored and **does not exist in a fresh checkout** — it has to be recreated by hand on every new machine. Format:
```swift
enum Secrets {
    static let supabaseURL = "https://anvgcmahgudiojnrfzku.supabase.co"
    static let supabaseAnonKey = "..."
    static let tmdbReadAccessToken = "..."
}
```
If it's missing, the app will not compile (`Secrets.supabaseURL` etc. won't resolve). Ask the user for the values, or check whether they've already dropped the file somewhere odd (this has happened before — it once landed in the wrong folder entirely).

## Development Setup
1. Xcode 26+ required (iOS 26 target for `.glassEffect()`)
2. **No Node.js, npm, or Homebrew needed for anything in this project.** The app itself is pure SwiftUI/SPM. Building is still plain `xcodebuild`; running/inspecting the app goes through the built-in iOS Simulator tool (`mcp__Claude_Code_iOS_Simulator__*`, no install needed — see "Building, Running & Verifying" below) with `xcrun devicectl` for the physical device and a narrow XCUITest fallback for custom gestures. Don't register third-party alternatives (XcodeBuildMCP, ios-simulator-mcp, etc.) — they'd be redundant with what's already available. When a CLI tool genuinely is needed (`xcodegen`, `gh`), fetch the prebuilt macOS binary from its GitHub releases directly rather than installing Homebrew for it — both already live at `~/.local/bin/`, which is on `PATH`.
3. **`gh` (GitHub CLI) is installed** at `~/.local/bin/gh` but not authenticated — nothing in the current workflow needs it (commits push straight to `main`, no PR/issue workflow). Run `gh auth login` only if that changes.
4. Simulator is the default target for day-to-day work (no Apple Developer Team needed — `DEVELOPMENT_TEAM: ""` and unsigned builds work fine for `platform=iOS Simulator` destinations). Physical-device builds need a real Team ID in `project.yml`, which hasn't been set up yet — ask the user for it (Xcode → Settings → Accounts, or developer.apple.com → Membership) only when device testing actually becomes necessary.
5. Supabase: schema already applied to the live project (`Docs/schema.sql` is the source of truth if it ever needs reapplying). The project can get **paused** on the free tier — if API calls start failing with DNS/connection errors, that's the first thing to check; the user has to click "Restore" in the Supabase dashboard, it doesn't self-resume. A Personal Access Token for the Management API is saved at `~/.supabase/access-token`.
6. `git remote` uses SSH (`git@github.com:imsaahiljain/Cinema.git`), not HTTPS — an SSH key is already set up and added to the GitHub account. If push ever fails with a credential error on a new machine, generate a new `ed25519` key and have the user add it at github.com/settings/ssh/new.

## Coding Conventions
- One `@Observable` ViewModel per feature screen
- Network calls via `async/await`, never callbacks
- All TMDB types conform to `Codable` — no manual JSON parsing
- `DesignSystem/` exports a single `CinemaTheme` enum for colors/spacing
- No comments unless the WHY is non-obvious
- Commit after each working feature slice, not at end of session
- **Search for existing components/screens before building new ones.** This project has more built out than a fresh grep suggests — e.g. `PosterImage` (`Cinema/DesignSystem/GlassCard.swift`), `MovieInfoView` (a full movie-detail screen already wired from Search/Discover), and the rank→rating formula (`ratingOutOf10` in `MovieInfoViewModel.FriendTake`, `Cinema/Features/Discover/MovieInfoView.swift`) all already existed and were nearly rebuilt from scratch during the Feed work. Grep for the concept before writing new UI or logic.
- **No hardcoded pixel/point dimensions for layout.** Sizes tuned by eyeballing one simulator/device look "right" there and wrong on every other screen size. Use `GeometryReader`/proportional sizing (fractions of available width/height), `.safeAreaInset`/safe-area-relative spacing instead of a guessed padding constant, and Dynamic Type-aware fonts (`.font(.system(.body, ...))` / relative scaling) rather than fixed point sizes, so screens scale correctly across the full iPhone size range, not just whichever one was open at the time. Flagged directly after a bucket-of-popcorn Feed prototype was hardcoded to one screen size (fixed `232pt` container height, `58pt` kernel size) and looked wrong as a result.

## Git Workflow (Claude must follow this)
**Always commit working changes to GitHub.** Do not let sessions end with uncommitted code.

Commit command pattern:
```bash
git add Cinema/ CinemaUITests/ Docs/ Cinema.xcodeproj/ project.yml
git commit -m "message"
git push origin main
```

Never add: `supabase/` (local CLI artifacts), `Cinema.xcodeproj/xcuserdata/`, `.DS_Store`, `Cinema/Core/Network/Secrets.swift` (all already gitignored — this is just a reminder of what NOT to force-add).

## Supabase Workflow (Claude must follow this)
Never ask the user to touch the Supabase dashboard for routine work. **The Supabase CLI is not installed on this Mac and should not be assumed to be** (a prior version of this doc assumed it was linked — it wasn't, on this machine). Two working paths instead, both plain `curl`, no install needed:

**Data-level work (create test users, seed rows, query tables)** — use the REST API with the anon key from `Secrets.swift`:
```bash
# Sign up a test user directly (skips the whole onboarding UI)
curl -s -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" -d '{"email":"...","password":"..."}'
# → returns access_token + user.id; use that Bearer token for authenticated inserts,
#   e.g. POST /rest/v1/users with {"id":..., "username":..., "onboarded": true}
```
This is much faster than driving the full 12-step onboarding flow (with real Contacts/Notifications system permission dialogs) through the UI just to get a usable account — see the UI Testing section below.

**Schema/project-admin work (DDL changes, auth config)** — use the Supabase Management API with the Personal Access Token stored at `~/.supabase/access-token` (outside the repo, gitignored-equivalent — never commit it):
```bash
curl -s "https://api.supabase.com/v1/projects/anvgcmahgudiojnrfzku/..." \
  -H "Authorization: Bearer $(cat ~/.supabase/access-token)"
```
The project's `service_role` key (bypasses Row Level Security for admin-level *data* operations, separate from the PAT which is for project/account-level management) is not held — ask the user for it (Settings → API in the dashboard) if that specific need comes up.

## Building, Running & Verifying (Claude must follow this)

**Never report a visual/UI change as done without actually looking at a screenshot yourself first.** Build → install → launch → screenshot → look at the image → fix what's visibly wrong → only then tell the user it's ready. Describing a change instead of verifying it (or installing straight to the user's physical device without a simulator look first) has produced real, embarrassing bugs that a screenshot would have caught immediately (a broken layout rendering off-screen, cropped images, mismatched colors) — each one cost several rounds of back-and-forth to diagnose and fix. The simulator loop is fast; use it before every device install, not instead of one.

Compiling is still real `xcodebuild` no matter which path below you take — nothing makes Swift itself compile faster. What's different is everything *after* a build: driving and inspecting the running app goes through the **iOS Simulator tool** (`mcp__Claude_Code_iOS_Simulator__*`), which replaced the old `xcrun simctl` + XCUITest loop as the default. XCUITest is kept, but only for one specific gap — see below.

### Regenerate the Xcode project when Swift files are added, moved, or removed
`Cinema.xcodeproj` uses explicit file references (not Xcode 16's auto-sync folders), so new files are invisible to the build until regenerated:
```bash
xcodegen generate --spec project.yml   # xcodegen is on PATH at ~/.local/bin/xcodegen
```
If `xcodegen` isn't found, fetch it fresh (no Homebrew needed, prebuilt binary):
```bash
curl -sL -o /tmp/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.45.4/xcodegen.zip
unzip -q /tmp/xcodegen.zip -d /tmp/xcodegen_install
mkdir -p ~/.local/bin && cp /tmp/xcodegen_install/xcodegen/bin/xcodegen ~/.local/bin/xcodegen
```
Known gotcha: xcodegen silently re-adds `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` as a default even if omitted from `project.yml` — since no `AppIcon` asset set exists yet, this breaks the build. `project.yml` explicitly sets it to `""` to blank it out; don't remove that line until a real app icon asset is added.

**Known gotcha, more important: `xcodegen generate` regenerates `Cinema/Resources/Info.plist` from `project.yml`'s `targets.Cinema.info.properties` block on *every single run*.** Hand-editing `Info.plist` directly works until the next `xcodegen generate`, which silently reverts it. Always make Info.plist changes in `project.yml`'s `info.properties`, never in the `.plist` file directly.

### Building
Two equivalent paths — pick whichever fits the turn:

**The simulator tool's own build action** — headless, non-blocking, good when the rest of the turn is also simulator-tool calls:
```
mcp__Claude_Code_iOS_Simulator__build({action: "build", project_path: "/Users/saahiljain/Documents/Popcorn IOS/Cinema.xcodeproj", scheme: "Cinema", device: "iPhone 17"})
→ returns a build_id immediately
mcp__Claude_Code_iOS_Simulator__build({action: "build_status", build_id: "..."})
→ poll this; on success it returns the built .app path plus a ready-to-paste launch call
```

**Plain `xcodebuild` in Bash** — identical result, better when the same turn also needs Bash for something else (seeding Supabase data, git, etc.) and switching tools mid-turn isn't worth it:
```bash
xcodebuild -scheme Cinema -project Cinema.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/Cinema_build build
```

### Installing, launching, and interacting — the simulator tool, as the default
```
control({action: "attach"})                                    # open the live panel — cheap, do it early
control({action: "launch", app_path: "<.app path from a build above>"})   # installs + launches; replaces simctl install+launch
control({action: "screenshot"})
control({action: "tap", x, y})
control({action: "text", text: "..."})                          # types into whatever field currently has focus
control({action: "swipe", x, y, x2, y2, duration})
control({action: "button", name: "HOME"})                       # background the app
```

**Coordinate gotcha — this will bite you if you skip it.** `tap`/`swipe`/`touch_path` all take device *points*, not the pixel dimensions of the screenshot image you're looking at (`attach` reports the exact point size, e.g. "402x874 points"). Compute the ratio once — `scale = point_width / screenshot_pixel_width` — and apply it to both x and y when reading a coordinate off a screenshot before tapping. Getting this wrong taps silently in the wrong place with no error; always re-screenshot immediately after a tap to confirm it actually landed where intended, don't chain multiple blind taps.

**Don't eyeball the screenshot's pixel dimensions — measure them.** A real incident (2026-07-25): guessing the screenshot's pixel width/height by visual estimation, one lucky coincidental tap "confirmed" a scale factor that was actually wrong, and every subsequent tap for the next ~15 tool calls (all of it burned on repeated screenshot round-trips, which are token-expensive) landed ~250 points away from the intended button because the bad ratio was never re-checked against ground truth. The fix takes one command and should happen *before* the first tap, not after several have already failed: `xcrun simctl io <udid> screenshot /path/to/file.png && sips -g pixelWidth -g pixelHeight /path/to/file.png` gives the screenshot's *real* pixel size, which combined with the point size `attach` already reports gives an exact scale (this device is a clean 3.0x — @3x retina). Do this once at the start of any tap-heavy verification session, not as a last resort after guessing has already failed repeatedly.

**This same mistake repeated on 2026-07-27, worse, and burned a huge chunk of a 5-hour credit budget in about 10 minutes.** Root cause, precisely: mid-session, coordinate-finding drifted away from the one-true-method above and started mixing three different sources of "where is this element" — (1) the simulator control tool's own inline screenshot render, (2) the Read tool's auto-resized preview of a raw file (which comes with its own separate "displayed at WxH, multiply by R" hint), and (3) actual measured crops of the raw `simctl io screenshot` file. These three have *different* pixel dimensions and different scale factors from each other. Treating them as interchangeable — eyeballing a coordinate off whichever image happened to be on screen, instead of always doing the same fixed arithmetic — produced tap coordinates that were sometimes off by a wrong multiplier, and at least twice were pixel values passed straight into `tap()` with the ÷3 step to convert to points simply forgotten (e.g. calling `tap(x, 1683)` on a device that is only 874 points tall — a value that large is *only* possible if it's still in pixels). Each bad tap silently missed, which meant another full screenshot round-trip just to discover and re-diagnose it. This is exactly the "repeating a mistake that's already been diagnosed" failure mode called out in the Working Agreement above — the fix was already written down two paragraphs up, and it still didn't get followed consistently.

**The hardened procedure — follow this exactly, every time, no shortcuts:**
1. At the start of any tap-heavy verification stretch, run the `simctl io screenshot` + `sips` command above *once* and write down the resulting scale as a fixed constant for the rest of that stretch (e.g. "scale = 3.0, points = pixels ÷ 3"). Do not re-derive it from a different image later.
2. To find a tap target: save a screenshot with plain `xcrun simctl io <udid> screenshot <path>` (never the control tool's own screenshot, never a resized/auto-scaled preview) and crop it with a script (e.g. PIL) to the region of interest.
3. Read *that* crop file. Estimate the target's center in pixels *within that same raw file's coordinate space* — add back any crop offset you applied.
4. Divide both x and y by the fixed scale constant from step 1 to get points. This is the only number that ever gets passed to `tap`/`swipe`.
5. **Sanity-check before tapping**: if x is outside `[0, point_width]` or y is outside `[0, point_height]` (e.g. y > 874 on this device), that is proof the ÷scale step was skipped or a wrong image's dimensions were used — stop and redo steps 2–4, don't tap the out-of-range value "to see what happens."
6. Tap once, then immediately take a fresh screenshot before doing anything else. Never chain a second blind tap off an assumed result.
7. If a tap visibly misses, don't retry with another guess — go back to step 2 with a brand-new screenshot.

**State persists between launches.** The simulator keeps the app's install and its Supabase session across relaunches, so there's normally no need to re-run any login flow — whatever account was last signed in (usually the seeded QA account, `qatest1@example.com` / `TestPass123`) is still signed in the next time you attach. Only sign in again if the simulator itself was erased.

### When to still reach for XCUITest
One real, confirmed gap: `touch_path` (the tool's smooth multi-point drag) did not reliably trigger the This-or-That screen's SwiftUI `DragGesture`-based swipe-to-pick, across several attempts with different start points, speeds, and durations — while XCUITest's `press(forDuration:thenDragTo:)` reliably does commit a pick the same way. `CinemaUITests/CinemaUITests.swift` stays in the project for exactly this category of check — a custom drag/gesture interaction the simulator tool's synthesized touch events don't seem to reach — not for navigation, taps, typing, or general verification, all of which the simulator tool now handles in a couple seconds instead of the old 60–90 second edit-test/rebuild/replay-from-login loop.

If a gesture genuinely needs XCUITest, add a test method per navigation step, then:
```bash
xcodebuild test -scheme Cinema -project Cinema.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CinemaUITests/CinemaUITests/<testName>
```
Run it in the background piped to a log file, and screenshot only once the log shows the specific action's line (e.g. `grep -q 'Tap "X" Button'`) — a blind `sleep N` either fires too early or (once) fired after the test had already torn down. There's a `pause(seconds:)` helper in the test file that keeps the app alive after the last action so there's a window to screenshot in. Use the `login()` helper against the seeded QA account rather than automating the full 12-step onboarding flow (live Contacts/Notifications system dialogs make it slow and flaky to script). Create additional seeded accounts via the Supabase REST API (below) when a fresh account is genuinely needed.

Known gap: the main tab bar's buttons have no explicit `.accessibilityLabel()`, so XCUITest sees them by raw SF Symbol name (e.g. `"Numbered List"` instead of `"Lists"`). Worth a one-line fix next time that file is touched.

### Physical device — unchanged, the simulator tool doesn't reach here
The iOS Simulator tool is simulator-only. The paired physical device (Saahil Jain's iPhone) still goes through `xcrun devicectl`:
```bash
xcodebuild -scheme Cinema -project Cinema.xcodeproj \
  -destination 'platform=iOS,name=Saahil Jain’s iPhone' \
  -derivedDataPath /tmp/Cinema_build_device build
xcrun devicectl device install app --device <udid> /tmp/Cinema_build_device/Build/Products/Debug-iphoneos/Cinema.app
xcrun devicectl device process launch --device <udid> com.mtgcardneeder.Cinema
```
Always verify on the simulator first, then push the same build to the device — per the working agreement, device installs happen *after* every verified change, not instead of a simulator look. If launch fails with a "Locked" error, the install already succeeded — the device just needs unlocking; that's not a build problem.

**Needs a USB cable, at least the first time.** `xcrun devicectl list devices` / `xcrun xctrace list devices` showing the phone as `unavailable` / "Devices Offline" even though it's unlocked and on the same Wi-Fi as the Mac (confirmed 2026-08-15) almost always means wireless debugging was never turned on for this device — that feature requires pairing over a cable at least once (Xcode's Devices and Simulators window, "Connect via network" checkbox) before Wi-Fi-only installs work at all. No cable in hand in that moment means no install, full stop — this isn't something to keep retrying blindly. Tell the user plainly and wait for a cable rather than hunting for a workaround.

### Known gotcha: iOS Simulator tool usage once broke Documents access mid-session
Using the simulator tool caused this session's shell to lose read/write access to the entire `~/Documents` folder (an interaction with macOS's `disclaimer` sandboxing wrapper — root cause not fully nailed down) until the chat session was restarted. If Bash/Read/Edit suddenly start failing with a bare "Operation not permitted" on project files after using the simulator tool, this is almost certainly it. Restarting the session fixed it; chasing System Settings → Privacy & Security did not (that was a wrong first guess — don't repeat it).
