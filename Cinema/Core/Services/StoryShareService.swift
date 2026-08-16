import SwiftUI
import UIKit

// MARK: - Story Share Content

enum StoryShareContent {
    case posterGrid(films: [MediaItem], title: String)
}

// MARK: - StoryShareService

/// Renders a 9:16 "story" card and hands it to the standard iOS share sheet — Messages,
/// Instagram, Facebook, WhatsApp, Save Image, etc. all show up there for free, exactly like
/// every other share button in the app (`ShareCardView`).
///
/// A prior version tried to post straight to Instagram Stories via the documented pasteboard
/// + `instagram-stories://` URL-scheme handoff, skipping the share sheet entirely. That's a
/// real, commonly-used mechanism, but it failed in practice — real Instagram rejected it with
/// "this app doesn't currently support sharing to stories," which happens when Instagram's
/// own allowlist/format checks on the pasteboard payload don't pass, not something fixable by
/// tweaking the pasteboard dictionary further. The share sheet's own Instagram entry already
/// opens Instagram's native share flow (Stories/Feed/DM, user's choice) and just works, so
/// that one-tap "skip Instagram's own UI" shortcut isn't worth the fragility.
@MainActor
enum StoryShareService {
    static func share(_ content: StoryShareContent, user: CinemaUser?) {
        let card = StoryShareCard(content: content, user: user)
            .frame(width: 405, height: 720) // 9:16 at a size ImageRenderer handles cleanly
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3

        guard let image = renderer.uiImage else { return }

        let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - StoryShareCard

/// The actual pixels that get rendered and handed off — kept visually consistent with
/// `ShareCard` (the existing Top-Films share card) but reformatted to a full 9:16 story
/// frame instead of a square-ish grid card, since Stories crop/pad anything that isn't.
struct StoryShareCard: View {
    let content: StoryShareContent
    let user: CinemaUser?

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background

            VStack(spacing: 28) {
                Spacer()

                switch content {
                case .posterGrid(let films, let title):
                    VStack(spacing: 18) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)],
                            spacing: 3
                        ) {
                            ForEach(Array(films.prefix(9).enumerated()), id: \.offset) { _, film in
                                PosterImage(path: film.posterPath, cornerRadius: 6)
                                    .aspectRatio(2/3, contentMode: .fit)
                            }
                        }
                        .padding(.horizontal, 36)
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    if let user {
                        Text("@\(user.username)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    }
                    Text("Popcorn")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
                .padding(.bottom, 56)
            }
        }
    }
}
