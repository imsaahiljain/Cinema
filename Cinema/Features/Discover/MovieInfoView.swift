import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class MovieInfoViewModel {
    var credits: TMDBCredits?
    var reviews: [TMDBReview] = []
    var director: String?
    var isLoading = false

    func load(film: MediaItem) async {
        isLoading = true
        defer { isLoading = false }
        credits = try? await TMDBClient.shared.credits(tmdbID: film.id, mediaType: film.mediaType)
        director = credits?.crew.first(where: { $0.job == "Director" })?.name
        reviews = (try? await TMDBClient.shared.reviews(tmdbID: film.id, mediaType: film.mediaType)) ?? []
    }
}

// MARK: - MovieInfoView

struct MovieInfoView: View {
    let film: MediaItem
    @State private var vm = MovieInfoViewModel()
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

            // Close
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .task { await vm.load(film: film) }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let path = film.backdropPath,
                   let url = TMDBClient.shared.backdropURL(path: path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            fallbackHero
                        }
                    }
                } else {
                    fallbackHero
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipped()

            // Gradient fade to background
            LinearGradient(
                colors: [.clear, CinemaTheme.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)

            // Title block
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(2)

                metaLine
            }
            .padding(.horizontal, CinemaTheme.Spacing.lg)
            .padding(.bottom, 20)
        }
    }

    private var fallbackHero: some View {
        ZStack {
            CinemaTheme.Colors.surface
            if let path = film.posterPath,
               let url = TMDBClient.shared.posterURL(path: path) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .blur(radius: 16)
                .opacity(0.4)
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let year = film.releaseYear {
                Text(year)
                    .metaStyle()
            }
            if let rt = film.formattedRuntime {
                Text("·")
                    .metaStyle()
                Text(rt)
                    .metaStyle()
            }
            if let score = film.voteAverage, score > 0 {
                Text("·")
                    .metaStyle()
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                    Text(String(format: "%.1f", score))
                        .metaStyle()
                }
            }
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 28) {

            // Genres
            if !film.genreNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(film.genreNames, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(Capsule().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                }
            }

            // Overview
            if !film.overview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Summary")
                    Text(film.overview)
                        .font(.system(size: 15))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }

            // Director
            if let director = vm.director {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Director")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    Text(director)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
            }

            // Cast
            if let cast = vm.credits?.cast, !cast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Cast")
                        .padding(.horizontal, CinemaTheme.Spacing.lg)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(cast.prefix(12)) { person in
                                CastCard(person: person)
                            }
                        }
                        .padding(.horizontal, CinemaTheme.Spacing.lg)
                    }
                }
            }

            // Reviews
            if !vm.reviews.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Reviews")
                        .padding(.horizontal, CinemaTheme.Spacing.lg)

                    VStack(spacing: 12) {
                        ForEach(vm.reviews.prefix(3)) { review in
                            ReviewCard(review: review)
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(CinemaTheme.Colors.textPrimary)
    }
}

private struct CastCard: View {
    let person: TMDBPerson

    var body: some View {
        VStack(spacing: 8) {
            // Profile photo
            Group {
                if let path = person.profilePath,
                   let url = TMDBClient.shared.profileImageURL(path: path) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            personPlaceholder
                        }
                    }
                } else {
                    personPlaceholder
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))

            VStack(spacing: 2) {
                Text(person.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let character = person.character, !character.isEmpty {
                    Text(character)
                        .font(.system(size: 10))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 80)
        }
    }

    private var personPlaceholder: some View {
        CinemaTheme.Colors.surface
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(CinemaTheme.Colors.border)
            )
    }
}

private struct ReviewCard: View {
    let review: TMDBReview
    @State private var expanded = false

    private var truncatedContent: String {
        let limit = 240
        guard review.content.count > limit else { return review.content }
        return String(review.content.prefix(limit)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                // Author initial
                ZStack {
                    Circle()
                        .fill(CinemaTheme.Colors.surface)
                        .frame(width: 36, height: 36)
                    Text(review.author.prefix(1).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(review.author)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)

                    if let rating = review.authorDetails?.rating {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { i in
                                Image(systemName: Double(i) < rating / 2 ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundStyle(CinemaTheme.Colors.gold)
                            }
                        }
                    }
                }
                Spacer()
            }

            Text(expanded ? review.content : truncatedContent)
                .font(.system(size: 14))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if review.content.count > 240 {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "Show less" : "Read more")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
        }
        .padding(16)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.md)
            .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
    }
}

// MARK: - Meta text style

private extension Text {
    func metaStyle() -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(CinemaTheme.Colors.textSecondary)
    }
}
