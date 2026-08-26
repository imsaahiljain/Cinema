import SwiftUI
import Supabase

// MARK: - Local Types

struct TasteProfile {
    struct WeightedPerson: Identifiable {
        let id: Int
        let name: String
        let profilePath: String?
    }

    // `weight` is this genre's ELO score normalized against the #1 genre's, so the UI can
    // size a bar off real ranking behavior instead of just a fixed 1st/2nd/3rd guess.
    struct WeightedGenre: Identifiable {
        var id: String { name }
        let name: String
        let weight: Double
    }

    let topGenres: [WeightedGenre]
    let favoriteDirector: WeightedPerson?
    let favoriteActors: [WeightedPerson]

    static let mock = TasteProfile(
        topGenres: [
            WeightedGenre(name: "Drama", weight: 1.0),
            WeightedGenre(name: "Thriller", weight: 0.74),
            WeightedGenre(name: "Sci-Fi", weight: 0.52),
        ],
        favoriteDirector: WeightedPerson(id: 525, name: "Christopher Nolan", profilePath: "/xuAIuYSmsUzKlUMBFGVZaWsY3DZ.jpg"),
        favoriteActors: [
            WeightedPerson(id: 31, name: "Tom Hanks", profilePath: "/xndWFsBlClOJFRdhziRzhaWQjEB.jpg"),
            WeightedPerson(id: 5081, name: "Cate Blanchett", profilePath: "/nJRciH8VXDbg496OG7RsAibkxRy.jpg"),
            WeightedPerson(id: 90633, name: "Timothée Chalamet", profilePath: "/BE2sdjpgsa2rNTFa66f7upkaOP.jpg"),
        ]
    )
}

private struct FollowRecord: Decodable {
    let followerID: UUID
    let followingID: UUID
    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
    }
}

struct ActivityEntry: Identifiable {
    let id: UUID
    let media: MediaItem
    let ratingOutOf10: Double?
    let note: String?
    let updatedAt: Date
}

/// A real head-to-head duel pulled from `elo_matches` where the film you picked scores lower
/// on TMDB than the one you passed over — grounded in an actual choice you made, not a guess
/// at what might read as controversial.
struct HotTake {
    let preferred: MediaItem
    let snubbed: MediaItem
    let scoreGap: Double
}

// MARK: - ViewModel

@Observable
@MainActor
final class ProfileViewModel {
    var allRankedItems: [RankedItem] = []
    var topFilms: [MediaItem] = []
    var leastLikedFilms: [MediaItem] = []
    var favoriteGenre: String?
    var favoriteGenreFilms: [MediaItem] = []
    var hotTake: HotTake?
    var recentActivity: [ActivityEntry] = []
    var followerCount: Int = 0
    var followingCount: Int = 0
    var tasteProfile: TasteProfile?
    var isTasteProfileLoading = false
    var isLoading = false

    var rankedCount: Int { allRankedItems.count }

    func load(userID: UUID?) async {
        guard let userID else { return }
        isLoading = allRankedItems.isEmpty
        defer { isLoading = false }

        do {
            let items: [RankedItem] = try await SupabaseClient.shared
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .order("elo_score", ascending: false)
                .execute()
                .value
            allRankedItems = items

            let followers: [FollowRecord] = (try? await SupabaseClient.shared
                .from("follows")
                .select("follower_id,following_id")
                .eq("following_id", value: userID)
                .execute()
                .value) ?? []
            followerCount = followers.count

            let following: [FollowRecord] = (try? await SupabaseClient.shared
                .from("follows")
                .select("follower_id,following_id")
                .eq("follower_id", value: userID)
                .execute()
                .value) ?? []
            followingCount = following.count

            var loaded: [MediaItem] = []
            for item in items.prefix(9) {
                if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                    loaded.append(media)
                }
            }
            topFilms = loaded

            await loadRecentActivity(userID: userID, items: items)

            // Least Liked / Favorite Genre need more than a handful ranked to mean anything
            // distinct from Top Films — 5 is a low, mostly-just-not-empty bar.
            if items.count >= 5 {
                var leastLoaded: [MediaItem] = []
                for item in items.suffix(9).reversed() {
                    if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                        leastLoaded.append(media)
                    }
                }
                leastLikedFilms = leastLoaded
                await loadFavoriteGenre(items: Array(items.prefix(20)))
                // Hot Takes disabled — pulled to post-production (2026-08-23). Its "biggest
                // upset" logic leans on TMDB's vote_average as the ground truth for which film
                // is objectively worse, and that's not a data source we trust for that call.
                // `loadHotTake`/`HotTake`/the `.hotTake` carousel case all stay in place so this
                // is a one-line revert once there's a rating source worth building it on.
                // await loadHotTake(userID: userID)
            }

