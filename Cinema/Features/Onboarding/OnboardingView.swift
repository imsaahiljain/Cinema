import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Text("10-Movie Wall")
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
