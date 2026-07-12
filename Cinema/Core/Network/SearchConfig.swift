import Foundation

/// Single switch for whether TV shows appear anywhere in Search/Discover (typed search, trending,
/// genre browsing, and the screen copy that references them). Launching movie-only; flip this to
/// `true` to turn TV shows on everywhere at once.
///
/// Genre browsing only adds TV for genres TMDB has a TV equivalent for — see
/// `MediaItem.tvGenreID(forMovieGenreID:)`. Genres without one (Horror, Thriller, Romance) stay
/// movie-only even after the flip; TMDB's TV genre list just doesn't have those.
enum SearchConfig {
    static let includeTVShows = false
}
