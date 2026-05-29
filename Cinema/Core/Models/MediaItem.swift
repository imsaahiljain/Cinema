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
    }

    // For detail endpoints (no mediaType in response, passed explicitly)
    init(id: Int, mediaType: MediaType, title: String, overview: String,
         posterPath: String?, backdropPath: String?, releaseYear: String?, voteAverage: Double?) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseYear = releaseYear
        self.voteAverage = voteAverage
    }
}

extension MediaItem {
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
    }
}
