import SwiftUI
import Supabase

// MARK: - Supporting Types

struct FriendTake: Identifiable {
    let id: UUID
    let user: CinemaUser?
    let displayName: String
    let username: String
    let rankPosition: Int?
    let totalRanked: Int
    var isSelf: Bool = false

    // Linear scale: #1 of N = 10.0, #N of N = 0.0
    var ratingOutOf10: Double? {
        guard let pos = rankPosition, totalRanked > 1 else { return rankPosition == 1 ? 10.0 : nil }
        return max(0, (1.0 - Double(pos - 1) / Double(totalRanked - 1)) * 10.0)
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class MovieInfoViewModel {
    var credits: TMDBCredits?
    var watchProviders: TMDBRegionProviders?
    var trailerKey: String?
    var director: TMDBPerson?
    var creators: [TMDBPerson] = []
    var bookAuthors: [TMDBPerson] = []
    var contentRating: String?
    var tagline: String?
    var collectionName: String?
    var isInTheaters = false
    var friendTakes: [FriendTake] = []
    var isLoading = false

    var noteDraft: String = ""
    private var savedNote: String = ""
    var isSavingNote = false
    var noteDirty: Bool { noteDraft != savedNote }

    func load(film: MediaItem, currentUserID: UUID?) async {
        isLoading = true
        defer { isLoading = false }

        credits = try? await TMDBClient.shared.credits(tmdbID: film.id, mediaType: film.mediaType)
        director = credits?.crew.first(where: { $0.job == "Director" })
        // TMDB credits the source material under two different job titles depending on whether
        // it's fiction or non-fiction — "Novel" (e.g. Andy Weir for Project Hail Mary, Frank
        // Herbert for Dune) vs "Book" (e.g. the Oppenheimer biography's authors). Both mean the
        // same thing to a viewer, so both get folded into one "Author" role. Naturally empty for
        // anything with an original screenplay — no special-casing needed.
        var seenAuthorIDs = Set<Int>()
        bookAuthors = (credits?.crew ?? [])
            .filter { $0.job == "Novel" || $0.job == "Book" }
            .filter { seenAuthorIDs.insert($0.id).inserted }
            .map { TMDBPerson(id: $0.id, name: $0.name, job: "Author", character: nil, profilePath: $0.profilePath, order: nil) }
        watchProviders = try? await TMDBClient.shared.watchProviders(tmdbID: film.id, mediaType: film.mediaType)
        // TMDB's own "now playing" list, fetched fresh every time this screen opens — not a
        // fixed release-date heuristic, so the "In Theaters Now" chip stops showing itself the
        // moment TMDB shows this title has left theaters, no manual expiry logic needed.
        if film.mediaType == .movie, let nowPlaying = try? await TMDBClient.shared.nowPlaying() {
            isInTheaters = nowPlaying.contains { $0.id == film.id }
        }
        trailerKey = await TMDBClient.shared.trailerKey(tmdbID: film.id, mediaType: film.mediaType)
        contentRating = await TMDBClient.shared.contentRating(tmdbID: film.id, mediaType: film.mediaType)
        (tagline, collectionName, creators) = await TMDBClient.shared.extras(tmdbID: film.id, mediaType: film.mediaType)

        if let uid = currentUserID {
            async let takes = loadFriendTakes(tmdbID: film.id, mediaType: film.mediaType, currentUserID: uid)
            async let note = loadNote(tmdbID: film.id, mediaType: film.mediaType, currentUserID: uid)
            friendTakes = await takes
            await note
        }
    }

    private func loadFriendTakes(tmdbID: Int, mediaType: MediaType, currentUserID: UUID) async -> [FriendTake] {
        struct JustID: Decodable { let id: UUID }

        var takes: [FriendTake] = []

        // "Or you" — the current user's own take shows first, if they've ranked it. Movie and
        // TV IDs are independent numbering spaces on TMDB (a movie #100 and a show #100 are
        // unrelated titles), so media_type has to be part of the match or this silently mixes
        // up two different titles once TV is enabled.
        if let mine: RankedItem = try? await SupabaseClient.shared
            .from("ranked_items").select()
            .eq("tmdb_id", value: tmdbID).eq("media_type", value: mediaType.rawValue)
            .eq("user_id", value: currentUserID)
            .single().execute().value {
            let allMine: [JustID] = (try? await SupabaseClient.shared
                .from("ranked_items").select("id").eq("user_id", value: currentUserID)
                .execute().value) ?? []
            takes.append(FriendTake(
                id: currentUserID, user: nil, displayName: "You", username: "",
                rankPosition: mine.rankPosition, totalRanked: allMine.count, isSelf: true
            ))
        }

        struct FollowEdge: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        guard let edges: [FollowEdge] = try? await SupabaseClient.shared
            .from("follows").select("following_id").eq("follower_id", value: currentUserID)
            .execute().value, !edges.isEmpty else { return takes }

        let ids = edges.map(\.followingID)
        guard let items: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items").select()
            .eq("tmdb_id", value: tmdbID).eq("media_type", value: mediaType.rawValue)
            .in("user_id", values: ids.map(\.uuidString))
            .execute().value, !items.isEmpty else { return takes }

        guard let profiles: [CinemaUser] = try? await SupabaseClient.shared
            .from("users").select()
            .in("id", values: items.map { $0.userID.uuidString })
            .execute().value else { return takes }

        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        for item in items {
            guard let user = profileMap[item.userID] else { continue }
            let allItems: [JustID] = (try? await SupabaseClient.shared
                .from("ranked_items").select("id").eq("user_id", value: item.userID)
                .execute().value) ?? []
            takes.append(FriendTake(
                id: item.userID, user: user,
                displayName: user.displayName ?? user.username,
                username: user.username,
                rankPosition: item.rankPosition,
                totalRanked: allItems.count
            ))
        }
        return takes
    }

    private func loadNote(tmdbID: Int, mediaType: MediaType, currentUserID: UUID) async {
        if let existing: FilmNote = try? await SupabaseClient.shared
            .from("film_notes").select()
            .eq("tmdb_id", value: tmdbID).eq("media_type", value: mediaType.rawValue)
            .eq("user_id", value: currentUserID)
            .single().execute().value {
            noteDraft = existing.note
            savedNote = existing.note
        }
    }

    func saveNote(tmdbID: Int, mediaType: MediaType, currentUserID: UUID?) async {
        guard let currentUserID, noteDirty else { return }
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            try await SupabaseClient.shared.from("film_notes")
                .upsert(["user_id": currentUserID.uuidString, "tmdb_id": String(tmdbID),
                         "media_type": mediaType.rawValue, "note": noteDraft])
                .execute()
            savedNote = noteDraft
        } catch {}
    }

    // Same default score / upsert shape as ListsViewModel.rankFilm — a film enters ranking at a
    // neutral 1500 and the battles do the rest. Only ever called when the film isn't ranked yet
    // (callers check `isRanked` first), so this never resets an existing real score.
    func rankFilm(tmdbID: Int, mediaType: MediaType, userID: UUID?) async {
        guard let userID else { return }
        try? await SupabaseClient.shared.from("ranked_items")
            .upsert(["user_id": userID.uuidString, "tmdb_id": String(tmdbID),
                     "media_type": mediaType.rawValue, "elo_score": String(1500.0)])
            .execute()
    }
}

// MARK: - MovieInfoView

struct MovieInfoView: View {
    let film: MediaItem
    @State private var vm = MovieInfoViewModel()
    @State private var selectedFriend: CinemaUser?
    @State private var showActions = false
    @State private var showAddToList = false
    @State private var showRanking = false
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Reuses the exact "You" signal Friends' Takes already computes from a real ranked_items
    // row — no separate state to track or fall out of sync with the rest of the screen.
    private var isRanked: Bool { vm.friendTakes.contains(where: \.isSelf) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CinemaTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    contentSection
                    Spacer().frame(height: 60)
                }
            }

