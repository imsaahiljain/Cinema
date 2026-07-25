import Foundation

struct TMDBClient {
    static let shared = TMDBClient()

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let imageBaseURL    = "https://image.tmdb.org/t/p/w500"
    private let backdropBaseURL = "https://image.tmdb.org/t/p/w1280"
    private let profileBaseURL  = "https://image.tmdb.org/t/p/w185"
    private let logoBaseURL     = "https://image.tmdb.org/t/p/w92"

    func posterURL(path: String)      -> URL? { URL(string: imageBaseURL    + path) }
    func backdropURL(path: String)    -> URL? { URL(string: backdropBaseURL + path) }
    func profileImageURL(path: String)-> URL? { URL(string: profileBaseURL  + path) }
    func providerLogoURL(path: String)-> URL? { URL(string: logoBaseURL     + path) }

    // MARK: - Discovery

    func trending(mediaType: String = "all", timeWindow: String = "week") async throws -> [MediaItem] {
        let url = baseURL.appending(path: "trending/\(mediaType)/\(timeWindow)")
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0) }
    }

    func nowPlaying() async throws -> [MediaItem] {
        let url = baseURL.appending(path: "movie/now_playing")
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0, forcedType: .movie) }
    }

    /// Movie-only unless `SearchConfig.includeTVShows` is on, in which case genres with a TV
    /// equivalent (see `MediaItem.tvGenreID`) also pull TV results, merged in by popularity.
    func discover(genreID: Int) async throws -> [MediaItem] {
        async let movies = discoverMovies(genreID: genreID)
        guard SearchConfig.includeTVShows, let tvGenreID = MediaItem.tvGenreID(forMovieGenreID: genreID) else {
            return try await movies
        }
        async let shows = discoverTV(genreID: tvGenreID)
        let (movieResults, tvResults) = try await (movies, shows)
        return (movieResults + tvResults).sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }

    private func discoverMovies(genreID: Int) async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "discover/movie")
            .appending(queryItems: [
                .init(name: "with_genres", value: "\(genreID)"),
                .init(name: "sort_by", value: "popularity.desc")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0, forcedType: .movie) }
    }

    private func discoverTV(genreID: Int) async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "discover/tv")
            .appending(queryItems: [
                .init(name: "with_genres", value: "\(genreID)"),
                .init(name: "sort_by", value: "popularity.desc")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0, forcedType: .tv) }
    }

    func criticallyAcclaimed() async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "discover/movie")
            .appending(queryItems: [
                .init(name: "sort_by", value: "vote_average.desc"),
                .init(name: "vote_count.gte", value: "1000"),
                .init(name: "vote_average.gte", value: "8.0")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0, forcedType: .movie) }
    }

    func awardWinners() async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "discover/movie")
            .appending(queryItems: [
                .init(name: "sort_by", value: "vote_count.desc"),
                .init(name: "vote_count.gte", value: "2000"),
                .init(name: "vote_average.gte", value: "8.0")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0, forcedType: .movie) }
    }

    func byPlatform(providerID: Int) async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "discover/movie")
            .appending(queryItems: [
                .init(name: "with_watch_providers", value: "\(providerID)"),
                .init(name: "watch_region", value: "US"),
                .init(name: "sort_by", value: "popularity.desc")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0, forcedType: .movie) }
    }

    // MARK: - Details & Related

    /// Hits TMDB's combined movie/TV/people endpoint regardless of `SearchConfig.includeTVShows` —
    /// TV results are filtered back out below so switching the flag doesn't need a different endpoint.
    func search(query: String, page: Int = 1) async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "search/multi")
            .appending(queryItems: [
                .init(name: "query", value: query),
                .init(name: "page", value: "\(page)"),
                .init(name: "include_adult", value: "false")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        let items = results.results.compactMap { MediaItem(from: $0) }
        return SearchConfig.includeTVShows ? items : items.filter { $0.mediaType == .movie }
    }

    func details(tmdbID: Int, mediaType: MediaType) async throws -> MediaItem {
        let path = mediaType == .movie ? "movie/\(tmdbID)" : "tv/\(tmdbID)"
        let result: TMDBResult = try await fetch(baseURL.appending(path: path))
        guard let item = MediaItem(from: result, forcedType: mediaType) else {
            throw TMDBError.invalidResponse
        }
        return item
    }

    func credits(tmdbID: Int, mediaType: MediaType) async throws -> TMDBCredits {
        let path = mediaType == .movie ? "movie/\(tmdbID)/credits" : "tv/\(tmdbID)/credits"
        return try await fetch(baseURL.appending(path: path))
    }

    func recommendations(tmdbID: Int, mediaType: MediaType) async throws -> [MediaItem] {
        let path = mediaType == .movie ? "movie/\(tmdbID)/recommendations" : "tv/\(tmdbID)/recommendations"
        let results: TMDBSearchResponse = try await fetch(baseURL.appending(path: path))
        return results.results.compactMap { MediaItem(from: $0, forcedType: mediaType) }
    }

    func reviews(tmdbID: Int, mediaType: MediaType) async throws -> [TMDBReview] {
        let path = mediaType == .movie ? "movie/\(tmdbID)/reviews" : "tv/\(tmdbID)/reviews"
        let response: TMDBReviewResponse = try await fetch(baseURL.appending(path: path))
        return response.results
    }

    func watchProviders(tmdbID: Int, mediaType: MediaType) async throws -> TMDBRegionProviders? {
        let path = mediaType == .movie ? "movie/\(tmdbID)/watch/providers" : "tv/\(tmdbID)/watch/providers"
        let response: TMDBWatchProviderResult = try await fetch(baseURL.appending(path: path))
        return response.results["US"]
    }

    /// US content rating — "PG-13"/"R" for movies (from `release_dates`, the first non-blank
    /// certification under the US entry), "TV-MA"/"TV-14" etc for TV (from `content_ratings`).
    /// Two different TMDB endpoints/shapes because movie certifications vary by release type
    /// (theatrical vs. digital) within a country while TV ratings don't.
    func contentRating(tmdbID: Int, mediaType: MediaType) async -> String? {
        if mediaType == .movie {
            guard let response: TMDBReleaseDatesResponse = try? await fetch(baseURL.appending(path: "movie/\(tmdbID)/release_dates")) else { return nil }
            let certification = response.results.first(where: { $0.iso31661 == "US" })?
                .releaseDates.first(where: { !$0.certification.isEmpty })?.certification
            return (certification?.isEmpty ?? true) ? nil : certification
        } else {
            guard let response: TMDBContentRatingsResponse = try? await fetch(baseURL.appending(path: "tv/\(tmdbID)/content_ratings")) else { return nil }
            let rating = response.results.first(where: { $0.iso31661 == "US" })?.rating
            return (rating?.isEmpty ?? true) ? nil : rating
        }
    }

    /// Tagline, franchise/collection name, and (TV only) creators — all only present on the full
    /// detail endpoint (search/discover results never carry them). Collection is movie-only; TV
    /// has no equivalent grouping in TMDB's model, so `belongsToCollection` just decodes absent.
    /// Creators are the TV-only equivalent of "the one name behind this" — TMDB's TV credits
    /// endpoint almost never has a "Director" job (that's an episode-level credit, not a
    /// show-level one), so the real answer to "who made this" lives in `created_by` here instead.
    func extras(tmdbID: Int, mediaType: MediaType) async -> (tagline: String?, collectionName: String?, creators: [TMDBPerson]) {
        let path = mediaType == .movie ? "movie/\(tmdbID)" : "tv/\(tmdbID)"
        guard let result: TMDBExtrasResult = try? await fetch(baseURL.appending(path: path)) else { return (nil, nil, []) }
        let tagline = (result.tagline?.isEmpty ?? true) ? nil : result.tagline
        let creators = (result.createdBy ?? []).map {
            TMDBPerson(id: $0.id, name: $0.name, job: "Creator", character: nil, profilePath: $0.profilePath, order: nil)
        }
        return (tagline, result.belongsToCollection?.name, creators)
    }

    func trailerKey(tmdbID: Int, mediaType: MediaType) async -> String? {
        let path = mediaType == .movie ? "movie/\(tmdbID)/videos" : "tv/\(tmdbID)/videos"
        guard let response: TMDBVideoResponse = try? await fetch(baseURL.appending(path: path)) else { return nil }
        let trailers = response.results.filter { $0.site == "YouTube" && $0.type == "Trailer" }
        return (trailers.first(where: { $0.official }) ?? trailers.first)?.key
    }

    // MARK: - Networking

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(Secrets.tmdbReadAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TMDBError.badStatus }
        return try JSONDecoder.tmdb.decode(T.self, from: data)
    }
}

