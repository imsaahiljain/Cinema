import SwiftUI
import UIKit

// MARK: - Story Share Content

enum StoryShareContent {
    case posterGrid(films: [MediaItem], title: String)
    case statCard(title: String, value: String, subtitle: String)
}

// MARK: - InstagramShareService

/// Shares a rendered 9:16 "story" card straight to Instagram Stories via the documented
/// pasteboard + URL-scheme handoff (the same mechanism Spotify Wrapped etc. use) — no
/// Instagram API/OAuth needed. Falls back to the plain iOS share sheet when Instagram isn't
/// installed. Requires `instagram-stories` under `LSApplicationQueriesSchemes` in
/// project.yml — without it, `canOpenURL` silently returns false even when the app IS
/// installed, since iOS 9 requires schemes an app wants to query to be declared up front.
@MainActor
enum InstagramShareService {
    private static let storiesURL = URL(string: "instagram-stories://share")!

    static func share(_ content: StoryShareContent, user: CinemaUser?) {
        let card = StoryShareCard(content: content, user: user)
            .frame(width: 405, height: 720) // 9:16 at a size ImageRenderer handles cleanly
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3

        guard let image = renderer.uiImage else { return }

        if UIApplication.shared.canOpenURL(storiesURL), let jpegData = image.jpegData(compressionQuality: 0.92) {
            UIPasteboard.general.setItems(
                [["com.instagram.sharedSticker.backgroundImage": jpegData]],
                options: [.expirationDate: Date().addingTimeInterval(300)]
            )
            UIApplication.shared.open(storiesURL)
        } else {
            presentShareSheet(image: image)
        }
    }

    private static func presentShareSheet(image: UIImage) {
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
                case .statCard(let title, let value, let subtitle):
                    VStack(spacing: 14) {
                        Text(title.uppercased())
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        Text(value)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(CinemaTheme.Colors.gold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
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
