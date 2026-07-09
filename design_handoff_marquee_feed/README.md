# Handoff: Popcorn Feed — "Marquee" (design 1b)

## Overview
The Popcorn Feed is the home screen of Popcorn, a social app for friends to share what movies/TV they're watching. Each post is called a "pop." This is the selected direction ("Marquee") — a warm, cozy, ticket-stub-styled vertical card feed.

## About the Design Files
The files in this bundle are **design references created in HTML/React (JSX)** — prototypes showing intended look and behavior, not production code to copy directly. The task is to **recreate this design in the target codebase's existing environment** (this is an iOS app — likely SwiftUI or UIKit) using its established patterns and libraries. If no environment exists yet, choose the framework best suited to an iOS app and implement there.

## Fidelity
**High-fidelity.** Colors, typography, spacing, and card layout below are final; recreate pixel-close using native iOS equivalents (SF Symbols where a generic icon is acceptable, but keep the custom "poster" placeholder and ticket-stub perforation as designed).

## Screen: Feed ("Marquee")

### Purpose
Scrollable list of friends' pops (movie/TV posts), each showing who posted, what they watched, their rating, a caption, tags, and reaction counts.

### Layout
- Full-screen vertical scroll, background `oklch(0.96 0.015 70)` (warm cream).
- Sticky header at top: app wordmark "Popcorn" in serif display font, size 30px, color `oklch(0.32 0.03 40)`, plus subtitle "What your friends are watching" at 12px, `oklch(0.5 0.02 40)`. Header has ~56px top padding to clear the iOS status bar / Dynamic Island.
- Below header: vertical list of pop cards, 16px gap between cards, 16px horizontal page margin.

### Pop card component
Each card is a horizontal flex row, white background (`#fff`), 16px border radius, overflow hidden, drop shadow: `0 1px 2px rgba(60,30,10,0.06), 0 6px 20px rgba(60,30,10,0.08)`. Entire card is tappable (expands caption + tags on tap — see Interactions).

Card contents left→right:
1. **Poster thumbnail** — 96px fixed width, full card height, striped placeholder (repeating diagonal stripes in the friend's hue) with centered monospace "POSTER" label — replace with real poster art fetched from a movie DB in production.
2. **Ticket perforation** — a 2px dashed vertical line (`oklch(0.9 0.02 60)`) between poster and text, with two 14px circular cutouts (matching page background color) punched at the top and bottom of the line, to read as a ticket-stub tear edge.
3. **Content column** (flex: 1, 14px/16px padding, 8px vertical gap):
   - Row: 22px circular avatar (initials on a solid color chip, color = `oklch(0.62 0.11 {friend hue})`), friend name (12.5px, weight 700, `oklch(0.4 0.02 40)`), timestamp ("· 2h", 11.5px, `oklch(0.6 0.02 40)`).
   - Row: movie title in serif display font, 19px, `oklch(0.25 0.02 40)` — and a rating pill, right-aligned, serif 15px weight 700, white text on `oklch(0.55 0.18 30)` background, 8px radius, `2px 8px` padding.
   - Caption text, 13.5px, `oklch(0.35 0.02 40)`, line-height 1.4. Clamped to 2 lines by default (`-webkit-line-clamp: 2`).
   - Tag chips (collapsed by default, revealed on tap): 11px pill chips, text `oklch(0.5 0.14 75)` on `oklch(0.94 0.05 85)` background, 6px/9px padding, weight 600.
   - Reaction row: "♥ {likes}" and "💬 {comments}", 12px, `oklch(0.5 0.02 40)`, weight 600. (Replace glyphs with proper heart/comment icons in production.)

## Interactions & Behavior
- Tapping anywhere on a card toggles an "expanded" state for that card: caption unclamps to full text, and the tag chip row animates open (`max-height` 0 → 40px, 0.2s transition).
- List scrolls natively; header is `position: sticky` at the top of the scroll container.
- No pull-to-refresh or compose flow implemented in this prototype — flag as a follow-up if needed.

## State Management
- One piece of state: a set/map of which card IDs are "expanded" (booleans keyed by pop id). Toggled on card tap. No persistence needed across sessions in the prototype.

## Design Tokens

**Colors** (oklch):
- Background: `oklch(0.96 0.015 70)`
- Card background: `#ffffff`
- Primary text (title/name): `oklch(0.25 0.02 40)` / `oklch(0.4 0.02 40)`
- Secondary text (timestamp/caption/reactions): `oklch(0.5–0.6 0.02 40)`
- Accent (rating pill, ticket color): `oklch(0.55 0.18 30)` — warm brick red
- Tag chip: text `oklch(0.5 0.14 75)`, bg `oklch(0.94 0.05 85)` — mustard
- Avatar chip fill: `oklch(0.62 0.11 {hue})` where hue varies per friend (arbitrary per-friend identity color)

**Typography:**
- Display/serif (wordmark, movie titles, rating pill): **Libre Caslon Text** (Google Font)
- Body (everything else): **Nunito Sans** (Google Font)

**Spacing/radius:**
- Card radius: 16px. Avatar/poster corners: circular / straight (poster has no radius, card clips it).
- Page margin: 16px. Card gap: 16px. Content padding: 14px top/bottom, 16px sides.

**Shadow:** `0 1px 2px rgba(60,30,10,0.06), 0 6px 20px rgba(60,30,10,0.08)`

## Assets
- No real images used. Posters are CSS-generated striped placeholders (diagonal repeating-linear-gradient in the friend's hue) with a monospace "POSTER" label — swap for real movie poster art (e.g. TMDB) in production.
- Avatars are generated initials chips — swap for real profile photos.

## Files in this bundle
- `Popcorn Feed Options.dc.html` — full prototype file (contains 1a/1b/1c feed explorations + 2a Bucket concept). The Marquee design is the `FeedMarquee` component, shown as option `1b`.
- `popcorn-scenes.jsx` — source for all feed components, incl. `FeedMarquee` (the one to build) and shared `DATA`, `Avatar`, `Poster` helpers used within it.
- `ios-frame.jsx` — iPhone device-frame chrome used only for prototype presentation; not part of the design itself.

Sample data (7 pops) used in the prototype is in `popcorn-scenes.jsx`'s `DATA` array near the top of the file — useful as a reference for the exact copy/values shown (friend names, movies, ratings, captions, tags, like/comment counts).
