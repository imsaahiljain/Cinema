# Cinema — CLAUDE.md

## Open Action Items (things only the user can do — check this whenever asked "any action items left?")
- **Apple Developer Team ID** — not set (`DEVELOPMENT_TEAM: ""` in `project.yml`). Not blocking simulator work, but required before any physical-device build or TestFlight. Get it from Xcode → Settings → Accounts, or developer.apple.com → Membership Details.
- ~~Supabase Personal Access Token~~ — done, saved at `~/.supabase/access-token` (outside the repo, never committed). Verified working against `api.supabase.com/v1/projects`.
- **Supabase `service_role` key** — still not held. Only needed for admin-level data operations that bypass Row Level Security; the PAT above covers schema/project-config changes. From the project's Settings → API in the Supabase dashboard, if it ever comes up.

## What This Is
Cinema is a high-velocity social media app for movie/TV taste. Think Beli for restaurants, but for film. Users rank media via pairwise ELO ("This or That"), build a ranked list, and share taste with friends via a social feed.

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
- Navigation bars and tab bars use `.glassEffect()` (iOS 26 native)
- Floating card surfaces: `ultraThinMaterial` background + 1px border at 20% white opacity
- Color palette: deep cinematic blacks (#0A0A0F), warm gold accents (#F5C842), white text
- Typography: SF Pro Display for headers, SF Pro Text for body
- Animations: spring-based, `.matchedGeometryEffect` for poster transitions
- Heavy reference: Beli iOS app (470 screenshots in `Beli Design References/`). **Read `Docs/beli-design-notes.md` instead of re-analyzing the screenshots** — it's a full written analysis of all 470 images (colors, tab bar, feed/list/detail/onboarding patterns, what to clone vs. skip). Only open the raw screenshots for something the notes don't cover.

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
