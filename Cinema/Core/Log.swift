import OSLog

// Namespaced loggers — one per concern. Strip for production by deleting this file
// and replacing call sites with no-ops, or wrap in #if DEBUG.
enum Log {
    static let app     = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "App")
    static let auth    = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Auth")
    static let ranking = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Ranking")
    static let search  = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Search")
    static let feed    = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Feed")
    static let profile = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Profile")
    static let onboarding = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Onboarding")
    static let network = Logger(subsystem: "com.mtgcardneeder.Cinema", category: "Network")
}
