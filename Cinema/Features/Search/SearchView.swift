import SwiftUI

struct SearchView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("Search")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
