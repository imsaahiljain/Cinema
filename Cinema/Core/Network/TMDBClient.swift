import Foundation

struct TMDBClient {
    static let shared = TMDBClient()

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let imageBaseURL = "https://image.tmdb.org/t/p/w500"

    func posterURL(path: String) -> URL? {
        URL(string: imageBaseURL + path)
    }

    func search(query: String, page: Int = 1) async throws -> [MediaItem] {
        let url = baseURL
            .appending(path: "search/multi")
            .appending(queryItems: [
                .init(name: "query", value: query),
                .init(name: "page", value: "\(page)"),
                .init(name: "include_adult", value: "false")
            ])
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0) }
    }

    func trending(mediaType: String = "all", timeWindow: String = "week") async throws -> [MediaItem] {
        let url = baseURL.appending(path: "trending/\(mediaType)/\(timeWindow)")
        let results: TMDBSearchResponse = try await fetch(url)
        return results.results.compactMap { MediaItem(from: $0) }
    }

    func details(tmdbID: Int, mediaType: MediaType) async throws -> MediaItem {
        let path = mediaType == .movie ? "movie/\(tmdbID)" : "tv/\(tmdbID)"
        let result: TMDBResult = try await fetch(baseURL.appending(path: path))
        guard let item = MediaItem(from: result) else {
            throw TMDBError.invalidResponse
        }
        return item
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(Secrets.tmdbReadAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TMDBError.badStatus
        }
        return try JSONDecoder.tmdb.decode(T.self, from: data)
    }
}

enum TMDBError: Error {
    case badStatus
    case invalidResponse
}

extension JSONDecoder {
    static let tmdb: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

// MARK: - TMDB Response Types

struct TMDBSearchResponse: Decodable {
    let results: [TMDBResult]
}

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
    let genreIds: [Int]?
}
