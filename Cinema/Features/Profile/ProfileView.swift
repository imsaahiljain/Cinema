import SwiftUI
import Supabase

// MARK: - Local Types

struct TasteProfile {
    let topGenres: [String]
    let favoriteDirector: String?
    let favoriteActors: [String]
}

private struct FollowRecord: Decodable {
    let followerID: UUID
    let followingID: UUID
    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class ProfileViewModel {
    var allRankedItems: [RankedItem] = []
    var topFilms: [MediaItem] = []
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

            if items.count >= 25 && tasteProfile == nil {
                isTasteProfileLoading = true
                await loadTasteProfile(items: Array(items.prefix(25)))
                isTasteProfileLoading = false
            }
        } catch {}
    }

    private func loadTasteProfile(items: [RankedItem]) async {
        var genreFreq: [String: Int] = [:]
        var directorFreq: [String: Int] = [:]
        var actorFreq: [String: Int] = [:]

        await withTaskGroup(of: ([String], String?, [String]).self) { group in
            for item in items {
                let tmdbID = item.tmdbID
                let mediaType = item.mediaType
                group.addTask {
                    var genres: [String] = []
                    var director: String? = nil
                    var actors: [String] = []
                    if let media = try? await TMDBClient.shared.details(tmdbID: tmdbID, mediaType: mediaType) {
                        genres = media.genreNames
                    }
                    if let credits = try? await TMDBClient.shared.credits(tmdbID: tmdbID, mediaType: mediaType) {
                        director = credits.crew.first(where: { $0.job == "Director" })?.name
                        actors = credits.cast.prefix(3).map(\.name)
                    }
                    return (genres, director, actors)
                }
            }
            for await (genres, director, actors) in group {
                for g in genres { genreFreq[g, default: 0] += 1 }
                if let d = director { directorFreq[d, default: 0] += 1 }
                for a in actors { actorFreq[a, default: 0] += 1 }
            }
        }

        let topGenres = Array(genreFreq.sorted { $0.value > $1.value }.prefix(3).map(\.key))
        let topDirector = directorFreq.sorted { $0.value > $1.value }.first?.key
        let topActors = Array(actorFreq.sorted { $0.value > $1.value }.prefix(3).map(\.key))
        tasteProfile = TasteProfile(topGenres: topGenres, favoriteDirector: topDirector, favoriteActors: topActors)
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ProfileViewModel()
    @State private var showShareCard = false
    @State private var showFollowers = false
    @State private var showFollowing = false

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
                        topFilmsSection
                        filmFingerprintSection
                        signOutButton
                        Spacer().frame(height: 100)
                    }
                }
                .refreshable { await vm.load(userID: appState.currentUser?.id) }
            }
        }
        .task { await vm.load(userID: appState.currentUser?.id) }
        .sheet(isPresented: $showFollowers) {
            FollowListView(mode: .followers, userID: appState.currentUser?.id)
        }
        .sheet(isPresented: $showFollowing) {
            FollowListView(mode: .following, userID: appState.currentUser?.id)
        }
        .sheet(isPresented: $showShareCard) {
            ShareCardView(films: vm.topFilms, user: appState.currentUser)
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(CinemaTheme.Colors.surface)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                Text(appState.currentUser?.displayName?.prefix(1).uppercased()
                     ?? appState.currentUser?.username.prefix(1).uppercased()
                     ?? "?")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
            }
            .padding(.top, 56)

            VStack(spacing: 5) {
                Text(appState.currentUser?.displayName ?? appState.currentUser?.username ?? "")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Text("@\(appState.currentUser?.username ?? "")")
                    .font(.system(size: 15))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
    }

    // MARK: - Social Stats

    private var socialStats: some View {
        HStack(spacing: 0) {
            StatCell(value: "\(vm.rankedCount)", label: "Ranked", tappable: false) {}

            Rectangle()
                .fill(CinemaTheme.Colors.border)
                .frame(width: 1, height: 40)

            StatCell(value: "\(vm.followerCount)", label: "Followers", tappable: true) {
                showFollowers = true
            }

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

    // MARK: - Top Films

    private var topFilmsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Top Films")
                    .font(.system(size: 22, weight: .bold))
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
                Text("Rank 9 films to see your top grid.")
                    .font(.system(size: 14))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.bottom, 8)
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
        .padding(.bottom, 36)
    }

    // MARK: - Film Fingerprint

    private var filmFingerprintSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Film Fingerprint")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                Spacer()
                if vm.rankedCount < 25 {
                    Text("\(vm.rankedCount) of 25")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .padding(.bottom, 16)

            if vm.rankedCount < 25 {
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
        .padding(.bottom, 36)
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

    private func unlockedFingerprintView(_ profile: TasteProfile) -> some View {
        VStack(spacing: 1) {
            if !profile.topGenres.isEmpty {
                FingerprintRow(label: "Genres") {
                    HStack(spacing: 8) {
                        ForEach(profile.topGenres, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(CinemaTheme.Colors.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                        }
                        Spacer()
                    }
                }
            }

            if let director = profile.favoriteDirector {
                FingerprintRow(label: "Director") {
                    Text(director)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                }
            }

            if !profile.favoriteActors.isEmpty {
                FingerprintRow(label: "Starring") {
                    Text(profile.favoriteActors.joined(separator: "  ·  "))
                        .font(.system(size: 14))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        .lineLimit(2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
        .padding(.horizontal, CinemaTheme.Spacing.lg)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            Task { await appState.signOut() }
        } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.red.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CinemaTheme.Spacing.lg)
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

private struct FingerprintRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(CinemaTheme.Colors.surface)
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
                Text("Cinema")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            }
            .padding(14)
            .background(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg))
    }
}
