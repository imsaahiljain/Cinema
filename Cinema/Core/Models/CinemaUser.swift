import Foundation

struct CinemaUser: Identifiable, Codable {
    let id: UUID
    var username: String
    var displayName: String?
    var avatarURL: String?
    var bio: String?
    var onboarded: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio, onboarded
        case createdAt = "created_at"
    }
}

struct RankedItem: Identifiable, Codable {
    let id: UUID
    let userID: UUID
    let tmdbID: Int
    let mediaType: MediaType
    var eloScore: Double
    var rankPosition: Int?
    let addedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case tmdbID = "tmdb_id"
        case mediaType = "media_type"
        case eloScore = "elo_score"
        case rankPosition = "rank_position"
        case addedAt = "added_at"
        case updatedAt = "updated_at"
    }
}

struct FilmNote: Identifiable, Codable {
    let id: UUID
    let userID: UUID
    let tmdbID: Int
    let mediaType: MediaType
    var note: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case tmdbID = "tmdb_id"
        case mediaType = "media_type"
        case note
        case updatedAt = "updated_at"
    }
}

struct ELOMatch: Identifiable, Codable {
    let id: UUID
    let userID: UUID
    let winnerTmdbID: Int
    let loserTmdbID: Int
    let mediaType: String
    let winnerEloBefore: Double?
    let loserEloBefore: Double?
    let winnerEloAfter: Double?
    let loserEloAfter: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case winnerTmdbID = "winner_tmdb_id"
        case loserTmdbID = "loser_tmdb_id"
        case mediaType = "media_type"
        case winnerEloBefore = "winner_elo_before"
        case loserEloBefore = "loser_elo_before"
        case winnerEloAfter = "winner_elo_after"
        case loserEloAfter = "loser_elo_after"
        case createdAt = "created_at"
    }
}
