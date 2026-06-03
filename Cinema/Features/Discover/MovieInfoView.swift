import SwiftUI
import Supabase

// MARK: - Supporting Types

struct FriendTake: Identifiable {
    let id: UUID
    let displayName: String
    let username: String
    let rankPosition: Int?
    let eloScore: Double
}

// MARK: - ViewModel

@Observable
@MainActor
final class MovieInfoViewModel {
    var credits: TMDBCredits?
    var watchProviders: TMDBRegionProviders?
    var trailerKey: String?
    var director: String?
    var friendTakes: [FriendTake] = []
    var isLoading = false

    func load(film: MediaItem, currentUserID: UUID?) async {
        isLoading = true
        defer { isLoading = false }

        credits = try? await TMDBClient.shared.credits(tmdbID: film.id, mediaType: film.mediaType)
        director = credits?.crew.first(where: { $0.job == "Director" })?.name
        watchProviders = try? await TMDBClient.shared.watchProviders(tmdbID: film.id, mediaType: film.mediaType)
        trailerKey = await TMDBClient.shared.trailerKey(tmdbID: film.id, mediaType: film.mediaType)

        if let uid = currentUserID {
            friendTakes = await loadFriendTakes(tmdbID: film.id, currentUserID: uid)
        }
    }

    private func loadFriendTakes(tmdbID: Int, currentUserID: UUID) async -> [FriendTake] {
        struct FollowEdge: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        guard let edges: [FollowEdge] = try? await SupabaseClient.shared
            .from("follows").select("following_id").eq("follower_id", value: currentUserID)
            .execute().value, !edges.isEmpty else { return [] }

        let ids = edges.map(\.followingID)
        guard let items: [RankedItem] = try? await SupabaseClient.shared
            .from("ranked_items").select()
            .eq("tmdb_id", value: tmdbID)
            .in("user_id", values: ids.map(\.uuidString))
            .execute().value, !items.isEmpty else { return [] }

        guard let profiles: [CinemaUser] = try? await SupabaseClient.shared
            .from("users").select()
            .in("id", values: items.map { $0.userID.uuidString })
            .execute().value else { return [] }

        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return items.compactMap { item in
            guard let user = profileMap[item.userID] else { return nil }
            return FriendTake(id: item.userID, displayName: user.displayName ?? user.username,
                              username: user.username, rankPosition: item.rankPosition, eloScore: item.eloScore)
        }
    }
}

// MARK: - MovieInfoView

struct MovieInfoView: View {
    let film: MediaItem
    @State private var vm = MovieInfoViewModel()
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

            // Director
            if let director = vm.director {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Director").font(.system(size: 12, weight: .semibold)).foregroundStyle(CinemaTheme.Colors.textSecondary)
                    Text(director).font(.system(size: 16, weight: .semibold)).foregroundStyle(CinemaTheme.Colors.textPrimary)
                }
            }

            // Cast
            if let cast = vm.credits?.cast, !cast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Cast")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(cast.prefix(12)) { person in CastCard(person: person) }
                        }
                    }
                }
            }

            // Where to Watch
            if let providers = vm.watchProviders {
                whereToWatchSection(providers)
            }

            // Friends' Takes
            if !vm.friendTakes.isEmpty {
                friendTakesSection
            }
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.top, 16)
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
                                Text("Ranked #\(pos) on their list")
                                    .font(.system(size: 12))
                                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        eloStars(take.eloScore)
                    }
                    .padding(12)
                    .background(CinemaTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm))
                }
            }
        }
    }

    private func eloStars(_ elo: Double) -> some View {
        let stars = min(5, max(1, Int((elo - 800) / 160) + 1))
        return HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(i < stars ? CinemaTheme.Colors.gold : CinemaTheme.Colors.border)
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
                if let ch = person.character, !ch.isEmpty {
                    Text(ch).font(.system(size: 10)).foregroundStyle(CinemaTheme.Colors.textSecondary).lineLimit(1)
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