            // No `tasteProfile == nil` guard — always recompute on every load so re-ranking
            // films and pulling to refresh actually changes what's shown here, instead of
            // freezing on whatever the first 25-film snapshot happened to be.
            if items.count >= 25 {
                isTasteProfileLoading = true
                await loadTasteProfile(items: Array(items.prefix(25)))
                isTasteProfileLoading = false
            }
        } catch {}
    }

    /// Most-recently-ranked-or-updated first, not ELO order — this is meant to read as "what
    /// have you been up to," not another view of the same top/bottom lists. Reuses your own
    /// private note (`film_notes`) if you left one, same as MovieInfoView's note field.
    private func loadRecentActivity(userID: UUID, items: [RankedItem]) async {
        let recent = items.sorted { $0.updatedAt > $1.updatedAt }.prefix(10)
        guard !recent.isEmpty else { recentActivity = []; return }

        let notesByKey: [String: String] = await {
            let tmdbIDs = Array(Set(recent.map(\.tmdbID)))
            guard let notes: [FilmNote] = try? await SupabaseClient.shared
                .from("film_notes")
                .select()
                .eq("user_id", value: userID)
                .in("tmdb_id", values: tmdbIDs)
                .execute()
                .value else { return [:] }
            return Dictionary(uniqueKeysWithValues: notes.map { ("\($0.tmdbID)-\($0.mediaType.rawValue)", $0.note) })
        }()

        // Same linear rank->rating formula as MovieInfoViewModel.FriendTake.ratingOutOf10
        // (#1 of N = 10.0, #N of N = 0.0) — reused here rather than reinvented so a film's
        // score reads the same on your profile as it does on its own detail screen.
        let totalRanked = items.count
        func ratingOutOf10(for rankPosition: Int?) -> Double? {
            guard let pos = rankPosition, totalRanked > 1 else { return rankPosition == 1 ? 10.0 : nil }
            return max(0, (1.0 - Double(pos - 1) / Double(totalRanked - 1)) * 10.0)
        }

        var entries: [ActivityEntry] = []
        for item in recent {
            guard let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) else { continue }
            let note = notesByKey["\(item.tmdbID)-\(item.mediaType.rawValue)"]
            entries.append(ActivityEntry(
                id: item.id,
                media: media,
                ratingOutOf10: ratingOutOf10(for: item.rankPosition),
                note: (note?.isEmpty == false) ? note : nil,
                updatedAt: item.updatedAt
            ))
        }
        recentActivity = entries
    }

    /// Lighter-weight than the full taste profile below — just genres, ELO-weighted, no
    /// gate beyond `rankedCount >= 5` — so the carousel's Favorite Genre page isn't stuck
    /// behind the same 25-film wall as the full Film Favorites section. Also builds the
    /// actual poster grid for that genre (the films that earned it the win), not just the
    /// genre name, so the card has something to look at instead of one word in a void.
    private func loadFavoriteGenre(items: [RankedItem]) async {
        var genreScore: [String: Double] = [:]
        var genresByItem: [UUID: [String]] = [:]
        var mediaByItem: [UUID: MediaItem] = [:]

        await withTaskGroup(of: (RankedItem, MediaItem?).self) { group in
            for item in items {
                group.addTask {
                    let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType)
                    return (item, media)
                }
            }
            for await (item, media) in group {
                let genres = media?.genreNames ?? []
                genresByItem[item.id] = genres
                if let media { mediaByItem[item.id] = media }
                for g in genres { genreScore[g, default: 0] += item.eloScore }
            }
        }

        guard let topGenre = genreScore.max(by: { $0.value < $1.value })?.key else {
            favoriteGenre = nil
            favoriteGenreFilms = []
            return
        }
        favoriteGenre = topGenre
        // `items` is already ELO-descending, so filtering preserves that order.
        favoriteGenreFilms = items
            .filter { genresByItem[$0.id]?.contains(topGenre) == true }
            .compactMap { mediaByItem[$0.id] }
    }

    /// "Biggest upset" read of `elo_matches`: among your most recent duels, the one where the
    /// film you picked has the largest TMDB-vote-average deficit against the film it beat.
    /// Working off actual recorded picks rather than inferring from rank position is what
    /// makes this a real hot take instead of a guess.
    private func loadHotTake(userID: UUID) async {
        guard let matches: [ELOMatch] = try? await SupabaseClient.shared
            .from("elo_matches")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(25)
            .execute()
            .value, !matches.isEmpty else {
            hotTake = nil
            return
        }

        struct Key: Hashable { let id: Int; let type: MediaType }
        var keys = Set<Key>()
        for m in matches {
            guard let type = MediaType(rawValue: m.mediaType) else { continue }
            keys.insert(Key(id: m.winnerTmdbID, type: type))
            keys.insert(Key(id: m.loserTmdbID, type: type))
        }

        var mediaByKey: [Key: MediaItem] = [:]
        await withTaskGroup(of: (Key, MediaItem?).self) { group in
            for key in keys {
                group.addTask {
                    let media = try? await TMDBClient.shared.details(tmdbID: key.id, mediaType: key.type)
                    return (key, media)
                }
            }
            for await (key, media) in group {
                if let media { mediaByKey[key] = media }
            }
        }

        var best: HotTake?
        for m in matches {
            guard let type = MediaType(rawValue: m.mediaType),
                  let preferred = mediaByKey[Key(id: m.winnerTmdbID, type: type)],
                  let snubbed = mediaByKey[Key(id: m.loserTmdbID, type: type)],
                  let preferredScore = preferred.voteAverage, let snubbedScore = snubbed.voteAverage else { continue }
            let gap = snubbedScore - preferredScore
            if gap > 0.5, (best == nil || gap > best!.scoreGap) {
                best = HotTake(preferred: preferred, snubbed: snubbed, scoreGap: gap)
            }
        }
        hotTake = best
    }

    /// Weighted by ELO score, not raw frequency — a film ranked #1 pulls harder toward its
    /// genres/cast than one ranked #24, so this reflects actual favorites rather than just
    /// whatever shows up most often across 25 ranked items regardless of how they scored.
    private func loadTasteProfile(items: [RankedItem]) async {
        struct PersonTally { var person: TMDBPerson; var score: Double }
        var genreScore: [String: Double] = [:]
        var directorScore: [Int: PersonTally] = [:]
        var actorScore: [Int: PersonTally] = [:]

        await withTaskGroup(of: (Double, [String], TMDBPerson?, [TMDBPerson]).self) { group in
            for item in items {
                let tmdbID = item.tmdbID
                let mediaType = item.mediaType
                let elo = item.eloScore
                group.addTask {
                    var genres: [String] = []
                    var director: TMDBPerson? = nil
                    var actors: [TMDBPerson] = []
                    if let media = try? await TMDBClient.shared.details(tmdbID: tmdbID, mediaType: mediaType) {
                        genres = media.genreNames
                    }
                    if let credits = try? await TMDBClient.shared.credits(tmdbID: tmdbID, mediaType: mediaType) {
                        director = credits.crew.first(where: { $0.job == "Director" })
                        actors = Array(credits.cast.prefix(3))
                    }
                    return (elo, genres, director, actors)
                }
            }
            for await (elo, genres, director, actors) in group {
                for g in genres { genreScore[g, default: 0] += elo }
                if let d = director {
                    if directorScore[d.id] != nil { directorScore[d.id]!.score += elo }
                    else { directorScore[d.id] = PersonTally(person: d, score: elo) }
                }
                for a in actors {
                    if actorScore[a.id] != nil { actorScore[a.id]!.score += elo }
                    else { actorScore[a.id] = PersonTally(person: a, score: elo) }
                }
            }
        }

        let topGenreEntries = Array(genreScore.sorted { $0.value > $1.value }.prefix(3))
        let topGenreScore = topGenreEntries.first?.value ?? 0
        let topGenres = topGenreEntries.map {
            TasteProfile.WeightedGenre(name: $0.key, weight: topGenreScore > 0 ? $0.value / topGenreScore : 0)
        }
        let topDirector = directorScore.values.max(by: { $0.score < $1.score })
        let topActors = actorScore.values.sorted { $0.score > $1.score }.prefix(3)

        tasteProfile = TasteProfile(
            topGenres: topGenres,
            favoriteDirector: topDirector.map { TasteProfile.WeightedPerson(id: $0.person.id, name: $0.person.name, profilePath: $0.person.profilePath) },
            favoriteActors: topActors.map { TasteProfile.WeightedPerson(id: $0.person.id, name: $0.person.name, profilePath: $0.person.profilePath) }
        )
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ProfileViewModel()
    @State private var showFollowers = false
    @State private var showFollowing = false
    @State private var showSettings = false
    @State private var showPeopleSearch = false
    @State private var showEditProfile = false
    @State private var carouselPage = 0
    @State private var isSelectingShare = false
    @State private var selectedSharePages: Set<CarouselPage> = []
    @State private var favoritesTab: FavoritesTab = .activity
    @AppStorage("cinema_dev_fingerprint") private var devFingerprintUnlocked = false

    private static let memberSinceFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        profileHeader
                        socialStats
                        filmCarouselSection
                        favoritesTabSection
                        Spacer().frame(height: 100)
                    }
                }
                .refreshable { await vm.load(userID: appState.currentUser?.id) }
            }

            // Find People + Settings — float above scroll
            VStack {
                HStack {
                    Spacer()
                    Button { showPeopleSearch = true } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Find People")
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                    .padding(.trailing, 10)
                }
                .padding(.top, 8)
                Spacer()
            }
        }
        .task { await vm.load(userID: appState.currentUser?.id) }
        .sheet(isPresented: $showPeopleSearch) {
            PeopleSearchView()
        }
        .sheet(isPresented: $showFollowers) {
            FollowListView(mode: .followers, userID: appState.currentUser?.id)
        }
        .sheet(isPresented: $showFollowing) {
            FollowListView(mode: .following, userID: appState.currentUser?.id)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $showEditProfile) {
            if let user = appState.currentUser {
                EditProfileView(user: user)
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            // Avatar — tap the pencil badge to edit
            Button { showEditProfile = true } label: {
                ZStack {
                    Group {
                        if let urlString = appState.currentUser?.avatarURL, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                                else { avatarInitial }
                            }
                        } else {
                            avatarInitial
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))

                    Circle()
                        .fill(CinemaTheme.Colors.gold)
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "pencil").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black))
                        .overlay(Circle().strokeBorder(CinemaTheme.Colors.background, lineWidth: 2))
                        .offset(x: 31, y: 31)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            VStack(spacing: 5) {
                Text(appState.currentUser?.displayName ?? appState.currentUser?.username ?? "")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Text("@\(appState.currentUser?.username ?? "")")
                    .font(.system(size: 15))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                if let bio = appState.currentUser?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 2)
                }
                if let createdAt = appState.currentUser?.createdAt {
                    Text("Member since \(Self.memberSinceFormatter.string(from: createdAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.6))
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
    }

    private var avatarInitial: some View {
        CinemaTheme.Colors.surface.overlay(
            Text(appState.currentUser?.displayName?.prefix(1).uppercased()
                 ?? appState.currentUser?.username.prefix(1).uppercased()
                 ?? "?")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        )
    }

    // MARK: - Social Stats

    private var socialStats: some View {
        HStack(spacing: 0) {
            StatCell(value: "\(vm.followerCount)", label: "Followers", tappable: true) {
                showFollowers = true
            }

            Rectangle()
                .fill(CinemaTheme.Colors.border)
                .frame(width: 1, height: 40)

            StatCell(value: "\(vm.rankedCount)", label: "Ranked", tappable: false) {}

            Rectangle()
                .fill(CinemaTheme.Colors.border)
                .frame(width: 1, height: 40)

            StatCell(value: "\(vm.followingCount)", label: "Following", tappable: true) {
                showFollowing = true
            }
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.bottom, 36)
    }

    // MARK: - Film Carousel (Top Films / Least Liked / Favorite Genre / Hot Takes)

    private enum CarouselPage: Hashable { case topFilms, leastLiked, favoriteGenre, hotTake }

    private var carouselPages: [CarouselPage] {
        var pages: [CarouselPage] = [.topFilms]
        if !vm.leastLikedFilms.isEmpty { pages.append(.leastLiked) }
        if !vm.favoriteGenreFilms.isEmpty { pages.append(.favoriteGenre) }
        // .hotTake withheld — see the `loadHotTake` call site in ProfileViewModel.load for why.
        // vm.hotTake is never populated right now, so this is belt-and-suspenders, not load-bearing.
        return pages
    }

    private func carouselTitle(_ page: CarouselPage) -> String {
        switch page {
        case .topFilms: return "Top Films"
        case .leastLiked: return "Least Liked"
        case .favoriteGenre: return "Favorite Genre"
        case .hotTake: return "Hot Takes"
        }
    }

    // What a given page would hand to the share sheet if selected — used both to decide
    // whether the share button shows at all, and to build the actual list of cards once the
    // user has picked which pages to share.
    private func shareContent(for page: CarouselPage) -> ShareCardContent? {
        switch page {
        case .topFilms:
            return vm.topFilms.isEmpty ? nil : .topFilms(films: vm.topFilms)
        case .leastLiked:
            return vm.leastLikedFilms.isEmpty ? nil : .leastLiked(films: vm.leastLikedFilms)
        case .favoriteGenre:
            guard let genre = vm.favoriteGenre, !vm.favoriteGenreFilms.isEmpty else { return nil }
            let denominator = max(min(vm.allRankedItems.count, 20), 1)
            let percent = Int((Double(vm.favoriteGenreFilms.count) / Double(denominator)) * 100)
            return .favoriteGenre(genre: genre, films: vm.favoriteGenreFilms, sharePercent: percent)
        case .hotTake:
            guard let hotTake = vm.hotTake else { return nil }
            return .hotTake(hotTake)
        }
    }

    private var currentCarouselPage: CarouselPage {
        carouselPages.indices.contains(carouselPage) ? carouselPages[carouselPage] : .topFilms
    }

    // MARK: Share selection (Photos-style: tap share, keep swiping, tap more pages to add)

    private func beginShareSelection() {
        selectedSharePages = [currentCarouselPage]
        isSelectingShare = true
    }

    private func endShareSelection() {
        isSelectingShare = false
        selectedSharePages = []
    }

    private func toggleSelection(for page: CarouselPage) {
        if selectedSharePages.contains(page) {
            selectedSharePages.remove(page)
        } else {
            selectedSharePages.insert(page)
        }
    }

    private func confirmShareSelection() async {
        // Iterate `carouselPages` rather than the (unordered) Set so the share sheet gets the
        // images in the same order they appear in the carousel.
        let contents = carouselPages.filter { selectedSharePages.contains($0) }.compactMap { shareContent(for: $0) }
        guard !contents.isEmpty else { return }
        await ShareCardService.share(contents, user: appState.currentUser)
        endShareSelection()
    }

    private var filmCarouselSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(carouselTitle(carouselPage < carouselPages.count ? carouselPages[carouselPage] : .topFilms))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Spacer()
                if carouselPages.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(carouselPages.indices, id: \.self) { i in
                            Circle()
                                .fill(i == carouselPage ? CinemaTheme.Colors.gold : CinemaTheme.Colors.border)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .animation(.easeInOut(duration: 0.15), value: carouselPage)

            HStack {
                if isSelectingShare {
                    Button("Cancel") { endShareSelection() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                    Spacer()
                    Text(selectedSharePages.isEmpty ? "Tap a page to select" : "\(selectedSharePages.count) selected")
                        .font(.system(size: 12))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                } else {
                    if carouselPages.count > 1 {
                        Text("Swipe for more")
                            .font(.system(size: 11))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.7))
                    }
                    Spacer()
                    if shareContent(for: currentCarouselPage) != nil {
                        shareButton { beginShareSelection() }
                    }
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .frame(minHeight: 20)

            TabView(selection: $carouselPage) {
                ForEach(carouselPages.indices, id: \.self) { i in
                    carouselCard(for: carouselPages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(2/3, contentMode: .fit)
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .overlay(alignment: .topTrailing) {
                // Same spot as Photos' per-thumbnail selection circle — tap to add or remove
                // the page currently on screen without leaving the carousel or losing your
                // swipe position.
                if isSelectingShare {
                    selectionCheckmark.padding(.trailing, CinemaTheme.Spacing.lg + 10).padding(.top, 10)
                }
            }
            .onChange(of: carouselPages.count) { _, newCount in
                if carouselPage >= newCount { carouselPage = 0 }
            }

            if isSelectingShare {
                Button {
                    Task { await confirmShareSelection() }
                } label: {
                    Text(selectedSharePages.isEmpty ? "Select a page to share" : "Share \(selectedSharePages.count) page\(selectedSharePages.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(CinemaTheme.Colors.gold)
                        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                }
                .disabled(selectedSharePages.isEmpty)
                .opacity(selectedSharePages.isEmpty ? 0.5 : 1)
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.top, 12)
            }
        }
        .padding(.bottom, 36)
    }

    private var selectionCheckmark: some View {
        let isSelected = selectedSharePages.contains(currentCarouselPage)
        return Button {
            toggleSelection(for: currentCarouselPage)
        } label: {
            ZStack {
                Circle().fill(isSelected ? CinemaTheme.Colors.gold : Color.black.opacity(0.45))
                Circle().strokeBorder(.white.opacity(isSelected ? 0 : 0.6), lineWidth: 1.5)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 26, height: 26)
        }
        .accessibilityLabel(isSelected ? "Deselect page" : "Select page")
    }

    // Top Films / Least Liked / Favorite Genre share one poster-grid component with an
    // optional corner badge — Top Films badges its #1, Favorite Genre badges the genre name
    // on the film that earned it, Least Liked has no badge. Hot Takes breaks from the grid
    // (see `hotTakeCard` below) since its content is a two-film comparison, not a collection —
    // forcing that into a 9-up grid read as an empty, unfinished page the same way an early
    // version of Favorite Genre did before it got real poster content.
    @ViewBuilder
    private func carouselCard(for page: CarouselPage) -> some View {
        switch page {
        case .topFilms:
            posterGridCard(
                films: vm.topFilms,
                cornerBadge: { i in i == 0 ? "#1" : nil },
                emptyText: "Rank 9 films to see your top grid."
            )
        case .leastLiked:
            posterGridCard(
                films: vm.leastLikedFilms,
                cornerBadge: { _ in nil },
                emptyText: "Rank more films to see this."
            )
        case .favoriteGenre:
            posterGridCard(
                films: vm.favoriteGenreFilms,
                cornerBadge: { i in i == 0 ? vm.favoriteGenre?.uppercased() : nil },
                emptyText: "Rank a few more films to see your favorite genre."
            )
        case .hotTake:
            if let hotTake = vm.hotTake {
                hotTakeCard(hotTake)
            } else {
                EmptyView()
            }
        }
    }

    // Two posters + the statement, not a 9-up grid — a hot take is a comparison between two
    // specific films, so the on-screen page shows exactly those two rather than forcing the
    // grid layout every other page uses onto content that isn't a collection.
    private func hotTakeCard(_ hotTake: HotTake) -> some View {
        // Width-driven, not height-driven — same approach the poster grid pages use: give
        // each poster an equal share of the available width and let `aspectRatio(.fit)`
        // derive its height from that, rather than forcing a height and hoping the width
        // works out. A `.frame(height:)` on the HStack computed as a fraction of the card's
        // own height overflowed the card, since two full-height 2:3 posters side by side need
        // more width than a phone-width card actually has. `.clipped()` stays on as a backstop
        // regardless.
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                PosterImage(path: hotTake.preferred.posterPath, cornerRadius: CinemaTheme.Radius.md)
                    .aspectRatio(2/3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                PosterImage(path: hotTake.snubbed.posterPath, cornerRadius: CinemaTheme.Radius.md)
                    .aspectRatio(2/3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }

            Text("\(Text(hotTake.preferred.title).fontWeight(.bold)) over \(Text(hotTake.snubbed.title).fontWeight(.bold))")
                .font(.system(size: 13))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
        .clipped()
    }

    private func posterGridCard(films: [MediaItem], cornerBadge: @escaping (Int) -> String?, emptyText: String) -> some View {
        Group {
            if films.isEmpty {
                RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                    .fill(CinemaTheme.Colors.surface)
                    .overlay(
                        Text(emptyText)
                            .font(.system(size: 13))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(24)
                    )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(Array(films.prefix(9).enumerated()), id: \.element.id) { i, film in
                        ZStack(alignment: .topLeading) {
                            PosterImage(path: film.posterPath, cornerRadius: 0)
                                .aspectRatio(2/3, contentMode: .fit)
                            if let badge = cornerBadge(i) {
                                Text(badge)
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(CinemaTheme.Colors.gold)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(6)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
            }
        }
    }

    private func shareButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55))
                .clipShape(Circle())
        }
        .accessibilityLabel("Share")
    }

    // MARK: - Activity / Taste Profile

    private enum FavoritesTab: CaseIterable { case activity, tasteProfile }

    private func favoritesTabLabel(_ tab: FavoritesTab) -> String {
        switch tab {
        case .activity: return "Your Activity"
        case .tasteProfile: return "Taste Profile"
        }
    }

    private func favoritesTabIcon(_ tab: FavoritesTab) -> String {
        switch tab {
        case .activity: return "doc.text.image"
        case .tasteProfile: return "chart.bar.fill"
        }
    }

    private var favoritesTabSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(FavoritesTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { favoritesTab = tab }
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: favoritesTabIcon(tab)).font(.system(size: 13))
                                Text(favoritesTabLabel(tab)).font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(favoritesTab == tab ? CinemaTheme.Colors.textPrimary : CinemaTheme.Colors.textSecondary)
                            Rectangle()
                                .fill(favoritesTab == tab ? CinemaTheme.Colors.gold : .clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CinemaTheme.Colors.border).frame(height: 1)
            }
            .padding(.bottom, 20)

            if favoritesTab == .activity {
                activityContent
            } else {
                tasteProfileContent
            }
        }
        .padding(.bottom, 36)
    }

    // Post-card layout, not a plain list — same information a friend's post carries in the
    // Feed tab (poster, who, when, title, score, note, reaction row), just filtered to you.
    private var activityContent: some View {
        VStack(spacing: 12) {
            if vm.recentActivity.isEmpty {
                Text("Rank a film to see your activity here.")
                    .font(.system(size: 14))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
            } else {
                ForEach(vm.recentActivity) { entry in
                    ActivityPostCard(entry: entry, user: appState.currentUser)
                        .padding(.horizontal, CinemaTheme.Spacing.lg)
                }
            }
        }
    }

    private var tasteProfileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !devFingerprintUnlocked && vm.rankedCount < 25 {
                Text("\(vm.rankedCount) of 25 films ranked")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.bottom, 16)
            }

            if devFingerprintUnlocked {
                unlockedFingerprintView(TasteProfile.mock)
            } else if vm.rankedCount < 25 {
                lockedFingerprintView
            } else if vm.isTasteProfileLoading {
                HStack {
                    ProgressView().tint(CinemaTheme.Colors.gold)
                        .padding(.horizontal, CinemaTheme.Spacing.lg)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else if let profile = vm.tasteProfile {
                unlockedFingerprintView(profile)
            }
        }
    }

    private var lockedFingerprintView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rank 25 films to unlock your taste fingerprint.")
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CinemaTheme.Colors.surface)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CinemaTheme.Colors.gold.opacity(0.6))
                        .frame(width: geo.size.width * min(CGFloat(vm.rankedCount) / 25.0, 1.0), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, CinemaTheme.Spacing.lg)
        }
    }

    // Genre rows and the director/cast list both run the full column top-to-bottom now —
    // the old version put genres in a horizontal-scrolling pill row and cast in a second
    // horizontal scroller, so on a tall narrow screen it read as two thin strips floating
    // over a lot of empty background. Weight bars use the real ELO-normalized score from
    // loadTasteProfile rather than a fixed 1st/2nd/3rd guess, and cast/director reuse this
    // screen's own divided-row idiom (see SettingsRow above) instead of a bespoke card.
    private func unlockedFingerprintView(_ profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            if !profile.topGenres.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("GENRES")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .padding(.horizontal, CinemaTheme.Spacing.lg)

                    VStack(spacing: 14) {
                        ForEach(Array(profile.topGenres.enumerated()), id: \.element.id) { i, genre in
                            GenreWeightRow(rank: i + 1, genre: genre)
                        }
                    }
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                }
            }

            if profile.favoriteDirector != nil || !profile.favoriteActors.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DIRECTOR & CAST")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .padding(.horizontal, CinemaTheme.Spacing.lg)

                    VStack(spacing: 0) {
                        if let director = profile.favoriteDirector {
                            PersonFingerprintRow(person: director, roleLabel: "Director")
                            if !profile.favoriteActors.isEmpty {
                                Divider().background(CinemaTheme.Colors.border).padding(.leading, 74)
                            }
                        }
                        ForEach(Array(profile.favoriteActors.enumerated()), id: \.element.id) { i, actor in
                            PersonFingerprintRow(person: actor, roleLabel: nil)
                            if i < profile.favoriteActors.count - 1 {
                                Divider().background(CinemaTheme.Colors.border).padding(.leading, 74)
                            }
                        }
                    }
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                }
            }
        }
    }

}

