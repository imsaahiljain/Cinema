import SwiftUI

struct LeaderboardView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("Leaderboard")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
