import SwiftUI

// MARK: - WarmTheme — the cream/serif/brick-red design language
//
// Shared by every screen built from a warm-palette design handoff (Marquee
// feed, Rankings list, ...). Colors are exact sRGB conversions of the
// handoff's OKLCH tokens (validated against the CSS Color 4 OKLab matrices,
// not eyeballed) — see design_handoff_marquee_feed/README.md for the
// original oklch values this was derived from.

enum WarmTheme {
    static let background = Color(red: 249 / 255, green: 240 / 255, blue: 231 / 255)
    static let cardBackground = Color.white
    static let wordmark = Color(red: 64 / 255, green: 46 / 255, blue: 39 / 255)
    static let titleText = Color(red: 42 / 255, green: 30 / 255, blue: 26 / 255)
    static let nameText = Color(red: 82 / 255, green: 68 / 255, blue: 64 / 255)
    static let secondaryText = Color(red: 110 / 255, green: 96 / 255, blue: 91 / 255)
    static let tertiaryText = Color(red: 139 / 255, green: 124 / 255, blue: 119 / 255)
    static let captionText = Color(red: 68 / 255, green: 55 / 255, blue: 51 / 255)
    static let accent = Color(red: 197 / 255, green: 56 / 255, blue: 41 / 255)
    static let tagText = Color(red: 144 / 255, green: 83 / 255, blue: 0 / 255)
    static let tagBackground = Color(red: 251 / 255, green: 233 / 255, blue: 198 / 255)
    static let divider = Color(red: 224 / 255, green: 216 / 255, blue: 206 / 255)
    static let chipBackground = Color(red: 231 / 255, green: 223 / 255, blue: 212 / 255)

    enum Font {
        static func wordmark(_ size: CGFloat) -> SwiftUI.Font { .custom("LibreCaslonText-Regular", size: size) }
        static func wordmarkBold(_ size: CGFloat) -> SwiftUI.Font { .custom("LibreCaslonText-Bold", size: size) }
        static func body(_ size: CGFloat) -> SwiftUI.Font { .custom("NunitoSans-Regular", size: size) }
        static func bodySemiBold(_ size: CGFloat) -> SwiftUI.Font { .custom("NunitoSansSemiBold-Regular", size: size) }
        static func bodyBold(_ size: CGFloat) -> SwiftUI.Font { .custom("NunitoSans-Bold", size: size) }
    }
}

// MARK: - Poster placeholder (diagonal stripe, stands in for real poster art)
//
// Used both as the design mockup's literal placeholder look and as the
// real loading/fallback state before a TMDB poster resolves.

struct PosterPlaceholder: View {
    let dark: Color
    let darker: Color

    var body: some View {
        GeometryReader { geo in
            let stripeWidth: CGFloat = 10
            let diagonal = (geo.size.width + geo.size.height) * 1.4
            let stripeCount = max(Int(diagonal / stripeWidth) + 2, 2)

            HStack(spacing: 0) {
                ForEach(0..<stripeCount, id: \.self) { i in
                    Rectangle().fill(i % 2 == 0 ? dark : darker)
                        .frame(width: stripeWidth)
                }
            }
            .frame(width: diagonal, height: diagonal)
            .rotationEffect(.degrees(135))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(
                Text("POSTER")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(6)
            )
        }
    }

    /// Deterministic dark/darker pair derived from a stable identity (e.g. tmdb_id),
    /// so the same title always gets the same placeholder color instead of
    /// re-randomizing on every reload.
    static func colors(seed: Int) -> (dark: Color, darker: Color) {
        let hues: [(Color, Color)] = [
            (Color(red: 112/255, green: 49/255, blue: 53/255), Color(red: 100/255, green: 38/255, blue: 43/255)),
            (Color(red: 27/255, green: 85/255, blue: 44/255), Color(red: 13/255, green: 74/255, blue: 34/255)),
            (Color(red: 0/255, green: 84/255, blue: 98/255), Color(red: 0/255, green: 73/255, blue: 87/255)),
            (Color(red: 103/255, green: 50/255, blue: 87/255), Color(red: 91/255, green: 40/255, blue: 76/255)),
            (Color(red: 111/255, green: 52/255, blue: 31/255), Color(red: 99/255, green: 41/255, blue: 20/255)),
            (Color(red: 58/255, green: 66/255, blue: 120/255), Color(red: 48/255, green: 55/255, blue: 108/255)),
            (Color(red: 90/255, green: 40/255, blue: 40/255), Color(red: 78/255, green: 30/255, blue: 30/255)),
        ]
        let index = ((seed % hues.count) + hues.count) % hues.count
        return hues[index]
    }
}
