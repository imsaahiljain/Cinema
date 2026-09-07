import SwiftUI
import UIKit

// MARK: - Share Card Content

/// One rendered card per case, not one merged multi-section card — each page type gets its
/// own layout tuned to what it's actually showing (a poster stack reads differently than a
/// head-to-head quote), and picking several pages in the carousel's share sheet produces
/// several separate images instead of one crowded collage.
///
/// Deliberately not named/shaped around any single destination (Story, feed post, etc.) —
/// these hand off to the plain iOS share sheet, so whatever the person picks there (Messages,
/// Instagram, Save Image, AirDrop...) decides how it's actually used.
enum ShareCardContent {
    case topFilms(films: [MediaItem])
    case leastLiked(films: [MediaItem])
    case favoriteGenre(genre: String, films: [MediaItem], sharePercent: Int?)
    case hotTake(HotTake)
}

// MARK: - ShareCardService

/// Renders one or more cards and hands them to the standard iOS share sheet together —
/// Messages, Instagram, Save Image, AirDrop, etc. all show up there for free, same as every
/// other share button in the app (`ShareCardView`). Handing over multiple images at once lets
/// apps that support it (Messages, Save Image, AirDrop) take all of them; anything that only
/// takes one just uses the first — that's the receiving app's call, not something to special-case.
@MainActor
enum ShareCardService {
    static func share(_ contents: [ShareCardContent], user: CinemaUser?) async {
        guard !contents.isEmpty else { return }

        // `ImageRenderer` snapshots the view tree synchronously — `Image(uiImage:)` needs a
        // concrete UIImage in hand before that snapshot happens, so every poster across every
        // selected card gets fetched up front rather than left to load asynchronously inside
        // the render (which would come out blank/placeholder). Dedup by id since the same film
        // can show up in more than one selected card (e.g. it's both a Top Film and half of
        // the Hot Take).
        var seenIDs = Set<Int>()
        let allFilms = contents.flatMap(filmsInvolved).filter { seenIDs.insert($0.id).inserted }
        let posterImages = await preloadPosters(for: allFilms)

        var images: [UIImage] = []
        for content in contents {
            let card = ShareRenderCard(content: content, posterImages: posterImages, user: user)
                .frame(width: 405, height: 720) // 9:16 at a size ImageRenderer handles cleanly
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            if let image = renderer.uiImage { images.append(image) }
        }
        guard !images.isEmpty else { return }

        let av = UIActivityViewController(activityItems: images, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private static func filmsInvolved(_ content: ShareCardContent) -> [MediaItem] {
        switch content {
        case .topFilms(let films): return films
        case .leastLiked(let films): return films
        case .favoriteGenre(_, let films, _): return films
        case .hotTake(let hotTake): return [hotTake.preferred, hotTake.snubbed]
        }
    }

    private static func preloadPosters(for films: [MediaItem]) async -> [Int: UIImage] {
        var result: [Int: UIImage] = [:]
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for film in films {
                group.addTask {
                    guard let path = film.posterPath, let url = TMDBClient.shared.posterURL(path: path) else {
                        return (film.id, nil)
                    }
                    guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else {
                        return (film.id, nil)
                    }
                    return (film.id, image)
                }
            }
            for await (id, image) in group {
                result[id] = image
            }
        }
        return result
    }
}

// MARK: - ShareCard (dispatcher)

private struct ShareRenderCard: View {
    let content: ShareCardContent
    let posterImages: [Int: UIImage]
    let user: CinemaUser?

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background
            VStack(spacing: 0) {
                Spacer(minLength: 44)
                cardBody
                Spacer(minLength: 24)
                ShareCardFooter(user: user)
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch content {
        case .topFilms(let films):
            TopFilmsCardBody(films: films, posterImages: posterImages)
        case .leastLiked(let films):
            LeastLikedCardBody(films: films, posterImages: posterImages)
        case .favoriteGenre(let genre, let films, let percent):
            FavoriteGenreCardBody(genre: genre, films: films, percent: percent, posterImages: posterImages)
        case .hotTake(let hotTake):
            HotTakeCardBody(hotTake: hotTake, posterImages: posterImages)
        }
    }
}

// MARK: - Shared poster tile

/// Takes pre-fetched `posterImages` rather than fetching its own — see `ShareCardService`.
private struct SharePosterTile: View {
    let film: MediaItem
    let posterImages: [Int: UIImage]

    var body: some View {
        Group {
            if let image = posterImages[film.id] {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                // Solid fill, no icon — an SF Symbol here would hit the same ImageRenderer
                // rasterization problem pre-fetching posters exists to sidestep.
                CinemaTheme.Colors.surface
            }
        }
    }
}

// MARK: - Top Films

/// A loose fanned stack instead of a flat grid — the #1 film is the actual point of this
/// card, so it's the one thing rendered at full size and legible title; everything else is
/// texture behind it, not competing for attention the way a 9-up grid would.
private struct TopFilmsCardBody: View {
    let films: [MediaItem]
    let posterImages: [Int: UIImage]

