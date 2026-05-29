import SwiftUI

struct AuthView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("Auth")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
