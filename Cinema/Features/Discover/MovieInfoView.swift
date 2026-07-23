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
        watchProviders = try? await TMDBClient.shared.watchProviders(tmdbID: film.id, mediaType: film.mediaType)
        // TMDB's own "now playing" list, fetched fresh every time this screen opens — not a
        // fixed release-date heuristic, so the "In Theaters Now" chip stops showing itself the
        // moment TMDB shows this title has left theaters, no manual expiry logic needed.
        if film.mediaType == .movie, let nowPlaying = try? await TMDBClient.shared.nowPlaying() {
            isInTheaters = nowPlaying.contains { $0.id == film.id }
        }
        trailerKey = await TMDBClient.shared.trailerKey(tmdbID: film.id, mediaType: film.mediaType)

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

        // "Or you" — the current user's own take shows first, if they've ranked it.
        if let mine: RankedItem = try? await SupabaseClient.shared
            .from("ranked_items").select()
            .eq("tmdb_id", value: tmdbID).eq("user_id", value: currentUserID)
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
            .eq("tmdb_id", value: tmdbID)
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
}

// MARK: - MovieInfoView

struct MovieInfoView: View {
    let film: MediaItem
    @State private var vm = MovieInfoViewModel()
    @State private var selectedFriend: CinemaUser?
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

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

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .task { await vm.load(film: film, currentUserID: appState.currentUser?.id) }
        .sheet(item: $selectedFriend) { friend in
            NavigationStack { UserProfileView(user: friend) }
        }
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

                HStack(spacing: 8) {
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
            if vm.director != nil || !(vm.credits?.cast.isEmpty ?? true) {
                castAndCrewSection
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

    private var castAndCrewSection: some View {
        // Director rendered as the same photo/name/role card as everyone else in Cast —
        // one consistent visual language for "people in this movie" instead of singling
        // the director out as a plain text line.
        let castSlots = vm.director == nil ? 12 : 11
        let people = ([vm.director].compactMap { $0 }) + Array((vm.credits?.cast ?? []).prefix(castSlots))

        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Cast & Crew")

            if !people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(people) { person in
                            CastCard(person: person, roleOverride: person.id == vm.director?.id ? "Director" : nil)
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
        let streaming = providers.flatrate ?? []
        let rentBuy = Array(Set((providers.rent ?? []) + (providers.buy ?? [])).prefix(5))

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

private struct ProviderLogo: View {
    let provider: TMDBWatchProvider
    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = TMDBClient.shared.providerLogoURL(path: provider.logoPath) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fit) }
                        else { Color.gray.opacity(0.3) }
                    }
                } else { Color.gray.opacity(0.3) }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(provider.providerName)
                .font(.system(size: 10))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: 52)
        }
    }
}

// TMDBWatchProvider Hashable for Set deduplication
extension TMDBWatchProvider: Hashable {
    static func == (lhs: TMDBWatchProvider, rhs: TMDBWatchProvider) -> Bool { lhs.providerId == rhs.providerId }
    func hash(into hasher: inout Hasher) { hasher.combine(providerId) }
}