    var body: some View {
        VStack(spacing: 22) {
            Text("TOP FILMS")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(CinemaTheme.Colors.gold)

            ZStack {
                if films.count > 2 {
                    tile(films[2]).frame(width: 180, height: 270).rotationEffect(.degrees(8)).opacity(0.45).offset(x: 34, y: 12)
                }
                if films.count > 1 {
                    tile(films[1]).frame(width: 185, height: 278).rotationEffect(.degrees(-7)).opacity(0.7).offset(x: -30, y: 8)
                }
                if let first = films.first {
                    tile(first)
                        .frame(width: 205, height: 308)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                }
            }
            .frame(height: 320)

            if let first = films.first {
                VStack(spacing: 5) {
                    Text("#1").font(.system(size: 12, weight: .black)).foregroundStyle(CinemaTheme.Colors.gold)
                    Text(first.title)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 30)
                }
            }
            if films.count > 1 {
                Text("+\(films.count - 1) more").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func tile(_ film: MediaItem) -> some View {
        SharePosterTile(film: film, posterImages: posterImages).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Least Liked

/// Deliberately deadpan rather than mirroring Top Films' celebratory treatment — desaturated
/// tiles and a dry caption instead of a badge, since "here's what I hated" reads differently
/// than "here's what I loved" and shouldn't use the same visual language.
private struct LeastLikedCardBody: View {
    let films: [MediaItem]
    let posterImages: [Int: UIImage]

    var body: some View {
        VStack(spacing: 22) {
            Text("LEAST LIKED")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(films.prefix(9).enumerated()), id: \.offset) { _, film in
                    SharePosterTile(film: film, posterImages: posterImages)
                        .aspectRatio(2/3, contentMode: .fit)
                        .saturation(0.15)
                        .brightness(-0.08)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 30)

            if let worst = films.first {
                Text(worst.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 30)
            }
            Text("couldn't do it").font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
        }
    }
}

// MARK: - Favorite Genre

/// The genre name is the hero element here, not the posters — a 9-up grid with one small
/// caption made the first version read as "here are some movies," when the actual content is
/// the genre itself. Posters are demoted to supporting evidence underneath.
private struct FavoriteGenreCardBody: View {
    let genre: String
    let films: [MediaItem]
    let percent: Int?
    let posterImages: [Int: UIImage]

    var body: some View {
        VStack(spacing: 20) {
            Text("FAVORITE GENRE")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(CinemaTheme.Colors.gold)

            Text(genre.lowercased())
                .font(.system(size: 50, weight: .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 24)

            HStack(spacing: 5) {
                ForEach(Array(films.prefix(3).enumerated()), id: \.offset) { _, film in
                    SharePosterTile(film: film, posterImages: posterImages)
                        .aspectRatio(2/3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(height: 155)
            .padding(.horizontal, 60)

            if let percent {
                Text("\(percent)% of your top films")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

// MARK: - Hot Take

/// Quote-first, not grid-first — a hot take is a comparison ("I ranked X above Y"), so the
/// statement itself is the largest thing on the card and the two films face off underneath it
/// rather than getting buried in a 9-up grid the way every other page uses.
private struct HotTakeCardBody: View {
    let hotTake: HotTake
    let posterImages: [Int: UIImage]

    var body: some View {
        VStack(spacing: 26) {
            Text("HOT TAKE")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(CinemaTheme.Colors.gold, in: Capsule())

            Text("ranked \(Text(hotTake.preferred.title).fontWeight(.bold)) above \(Text(hotTake.snubbed.title).fontWeight(.bold))")
                .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(5)
            .padding(.horizontal, 26)

            HStack(spacing: 16) {
                SharePosterTile(film: hotTake.preferred, posterImages: posterImages)
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("vs").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                SharePosterTile(film: hotTake.snubbed, posterImages: posterImages)
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(height: 195)
            .padding(.horizontal, 54)
        }
    }
}

// MARK: - Footer

/// Same small watermark on every card regardless of type — a single consistent brand mark
/// rather than a big repeated CTA button, which read as spammy once a share could hand over
/// several of these images at once instead of just one.
private struct ShareCardFooter: View {
    let user: CinemaUser?

    var body: some View {
        HStack(spacing: 8) {
            if let user {
                Text("@\(user.username)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 6) {
                Image("PopcornMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Popcorn")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.gold)
            }
        }
        .padding(.horizontal, 30)
    }
}