// MARK: - Genre Weight Row (Taste Profile)

private struct GenreWeightRow: View {
    let rank: Int
    let genre: TasteProfile.WeightedGenre

    private var rankColor: Color {
        switch rank {
        case 1: return CinemaTheme.Colors.gold
        case 2: return CinemaTheme.Colors.gold.opacity(0.65)
        default: return CinemaTheme.Colors.gold.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(rankColor)
                .frame(width: 14, alignment: .leading)

            Text(genre.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .frame(width: 74, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(rankColor)
                    .frame(width: geo.size.width * max(0.08, min(1, genre.weight)), height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Person Fingerprint Row (Director & Cast — a divided row list, not a card)

private struct PersonFingerprintRow: View {
    let person: TasteProfile.WeightedPerson
    var roleLabel: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let path = person.profilePath, let url = TMDBClient.shared.profileImageURL(path: path) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        else { placeholder }
                    }
                } else { placeholder }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(1)
                if let roleLabel {
                    Text(roleLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var placeholder: some View {
        CinemaTheme.Colors.surface.overlay(
            Image(systemName: "person.fill").font(.system(size: 16)).foregroundStyle(CinemaTheme.Colors.border)
        )
    }
}

// MARK: - Settings

struct SettingsView: View {
    let appState: AppState
    @AppStorage("cinema_dev_fingerprint") private var devFingerprintUnlocked = false
    @AppStorage("cinema_dev_scores_unlocked") private var devScoresUnlocked = false
    @Environment(\.dismiss) private var dismiss
    @State private var showEditProfile = false
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?
    @State private var showCaptionDebug = false

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaTheme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        // Account
                        SettingsSection(title: "Account") {
                            SettingsRow(icon: "person.crop.circle", iconColor: CinemaTheme.Colors.gold, label: "Edit Profile") {
                                showEditProfile = true
                            }
                            Divider().background(CinemaTheme.Colors.border).padding(.leading, 52)
                            SettingsRow(icon: "key.fill", iconColor: CinemaTheme.Colors.gold, label: "Change Password", note: "Coming soon", disabled: true) {}
                            Divider().background(CinemaTheme.Colors.border).padding(.leading, 52)
                            SettingsRow(icon: "bell.fill", iconColor: .blue, label: "Notifications", note: "Coming soon", disabled: true) {}
                        }

                        // Developer — pre-production only
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("DEVELOPER")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                Text("· pre-production only")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.5))
                            }
                            .padding(.horizontal, CinemaTheme.Spacing.lg)

                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.purple)
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Film Favorites Preview")
                                            .font(.system(size: 16))
                                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                        Text("Shows mock data — bypasses 25-film gate")
                                            .font(.system(size: 12))
                                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $devFingerprintUnlocked)
                                        .tint(CinemaTheme.Colors.gold)
                                        .labelsHidden()
                                }
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                                .padding(.vertical, 12)