            HStack(spacing: 14) {
                Button { showActions = true } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                .accessibilityLabel("Quick Actions")

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .task { await vm.load(film: film, currentUserID: appState.currentUser?.id) }
        .popover(isPresented: $showActions) {
            quickActionsMenu
                .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(tmdbID: film.id, mediaType: film.mediaType, title: film.title, posterPath: film.posterPath, userID: appState.currentUser?.id)
        }
        .fullScreenCover(isPresented: $showRanking, onDismiss: {
            Task { await vm.load(film: film, currentUserID: appState.currentUser?.id) }
        }) {
            RankingView()
        }
        .sheet(item: $selectedFriend) { friend in
            NavigationStack { UserProfileView(user: friend) }
        }
    }

    // MARK: - Quick Actions
    //
    // Everything you'd want to do with this film now lives on its own detail screen instead of
    // behind a "..." on a Search poster tile — same two actions, same wording, ported from the
    // grid-tile menu this replaces (Cinema/Features/Search/SearchView.swift, before it was
    // stripped down to poster-tap-only). "Rank This or That" upserts a fresh ranked_items row
    // at a neutral score only if this film isn't ranked yet — an already-ranked film's real
    // score is never touched, "Re-Rank" just reopens the battle screen.

    private var quickActionsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showActions = false
                showAddToList = true
            } label: {
                Label("Add to List", systemImage: "bookmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider().background(CinemaTheme.Colors.border)

            Button {
                showActions = false
                Task {
                    if !isRanked {
                        await vm.rankFilm(tmdbID: film.id, mediaType: film.mediaType, userID: appState.currentUser?.id)
                    }
                    showRanking = true
                }
            } label: {
                Label(isRanked ? "Re-Rank" : "Rank This or That", systemImage: "circle.grid.cross")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 230)
        .background(CinemaTheme.Colors.surface)
    }

    // MARK: - Hero (not zoomed — uses .fit so full image shows)

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let path = film.backdropPath, let url = TMDBClient.shared.backdropURL(path: path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fit)   // .fit = no cropping
                        default:
                            fallbackHero
                        }
                    }
                } else {
                    fallbackHero
                }
            }
            .frame(maxWidth: .infinity)
            .background(CinemaTheme.Colors.surface)

            // Gradient fades bottom of image into background
            LinearGradient(
                colors: [.clear, CinemaTheme.Colors.background],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 80)
        }
    }

    private var fallbackHero: some View {
        ZStack {
            CinemaTheme.Colors.surface
            if let path = film.posterPath, let url = TMDBClient.shared.posterURL(path: path) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill).blur(radius: 20).opacity(0.4)
                    }
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Title + meta
            VStack(alignment: .leading, spacing: 8) {
                Text(film.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let tagline = vm.tagline {
                    Text(tagline)
                        .font(.system(size: 13.5))
                        .italic()
                        .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if let rating = vm.contentRating {
                        Text(rating)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                        metaText("·")
                    }
                    if let year = film.releaseYear { metaText(year) }
                    if let rt = film.formattedRuntime { metaText("·"); metaText(rt) }
                    if let score = film.voteAverage, score > 0 {
                        metaText("·")
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(CinemaTheme.Colors.gold)
                            metaText(String(format: "%.1f", score))
                        }
                    }
                }

                // Rating is TMDB's own community score, not IMDb/RT — surfacing the vote count
                // here is what actually answers "is this rating trustworthy," right where someone
                // is deciding whether to believe it, rather than just asserting a bare number.
                if let score = film.voteAverage, score > 0, let count = film.voteCount {
                    Text("TMDB rating from \(count) \(count == 1 ? "rating" : "ratings")")
                        .font(.system(size: 11))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.6))
                }
            }

            // Trailer + action buttons
            if vm.trailerKey != nil || !vm.friendTakes.isEmpty {
                actionButtons
            }

            // Genres
            if !film.genreNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(film.genreNames, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Summary
            if !film.overview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Summary")
                    Text(film.overview)
                        .font(.system(size: 15))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Friends' (and your own) takes — only shows up if someone's actually seen it
            if !vm.friendTakes.isEmpty {
                friendTakesSection
            }

            // Where to Watch — or, if nothing streams/rents it yet and it's still in its
            // theatrical window, a quiet "In Theaters" chip instead of an empty section.
            watchAvailabilitySection

            // Your private note — sits right before Cast & Crew
            noteSection

            // Cast & Crew — always last
            if vm.director != nil || !vm.bookAuthors.isEmpty || !vm.creators.isEmpty || !(vm.credits?.cast.isEmpty ?? true) {
                castAndCrewSection
            }

            if let collectionName = vm.collectionName {
                Text("Part of the \(collectionName)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.7))
            }
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.top, 16)
    }

    // MARK: - Cast & Crew (bottom of screen)
    //
    // Popcorn is a social ranking app, not a film-credits database — we deliberately don't
    // list Writer/Producer/Cinematographer/Editor here. Director is the one crew role the
    // average moviegoer actually recognizes and treats as a signal ("a Nolan film"); everyone
    // else in the credits is industry-recognition territory, not a reason someone picks a
    // movie. Keep this section to Director + the main cast, nothing more.
    //
    // Two deliberate exceptions, both because they're a real, recognizable draw the same way a
    // director is: the source-material author for a book adaptation (`vm.bookAuthors`, e.g. "an
    // Andy Weir book" carries real weight for his readers), and — for TV, which has no real
    // "Director" credit at the show level (directing is an episode-level job there, and TMDB's
    // aggregate TV credits almost never surface a show-level one) — the show's creator(s)
    // (`vm.creators`, e.g. "Vince Gilligan" for Breaking Bad). All share the same card treatment.

    private var castAndCrewSection: some View {
        let leads = film.mediaType == .tv ? vm.creators : ([vm.director].compactMap { $0 } + vm.bookAuthors)
        let castSlots = max(12 - leads.count, 0)
        let people = leads + Array((vm.credits?.cast ?? []).prefix(castSlots))
        let leadIDs = Set(leads.map(\.id))

        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Cast & Crew")

            if !people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(people) { person in
                            CastCard(person: person, roleOverride: leadIDs.contains(person.id) ? person.job : nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Note (private — only the current user ever sees their own)

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Your Note")
                Spacer()
                if vm.noteDirty {
                    Button {
                        Task {
                            await vm.saveNote(tmdbID: film.id, mediaType: film.mediaType, currentUserID: appState.currentUser?.id)
                        }
                    } label: {
                        Text(vm.isSavingNote ? "Saving…" : "Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.gold)
                    }
                    .disabled(vm.isSavingNote)
                }
            }
            Text("Private — only you can see this.")
                .font(.system(size: 11))
                .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.6))
            TextEditor(text: $vm.noteDraft)
                .font(.system(size: 14))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(10)
                .background(CinemaTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm)
                        .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let key = vm.trailerKey {
                Button {
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Trailer")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(CinemaTheme.Colors.gold)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Where to Watch

    // Picks between the full streaming/rental section and a quiet "In Theaters" chip —
    // a film mid-theatrical-run has no flatrate/rent/buy providers yet, but "you can't
    // stream this, nothing to show" reads as broken when the real answer is "go to a theater."
    @ViewBuilder
    private var watchAvailabilitySection: some View {
        let streaming = vm.watchProviders?.flatrate ?? []
        let rentBuy = Array(Set((vm.watchProviders?.rent ?? []) + (vm.watchProviders?.buy ?? [])).prefix(5))

        if !streaming.isEmpty || !rentBuy.isEmpty {
            whereToWatchSection(vm.watchProviders!)
        } else if vm.isInTheaters {
            HStack(spacing: 8) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(CinemaTheme.Colors.gold)
                Text("In Theaters Now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(Capsule().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func whereToWatchSection(_ providers: TMDBRegionProviders) -> some View {
        let streaming = curatedProviders(providers.flatrate ?? [])
        let rentBuy = curatedProviders((providers.rent ?? []) + (providers.buy ?? []))

        if !streaming.isEmpty || !rentBuy.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Where to Watch")

                if !streaming.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Streaming")
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(streaming, id: \.providerId) { provider in
                                    ProviderLogo(provider: provider)
                                }
                            }
                        }
                    }
                }

                if !rentBuy.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rent / Buy")
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(rentBuy, id: \.providerId) { provider in
                                    ProviderLogo(provider: provider)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The streaming platforms Popcorn actually shows — cut down from TMDB's full list of 250+
    // tracked providers (almost all of them tiny regional or reseller-only services nobody
    // uses) to a deliberate, hand-picked set. Keyed by provider ID rather than name: a name
    // string like "Paramount Plus Essential" is fragile to match against, an ID isn't, and
    // TMDB's own naming/casing for the same brand isn't even consistent across entries.
    //
    // Variants that give access to the exact same catalog as their base brand — a subscription
    // tier (Paramount+ Essential/Premium, Peacock Premium/Premium Plus), an ad-supported profile
    // (Netflix Standard with Ads, Netflix Kids), or paying through Amazon/Apple/Roku instead of
    // directly — collapse to one canonical name below, so the row shows one tile per real
    // choice. Variants that are a genuinely smaller/different catalog (Amazon's free-for-anyone
    // ad-supported tier, Fandango At Home's free tier) get their own distinct name so they never
    // silently merge into — and get mistaken for — the full paid catalog's tile.
    private let allowedProviders: [Int: String] = [
        8: "Netflix", 1796: "Netflix", 175: "Netflix",
        9: "Amazon Prime Video", 2100: "Amazon Prime Video", 613: "Amazon Prime Video (Free)",
        350: "Apple TV", 2: "Apple TV",
        337: "Disney Plus",
        15: "Hulu",
        1899: "HBO Max", 1825: "HBO Max",
        283: "Crunchyroll", 1968: "Crunchyroll",
        2303: "Paramount+", 2616: "Paramount+", 582: "Paramount+", 633: "Paramount+", 1853: "Paramount+",
        386: "Peacock", 387: "Peacock", 2553: "Peacock",
        3: "Google Play Movies",
        192: "YouTube",
        7: "Fandango At Home", 332: "Fandango At Home (Free)",
    ]

    // Drops anything not on the allowlist, collapses same-catalog variants to one tile
    // (preferring the direct entry over a "via Amazon/Apple/Roku Channel" one when both are
    // present), and — critically — never routes through a bare Set, since Swift's Set/Dictionary
    // iteration order is randomized per process launch. Order comes from TMDB's own list.
    private func curatedProviders(_ providers: [TMDBWatchProvider]) -> [TMDBWatchProvider] {
        var chosen: [String: TMDBWatchProvider] = [:]
        for provider in providers {
            guard let canonicalName = allowedProviders[provider.providerId] else { continue }
            if let existing = chosen[canonicalName], !existing.providerName.localizedCaseInsensitiveContains("channel") {
                continue
            }
            chosen[canonicalName] = provider
        }
        var addedNames: Set<String> = []
        return providers.compactMap { provider in
            guard let canonicalName = allowedProviders[provider.providerId],
                  !addedNames.contains(canonicalName),
                  let winner = chosen[canonicalName] else { return nil }
            addedNames.insert(canonicalName)
            return winner
        }
    }

    // MARK: - Friends' Takes

    private var friendTakesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Friends' Takes")
            VStack(spacing: 8) {
                ForEach(vm.friendTakes) { take in
                    Button {
                        if !take.isSelf, let user = take.user { selectedFriend = user }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(CinemaTheme.Colors.surface).frame(width: 36, height: 36)
                                    .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                                Text(take.displayName.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(take.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                if let pos = take.rankPosition {
                                    Text(take.isSelf ? "Ranked #\(pos) on your list" : "Ranked #\(pos) on their list")
                                        .font(.system(size: 12))
                                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                }
                            }
                            Spacer()
                            if let rating = take.ratingOutOf10 {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                    Text("/ 10")
                                        .font(.system(size: 12))
                                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                }
                            }
                            if !take.isSelf {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.5))
                            }
                        }
                        .padding(12)
                        .background(CinemaTheme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(take.isSelf)
                }
            }
        }
    }

    private func metaText(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(CinemaTheme.Colors.textSecondary)
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(CinemaTheme.Colors.textPrimary)
    }
}

