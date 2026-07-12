# Notes

Freeform notes-to-self, captured verbatim whenever you say "note to self" in conversation. This is not a spec or a task list — just a running scratchpad of things on your mind. Check it whenever you ask "what notes do I have?" or similar.

---

- (2026-07-08) The Discover page doesn't seem very Gen Z.
- (2026-07-08) make feed called popcorn and each of the posts is a "pop"
- (2026-07-09) change onboarding flow from email+password into google-account everything else same
- (2026-07-09) missing back arrows in onboarding
- (2026-07-09) Note to self post production: iterate on the popcorn bucket with pops features
- (2026-07-09) Note to self: make sure all the elements are cohesive. We're doing it tab by tab, feature by feature right now, which means each feature looks a bit different and won't look as cohesive — fix that at the end with an overall recalibration pass. (Context: moving away from the pure-black-with-yellow "Cinema" theme since apps like Letterboxd don't go pure black either, it's too harsh; the Marquee feed's warm/laid-back tone is fine for now but needs to be reconciled with everything else eventually.)
- (2026-07-09) add the TV rating of movies like PG-13, R, MA, et cetera in their movie info thingy
- (2026-07-11) score color-coding by band (green/yellow/red) — keeping the idea, but haven't decided the cutoffs yet, decide later
- (2026-07-11) Pre-production checklist item: right before going to production, audit every screen to make sure all Supabase backend work is actually tied to the UI — no leftover placeholders, no stubbed data, no lagging/loading states that never resolve. (Prompted by finding two things that should've already been wired: the real Marquee feed built July 9 was never connected to the Feed tab, and the Watchlist tab was left as a placeholder even though its Supabase table already existed and was live.)
