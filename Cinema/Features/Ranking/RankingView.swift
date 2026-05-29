import SwiftUI

struct RankingView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("This or That")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
