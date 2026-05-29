import SwiftUI

struct FeedView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("Feed")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
