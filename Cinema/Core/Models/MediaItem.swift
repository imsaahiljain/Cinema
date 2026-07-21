import Foundation

enum MediaType: String, Codable {
    case movie
    case tv
}

struct MediaItem: Identifiable, Hashable {
    let id: Int
    let mediaType: MediaType
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseYear: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreNames: [String]
    let runtime: Int?
    let originalLanguage: String?
    let popularity: Double?

    init?(from result: TMDBResult) {
        guard let rawType = result.mediaType, let type_ = MediaType(rawValue: rawType),
              let title = result.title ?? result.name else { return nil }
        self.id = result.id
        self.mediaType = type_
        self.title = title
        self.overview = result.overview ?? ""
        self.posterPath = result.posterPath
        self.backdropPath = result.backdropPath
        self.voteAverage = result.voteAverage
        self.voteCount = result.voteCount
        let dateStr = result.releaseDate ?? result.firstAirDate ?? ""
        self.releaseYear = String(dateStr.prefix(4)).isEmpty ? nil : String(dateStr.prefix(4))
        self.genreNames = result.genres.map { g in g.map { $0.name } }
            ?? (result.genreIds ?? []).compactMap { MediaItem.genreMap[$0] }
        self.runtime = result.runtime ?? result.episodeRunTime?.first
        self.originalLanguage = result.originalLanguage
        self.popularity = result.popularity
    }

    init?(from result: TMDBResult, forcedType: MediaType) {
        guard let title = result.title ?? result.name else { return nil }
        self.id = result.id
        self.mediaType = forcedType
        self.title = title
        self.overview = result.overview ?? ""
        self.posterPath = result.posterPath
        self.backdropPath = result.backdropPath
        self.voteAverage = result.voteAverage
        self.voteCount = result.voteCount
        let dateStr = result.releaseDate ?? result.firstAirDate ?? ""
        self.releaseYear = String(dateStr.prefix(4)).isEmpty ? nil : String(dateStr.prefix(4))
        self.genreNames = result.genres.map { g in g.map { $0.name } }
            ?? (result.genreIds ?? []).compactMap { MediaItem.genreMap[$0] }
        self.runtime = result.runtime ?? result.episodeRunTime?.first
        self.originalLanguage = result.originalLanguage
        self.popularity = result.popularity
    }

    init(id: Int, mediaType: MediaType, title: String, overview: String,
         posterPath: String?, backdropPath: String?, releaseYear: String?,
         voteAverage: Double?, voteCount: Int? = nil, genreNames: [String] = [], runtime: Int? = nil,
         originalLanguage: String? = nil, popularity: Double? = nil) {
        self.id = id; self.mediaType = mediaType; self.title = title
        self.overview = overview; self.posterPath = posterPath
        self.backdropPath = backdropPath; self.releaseYear = releaseYear
        self.voteAverage = voteAverage; self.voteCount = voteCount; self.genreNames = genreNames
        self.runtime = runtime; self.originalLanguage = originalLanguage
        self.popularity = popularity
    }

    var formattedRuntime: String? {
        guard let r = runtime, r > 0 else { return nil }
        let h = r / 60, m = r % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// TMDB's movie and TV genre lists don't line up 1:1 — some share names but use different IDs,
    /// and a few movie genres (Horror, Thriller, Romance) have no TV equivalent at all. Returns nil
    /// when there's nothing sensible to browse on the TV side.
    static func tvGenreID(forMovieGenreID movieGenreID: Int) -> Int? {
        switch movieGenreID {
        case 28: return 10759   // Action -> Action & Adventure
        case 18: return 18      // Drama
        case 35: return 35      // Comedy
        case 878: return 10765  // Sci-Fi -> Sci-Fi & Fantasy
        case 16: return 16      // Animation
        case 80: return 80      // Crime
        case 99: return 99      // Documentary
        default: return nil     // Thriller, Horror, Romance
        }
    }

    static let genreMap: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
        80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        53: "Thriller", 10752: "War", 37: "Western", 10770: "TV Movie",
        10759: "Action & Adventure", 10762: "Kids", 10763: "News",
        10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap",
        10767: "Talk", 10768: "War & Politics"
    ]
}