                                Divider().background(CinemaTheme.Colors.border).padding(.leading, 60)

                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.purple)
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "star.circle.fill")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Rankings Score Preview")
                                            .font(.system(size: 16))
                                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                        Text("Shows scores early — bypasses 10-film gate")
                                            .font(.system(size: 12))
                                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $devScoresUnlocked)
                                        .tint(CinemaTheme.Colors.gold)
                                        .labelsHidden()
                                        .accessibilityLabel("Rankings Score Preview Toggle")
                                }
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                                .padding(.vertical, 12)

                                Divider().background(CinemaTheme.Colors.border).padding(.leading, 60)

                                // Jumps straight to RankingView's "ranked!" / caption screen with
                                // mock data — for hand-testing that specific screen (keyboard
                                // behavior, layout) without spending a real ranking on every check.
                                Button { showCaptionDebug = true } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(Color.purple)
                                                .frame(width: 32, height: 32)
                                            Image(systemName: "text.bubble.fill")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(.white)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Caption Screen Preview")
                                                .font(.system(size: 16))
                                                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                            Text("Jumps to the ranked/caption screen with mock data")
                                                .font(.system(size: 12))
                                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                    }
                                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }
                            .background(CinemaTheme.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                                .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                            .padding(.horizontal, CinemaTheme.Spacing.lg)
                        }

                        // Sign Out
                        VStack(spacing: 0) {
                            Button {
                                Task { await appState.signOut() }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                    Text("Sign Out")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundStyle(.red.opacity(0.85))
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                                .padding(.vertical, 16)
                            }
                        }
                        .background(CinemaTheme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                            .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                        .padding(.horizontal, CinemaTheme.Spacing.lg)

                        // Delete Account — kept separate from Sign Out, own section, so it
                        // can't be mis-tapped reaching for the (much more common) sign-out row.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DANGER ZONE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                .padding(.horizontal, CinemaTheme.Spacing.lg)

                            Button {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 16))
                                    Text("Delete Account")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .foregroundStyle(.red)
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                                .padding(.vertical, 16)
                            }
                            .background(CinemaTheme.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
                            .padding(.horizontal, CinemaTheme.Spacing.lg)
                            .disabled(isDeletingAccount)
                        }

                        Spacer().frame(height: 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
            .sheet(isPresented: $showEditProfile) {
                if let user = appState.currentUser {
                    EditProfileView(user: user)
                }
            }
            .sheet(isPresented: $showCaptionDebug) {
                RankingResultDebugPreview()
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, every ranking, and your follows. This can't be undone.")
            }
            .alert("Couldn't Delete Account", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK") { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        ProgressView().tint(CinemaTheme.Colors.gold)
                    }
                }
            }
        }
    }

    private func performDelete() async {
        isDeletingAccount = true
        let success = await appState.deleteAccount()
        isDeletingAccount = false
        if !success {
            deleteErrorMessage = "Something went wrong. Check your connection and try again."
        }
        // On success, AppState.isAuthenticated flips to false and RootView swaps to the
        // auth screen on its own — no explicit dismiss needed here.
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

            VStack(spacing: 0) {
                content()
            }
            .background(CinemaTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
                .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
            .padding(.horizontal, CinemaTheme.Spacing.lg)
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    var note: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: disabled ? {} : action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(disabled ? iconColor.opacity(0.35) : iconColor)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(disabled ? 0.5 : 1))
                }
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(disabled ? CinemaTheme.Colors.textSecondary : CinemaTheme.Colors.textPrimary)
                Spacer()
                if let note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.6))
                } else if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.border)
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .padding(.vertical, 14)
        }
        .disabled(disabled)
    }
}

