# Cinema — CLAUDE.md

## What This Is
Cinema is a high-velocity social media app for movie/TV taste. Think Beli for restaurants, but for film. Users rank media via pairwise ELO ("This or That"), build a ranked list, and share taste with friends via a social feed.

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
- Heavy reference: Beli iOS app (470 screenshots in `Beli Design References/`)

## Supabase Schema (source of truth in Docs/schema.sql)
- `users` — profile, username, avatar_url, created_at
- `ranked_items` — user_id, tmdb_id, media_type, elo_score, rank_position, updated_at
- `elo_matches` — id, user_id, winner_tmdb_id, loser_tmdb_id, media_type, created_at
- `follows` — follower_id, following_id, created_at
- `feed_events` — id, user_id, event_type, tmdb_id, media_type, elo_score, created_at

## Key Credentials (set as env/secrets, never commit)
- `TMDB_API_KEY` — get from themoviedb.org
- Supabase URL + anon key — from Supabase project dashboard

## Development Setup
1. Xcode 26+ required (iOS 26 target for `.glassEffect()`)
2. Apple Developer account connected in Xcode (paid $99/yr — enables device testing + TestFlight)
3. Run on physical iPhone via Xcode → Product → Run
4. Supabase: apply `Docs/schema.sql` to your project

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
git add Cinema/ Docs/ Cinema.xcodeproj/xcshareddata/
git commit -m "message"
git push origin main
```

Never add: `supabase/` (local CLI artifacts), `Cinema.xcodeproj/xcuserdata/`, `.DS_Store`

## Supabase Workflow (Claude must follow this)
Never ask the user to touch the Supabase dashboard. Use the CLI:
```bash
echo "YOUR SQL;" | supabase db query --linked
```
Auth config changes via Management API:
```bash
curl -X PATCH https://api.supabase.com/v1/projects/anvgcmahgudiojnrfzku/config/auth \
  -H "Authorization: Bearer $(cat ~/.supabase/access-token)" \
  -H "Content-Type: application/json" \
  -d '{...}'
```
The Supabase CLI is installed, authenticated, and the project is linked. Token is in memory.

## Build & Run
```bash
# Build for device
xcodebuild -scheme Cinema -project Cinema.xcodeproj -destination 'id=BBC55267-7020-5449-A572-EA4E1820A874' build

# See the screen (iPhone Mirroring must be open)
screencapture -x /tmp/screen.png

# Click at coordinates (requires Accessibility permission for terminal)
osascript -e 'tell application "System Events" to click at {x, y}'
```
