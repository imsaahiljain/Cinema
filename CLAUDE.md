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

## Post-Production Backlog (polish/features to come back to later — not blocking current work)
- **Multiple winning animations for This or That** — once the rebuilt ranking screen has one good "you picked this one" animation, add several more and rotate/randomize between them so the screen feels dynamic rather than repeating the same transition every battle. First candidate already saved: `Cinema/Features/Ranking/WinEffects/DiagonalOverarchWinEffect.swift` (winner slides diagonally across and overarches the loser) — built during the swipe-prototype pass, needs minor tweaking but is ready to become one of several selectable variants rather than rebuilt from scratch.
- **Separate onboarding variant of This or That** — the 10-Movie Wall needs its own version of the ranking screen with an added "I haven't watched one of these" button. Tapping it changes the top prompt to ask which film the user *has* seen (put that phrasing in the question area at the top) and requires tapping the poster of the one they've watched, rather than a normal pairwise pick.
- **Decision-time-weighted ranking algorithm** — go beyond fixed-K ELO (K=32) by also factoring in how long the user took to decide (fast pick = high confidence = bigger rating swing, long hesitation = low confidence = smaller swing) plus other behavioral signals, closer to how Glicko/TrueSkill model rating confidence rather than plain ELO. Separate work from the visual/gesture rebuild — touches `ELOService` and `RankingViewModel.selectPair`/`choose`.
- **Custom sound effects for This or That** — swipe/commit/win moments should eventually have short custom SFX (not generic iOS system sounds) to match the haptic feedback. Needs either sourcing a few licensed/royalty-free short clips or synthesizing simple tones in-app; punt until the swipe + haptics interaction itself is built and feels right.
- **More Search grid tags beyond "New"** — the tag system (`Cinema/Features/Search/SearchView.swift`, `SearchGridTile`, sits in the year's slot in the caption) is deliberately launching with just `MediaItem.isRecentRelease` ("New"). The next candidate is a legitimacy/recognition tag (working name "Popular") based on `voteCount` clearing some threshold — the thing that actually would have disambiguated "Minions" from knockoffs like "Minion Scouts," which "New" doesn't address at all. Don't build it until there's real usage data to pick a sane vote-count cutoff — the one real number checked so far (Minions & Monsters, a real 2026 release the user watched and liked, sitting at ~208 votes) shows a naive high threshold (1,000+) would unfairly exclude a legitimately good, just-new movie. Needs a smarter rule than a flat cutoff, or needs to coexist with "New" rather than replace it for brand-new titles.

## What This Is
Popcorn is a high-velocity social media app for movie/TV taste. Think Beli for restaurants, but for film. Users rank media via pairwise ELO ("This or That"), build a ranked list, and share taste with friends via a social feed.

## Current Status & Working Agreement (as of 2026-07-08 — check git log before trusting this is still current)

**Branch:** `main` is the working branch. There was a `v2-rebuild` branch where features had been deliberately stripped to stubs for a from-scratch rebuild with a nicer tab bar; after comparing both live in the simulator, the user chose to consolidate back onto `main` instead, since it already has more built-out screens (Profile, Search, Discover all have real content; `v2-rebuild`'s equivalents were still stubs). `v2-rebuild` still exists on GitHub and has two things worth cherry-picking onto `main` if not already done by the time you read this: (1) a nicer floating glass-pill tab bar, and (2) a fix for a real bug — **the core "This or That" ranking flow existed as a screen but was never wired to any button anywhere in the app**; adding a film via Search/Discover just silently upserted a flat ELO score instead of triggering a comparison battle. Check whether `Cinema/Features/Search/SearchView.swift` and `Cinema/Features/Discover/MovieInfoView.swift` already launch `RankingView` after adding a film — if not, that port still needs to happen.

**Working style the user has explicitly asked for:**
- **One feature at a time.** Implement it, verify it actually works (build + real interaction via XCUITest, not just "it compiles"), then stop and let the user react before starting the next one. Don't batch multiple features into one pass even if they feel related — this was called out directly after Ranking/Search/Discover/Lists all got built together in one go.
- **Be transparent, not just fast, when something isn't working.** If a debugging approach is fundamentally wrong (e.g. screen-pixel clicking), say so and switch rather than iterating blindly on the wrong tool.
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
2. **No Node.js, npm, or Homebrew needed for anything in this project.** The app itself is pure SwiftUI/SPM. Tooling (XcodeBuildMCP, ios-simulator-mcp, etc.) is unnecessary — everything below is driven directly through `xcodebuild`/`xcrun simctl`/XCUITest, which ship with Xcode. Don't register those MCP servers; if asked to, explain this instead. When a CLI tool genuinely is needed (`xcodegen`, `gh`), fetch the prebuilt macOS binary from its GitHub releases directly rather than installing Homebrew for it — both already live at `~/.local/bin/`, which is on `PATH`.
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

The project is driven entirely through `xcodebuild` / `xcrun simctl` / XCUITest — no XcodeBuildMCP, no ios-simulator-mcp, no Node. All commands below run straight in Bash.

**Never report a visual/UI change as done without actually looking at a screenshot yourself first.** Build → install → launch → screenshot → Read the PNG → fix what's visibly wrong → only then tell the user it's ready. Describing a change instead of verifying it (or installing straight to the user's physical device without a simulator look first) has produced real, embarrassing bugs that a screenshot would have caught immediately (a broken layout rendering off-screen, cropped images, mismatched colors) — each one cost several rounds of back-and-forth to diagnose and fix. The simulator loop is fast; use it before every device install, not instead of one.

**Regenerate the Xcode project when Swift files are added, moved, or removed.** `Cinema.xcodeproj` uses explicit file references (not Xcode 16's auto-sync folders), so new files are invisible to the build until regenerated:
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

**Known gotcha, more important: `xcodegen generate` regenerates `Cinema/Resources/Info.plist` from `project.yml`'s `targets.Cinema.info.properties` block on *every single run*.** Hand-editing `Info.plist` directly (adding a key, changing a string like `NSContactsUsageDescription`) works until the next `xcodegen generate`, which silently reverts it back to whatever `project.yml` says. Always make Info.plist changes in `project.yml`'s `info.properties`, never in the `.plist` file directly. This cost real time twice in one session: once discovering the gotcha itself, and again because a fix made on a feature branch didn't get carried back to `main` and silently reverted there too the next time `main`'s `project.yml` was regenerated from.

**Build for the simulator:**
```bash
xcodebuild -scheme Cinema -project Cinema.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/Cinema_build build
```

**Install, launch, and screenshot:**
```bash
xcrun simctl list devices available          # get the device UDID
xcrun simctl install <udid> /tmp/Cinema_build/Build/Products/Debug-iphonesimulator/Cinema.app
xcrun simctl launch <udid> com.mtgcardneeder.Cinema
xcrun simctl io <udid> screenshot /path/to/screenshot.png   # then Read the PNG to actually look at it
```

**Interacting with the app (tapping, typing) — use XCUITest, never screen-pixel automation.** A `CinemaUITests` UI-testing target already exists (`CinemaUITests/CinemaUITests.swift`). Driving the simulator via `osascript`/System Events by screenshotting the whole Mac screen and clicking computed pixel coordinates was tried first and failed repeatedly — window position drift, fragile coordinate math, one click even landed in an unrelated Mac app. XCUITest instead finds elements by accessibility label (`app.buttons["Sign In"].tap()`), which works regardless of window position or size. Add a test method per navigation step you need, then:
```bash
xcodebuild test -scheme Cinema -project Cinema.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CinemaUITests/CinemaUITests/<testName>
```
Run it in the background piped to a log file, and take your `simctl` screenshot only once the log shows the specific action's line (e.g. `grep -q 'Tap "X" Button'`) — a blind `sleep N` either fires too early or (once) fired after the test had already torn down and the app was back on the home screen. There's a `pause(seconds:)` helper in the test file that keeps the app alive after the last action so there's a window to screenshot in.

For a logged-in state, use the `login()` helper against the seeded QA account (`qatest1@example.com` / `TestPass123`) rather than automating the full onboarding flow — the real onboarding has 12 steps including live Contacts/Notifications system permission dialogs, which is slow and flaky to script. Create additional seeded accounts via the Supabase REST API (above) when a fresh account is genuinely needed.

Known gap: the main tab bar's buttons currently have no explicit `.accessibilityLabel()`, so XCUITest sees them by their raw SF Symbol name (e.g. `"Numbered List"` instead of something like `"Lists"`). Worth fixing with a one-line `.accessibilityLabel(...)` per tab item next time that file is touched — makes both testing and real accessibility better.
