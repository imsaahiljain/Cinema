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
    let genreNames: [String]

    // Search endpoint — has genreIds, no genres array
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
        let dateStr = result.releaseDate ?? result.firstAirDate ?? ""
        self.releaseYear = String(dateStr.prefix(4)).isEmpty ? nil : String(dateStr.prefix(4))
        if let genres = result.genres {
            self.genreNames = genres.map(\.name)
        } else {
            self.genreNames = (result.genreIds ?? []).compactMap { MediaItem.genreMap[$0] }
        }
    }

    // Detail endpoint — mediaType passed explicitly, genres array in response
    init?(from result: TMDBResult, forcedType: MediaType) {
        guard let title = result.title ?? result.name else { return nil }
        self.id = result.id
        self.mediaType = forcedType
        self.title = title
        self.overview = result.overview ?? ""
        self.posterPath = result.posterPath
        self.backdropPath = result.backdropPath
        self.voteAverage = result.voteAverage
        let dateStr = result.releaseDate ?? result.firstAirDate ?? ""
        self.releaseYear = String(dateStr.prefix(4)).isEmpty ? nil : String(dateStr.prefix(4))
        if let genres = result.genres {
            self.genreNames = genres.map(\.name)
        } else {
            self.genreNames = (result.genreIds ?? []).compactMap { MediaItem.genreMap[$0] }
        }
    }

    // Manual init for cases where all data is already known
    init(id: Int, mediaType: MediaType, title: String, overview: String,
         posterPath: String?, backdropPath: String?, releaseYear: String?,
         voteAverage: Double?, genreNames: [String] = []) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseYear = releaseYear
        self.voteAverage = voteAverage
        self.genreNames = genreNames
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