// MARK: - Cast Card

private struct CastCard: View {
    let person: TMDBPerson
    var roleOverride: String? = nil
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let path = person.profilePath, let url = TMDBClient.shared.profileImageURL(path: path) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        else { placeholder }
                    }
                } else { placeholder }
            }
            .frame(width: 72, height: 72).clipShape(Circle())
            .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))

            VStack(spacing: 2) {
                Text(person.name).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary).lineLimit(2).multilineTextAlignment(.center)
                if let role = roleOverride ?? person.character, !role.isEmpty {
                    Text(role).font(.system(size: 10)).foregroundStyle(CinemaTheme.Colors.textSecondary).lineLimit(1)
                }
            }
            .frame(width: 80)
        }
    }
    private var placeholder: some View {
        CinemaTheme.Colors.surface.overlay(
            Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(CinemaTheme.Colors.border)
        )
    }
}

// MARK: - Provider Logo

// TMDB's provider assets already come as finished square tiles (real app icons, or — for
// bundled entries like "HBO Max on Prime Video" — a pre-composited multi-brand lockup), so the
// icon needs no card or border of its own; adding one just framed a frame. .fit (not .fill)
// still matters for the occasional non-square lockup, so nothing gets cropped. No name label
// underneath — a recognizable icon doesn't need a caption.
private struct ProviderLogo: View {
    let provider: TMDBWatchProvider
    var body: some View {
        Group {
            if let url = TMDBClient.shared.providerLogoURL(path: provider.logoPath) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fit)
                    } else { Color.clear }
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// TMDBWatchProvider Hashable for Set deduplication
extension TMDBWatchProvider: Hashable {
    static func == (lhs: TMDBWatchProvider, rhs: TMDBWatchProvider) -> Bool { lhs.providerId == rhs.providerId }
    func hash(into hasher: inout Hasher) { hasher.combine(providerId) }
}