// MARK: - Activity Row

// Same shape as Feed's PopCard (poster spanning the card, header/title/note/reactions in
// a text column) — just re-skinned in CinemaTheme's dark palette instead of Marquee's warm
// one, and reactions render inert since there's no likes/comments backend on rankings yet.
private struct ActivityPostCard: View {
    let entry: ActivityEntry
    let user: CinemaUser?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterImage(path: entry.media.posterPath, cornerRadius: 12)
                .frame(width: 84, height: 126)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    avatar
                    Text(user?.displayName ?? user?.username ?? "You")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    Text("· \(Self.relativeFormatter.localizedString(for: entry.updatedAt, relativeTo: Date()))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.media.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let rating = entry.ratingOutOf10 {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(CinemaTheme.Colors.gold, in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                if let note = entry.note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 18) {
                    Image(systemName: "heart")
                    Image(systemName: "bubble.right")
                    Image(systemName: "paperplane")
                }
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.7))
            }
            .frame(height: 126, alignment: .top)
        }
        .padding(14)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            if let urlString = user?.avatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                    else { avatarInitial }
                }
            } else {
                avatarInitial
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
    }

    private var avatarInitial: some View {
        CinemaTheme.Colors.background.overlay(
            Text((user?.displayName ?? user?.username ?? "?").prefix(1).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        )
    }
}

