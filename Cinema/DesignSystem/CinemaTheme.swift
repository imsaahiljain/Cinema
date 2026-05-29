import SwiftUI

enum CinemaTheme {
    enum Colors {
        static let background = Color(red: 0.039, green: 0.039, blue: 0.059)   // #0A0A0F
        static let surface = Color(red: 0.09, green: 0.09, blue: 0.13)
        static let gold = Color(red: 0.961, green: 0.784, blue: 0.259)         // #F5C842
        static let goldMuted = Color(red: 0.961, green: 0.784, blue: 0.259).opacity(0.7)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)
        static let border = Color.white.opacity(0.12)
    }

    enum Typography {
        static func displayLarge(_ text: String) -> some View {
            Text(text).font(.system(.largeTitle, design: .default, weight: .bold))
        }
        static func title(_ text: String) -> some View {
            Text(text).font(.system(.title2, design: .default, weight: .semibold))
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let full: CGFloat = 999
    }
}
