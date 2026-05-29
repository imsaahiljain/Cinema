import SwiftUI

struct ProfileView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("Profile")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