// MARK: - Supporting Views

private struct StatCell: View {
    let value: String
    let label: String
    let tappable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: tappable ? action : {}) {
            VStack(spacing: 5) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(tappable ? CinemaTheme.Colors.textSecondary : CinemaTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!tappable)
    }
}

// MARK: - Follow List

struct FollowListView: View {
    enum Mode { case followers, following }

    let mode: Mode
    let userID: UUID?

    @State private var users: [CinemaUser] = []
    @State private var isLoading = true
    @State private var selectedUser: CinemaUser?
    @State private var showUserProfile = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaTheme.Colors.background.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(CinemaTheme.Colors.gold)
                } else if users.isEmpty {
                    Text(mode == .followers ? "No followers yet." : "Not following anyone yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(users) { user in
                                Button {
                                    selectedUser = user
                                    showUserProfile = true
                                } label: {
                                    FollowUserRow(user: user)
                                }
                                .buttonStyle(.plain)

                                Rectangle()
                                    .fill(CinemaTheme.Colors.border)
                                    .frame(height: 1)
                                    .padding(.leading, CinemaTheme.Spacing.lg)
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode == .followers ? "Followers" : "Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
            .navigationDestination(isPresented: $showUserProfile) {
                if let user = selectedUser {
                    UserProfileView(user: user)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let userID else { isLoading = false; return }
        do {
            let records: [FollowRecord] = try await SupabaseClient.shared
                .from("follows")
                .select("follower_id,following_id")
                .eq(mode == .followers ? "following_id" : "follower_id", value: userID)
                .execute()
                .value

            let ids = records.map { mode == .followers ? $0.followerID : $0.followingID }
            guard !ids.isEmpty else { isLoading = false; return }

            let profiles: [CinemaUser] = try await SupabaseClient.shared
                .from("users")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            users = profiles
        } catch {}
        isLoading = false
    }
}

private struct FollowUserRow: View {
    let user: CinemaUser

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CinemaTheme.Colors.surface)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                Text(user.displayName?.prefix(1).uppercased()
                     ?? user.username.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Text("@\(user.username)")
                    .font(.system(size: 13))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CinemaTheme.Colors.border)
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.vertical, 14)
    }
}

