import Supabase
import Foundation

extension SupabaseClient {
    static let shared = SupabaseClient(
        supabaseURL: URL(string: Secrets.supabaseURL)!,
        supabaseKey: Secrets.supabaseAnonKey
    )
}
