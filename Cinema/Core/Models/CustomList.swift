import Foundation

struct WatchlistEntry: Identifiable, Codable {
    let id: UUID
    let userID: UUID
    let tmdbID: Int
    let mediaType: MediaType
    let addedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case tmdbID = "tmdb_id"
        case mediaType = "media_type"
        case addedAt = "added_at"
    }
}

struct CustomList: Identifiable, Codable, Hashable {
    let id: UUID
    let userID: UUID
    var name: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case createdAt = "created_at"
    }
}

struct ListItem: Identifiable, Codable {
    let id: UUID
    let listID: UUID
    let tmdbID: Int
    let mediaType: MediaType
    let addedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case listID = "list_id"
        case tmdbID = "tmdb_id"
        case mediaType = "media_type"
        case addedAt = "added_at"
    }
}