// MARK: - User Profile (another user)

struct UserProfileView: View {
    let user: CinemaUser
    @State private var vm = UserProfileViewModel()
    @State private var showShareCard = false

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(CinemaTheme.Colors.gold)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(CinemaTheme.Colors.surface)
                                    .frame(width: 72, height: 72)
                                    .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                                Text(user.displayName?.prefix(1).uppercased()
                                     ?? user.username.prefix(1).uppercased())
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            }
                            .padding(.top, 24)

                            VStack(spacing: 4) {
                                Text(user.displayName ?? user.username)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                Text("@\(user.username)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                Text("\(vm.rankedCount) films ranked")
                                    .font(.system(size: 13))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary.opacity(0.7))
                                    .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 28)

                        // Top Films
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Top Films")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                Spacer()
                                if !vm.topFilms.isEmpty {
                                    Button {
                                        showShareCard = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("Share")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundStyle(CinemaTheme.Colors.gold)
                                    }
                                }
                            }
                            .padding(.horizontal, CinemaTheme.Spacing.lg)

                            if vm.topFilms.isEmpty {
                                Text("No films ranked yet.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                            } else {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 2),
                                        GridItem(.flexible(), spacing: 2),
                                        GridItem(.flexible(), spacing: 2)
                                    ],
                                    spacing: 2
                                ) {
                                    ForEach(Array(vm.topFilms.prefix(9).enumerated()), id: \.element.id) { i, film in
                                        ZStack(alignment: .topLeading) {
                                            PosterImage(path: film.posterPath, cornerRadius: 0)
                                                .aspectRatio(2/3, contentMode: .fit)
                                            if i == 0 {
                                                Text("#1")
                                                    .font(.system(size: 11, weight: .black))
                                                    .foregroundStyle(.black)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(CinemaTheme.Colors.gold)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    .padding(6)
                                            }
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(userID: user.id) }
        .sheet(isPresented: $showShareCard) {
            ShareCardView(films: vm.topFilms, user: user)
        }
    }
}