enum TMDBError: Error { case badStatus, invalidResponse }

extension JSONDecoder {
    static let tmdb: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

// MARK: - Response Types

struct TMDBSearchResponse: Decodable { let results: [TMDBResult] }

struct TMDBResult: Decodable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIds: [Int]?
    let genres: [TMDBGenreItem]?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let originalLanguage: String?
}

struct TMDBGenreItem: Decodable { let id: Int; let name: String }

struct TMDBCredits: Decodable { let cast: [TMDBPerson]; let crew: [TMDBPerson] }

struct TMDBPerson: Identifiable, Decodable {
    let id: Int
    let name: String
    let job: String?
    let character: String?
    let profilePath: String?
    let order: Int?
}

struct TMDBReviewResponse: Decodable { let results: [TMDBReview] }

struct TMDBReview: Identifiable, Decodable {
    let id: String
    let author: String
    let content: String
    let authorDetails: TMDBAuthorDetails?
    struct TMDBAuthorDetails: Decodable { let rating: Double?; let avatarPath: String? }
}

struct TMDBWatchProviderResult: Decodable { let results: [String: TMDBRegionProviders] }

struct TMDBRegionProviders: Decodable {
    let flatrate: [TMDBWatchProvider]?
    let rent: [TMDBWatchProvider]?
    let buy: [TMDBWatchProvider]?
}

struct TMDBWatchProvider: Decodable {
    let providerId: Int
    let providerName: String
    let logoPath: String
}

struct TMDBReleaseDatesResponse: Decodable { let results: [TMDBReleaseDatesCountry] }
struct TMDBReleaseDatesCountry: Decodable { let iso31661: String; let releaseDates: [TMDBReleaseDateEntry] }
struct TMDBReleaseDateEntry: Decodable { let certification: String }

struct TMDBContentRatingsResponse: Decodable { let results: [TMDBContentRatingCountry] }
struct TMDBContentRatingCountry: Decodable { let iso31661: String; let rating: String }

struct TMDBExtrasResult: Decodable { let tagline: String?; let belongsToCollection: TMDBCollectionRef?; let createdBy: [TMDBCreatedBy]? }
struct TMDBCollectionRef: Decodable { let name: String }
struct TMDBCreatedBy: Decodable { let id: Int; let name: String; let profilePath: String? }

struct TMDBVideoResponse: Decodable { let results: [TMDBVideo] }

struct TMDBVideo: Identifiable, Decodable {
    let id: String
    let key: String
    let site: String
    let type: String
    let official: Bool
    let name: String
}
