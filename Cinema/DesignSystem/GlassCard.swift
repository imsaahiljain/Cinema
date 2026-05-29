import SwiftUI

struct GlassCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg)
                    .strokeBorder(CinemaTheme.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.lg))
    }
}