@Observable
@MainActor
final class UserProfileViewModel {
    var topFilms: [MediaItem] = []
    var rankedCount: Int = 0
    var isLoading = false

    func load(userID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items: [RankedItem] = try await SupabaseClient.shared
                .from("ranked_items")
                .select()
                .eq("user_id", value: userID)
                .order("elo_score", ascending: false)
                .execute()
                .value
            rankedCount = items.count
            var loaded: [MediaItem] = []
            for item in items.prefix(9) {
                if let media = try? await TMDBClient.shared.details(tmdbID: item.tmdbID, mediaType: item.mediaType) {
                    loaded.append(media)
                }
            }
            topFilms = loaded
        } catch {}
    }
}

// MARK: - Share Card

struct ShareCardView: View {
    let films: [MediaItem]
    let user: CinemaUser?
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, CinemaTheme.Spacing.lg)

                ShareCard(films: films, user: user)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)

                CinemaButton("Share", isLoading: isSharing) {
                    Task { await shareCard() }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)

                Spacer()
            }
        }
    }

    @MainActor
    private func shareCard() async {
        isSharing = true
        defer { isSharing = false }
        let renderer = ImageRenderer(content:
            ShareCard(films: films, user: user)
                .frame(width: 300)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

struct ShareCard: View {
    let films: [MediaItem]
    let user: CinemaUser?

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ],
                spacing: 2
            ) {
                ForEach(Array(films.prefix(9).enumerated()), id: \.element.id) { _, film in
                    PosterImage(path: film.posterPath, cornerRadius: 0)
                        .aspectRatio(2/3, contentMode: .fit)
                }
                ForEach(films.count..<min(films.count > 0 ? 9 : 0, 9), id: \.self) { _ in
                    CinemaTheme.Colors.surface.aspectRatio(2/3, contentMode: .fit)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(user?.username ?? "")")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    if let top = films.first {
                        Text("#1 · \(top.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaTheme.Colors.gold)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("Popcorn")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }
            .padding(14)
            .background(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg))
    }
}
