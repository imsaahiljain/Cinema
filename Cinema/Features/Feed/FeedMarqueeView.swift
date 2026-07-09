import SwiftUI

// MARK: - FeedMarqueeView — "Marquee": warm ticket-stub card feed
//
// Isolated prototype — no network calls, no Supabase writes. Built directly
// from the high-fidelity design handoff in design_handoff_marquee_feed/
// (colors extracted pixel-exact from the reference mockup via a canvas
// readback, not eyeballed; fonts are the real Google Fonts named in the
// spec, bundled as static Regular/SemiBold/Bold instances — see
// Cinema/Resources/Fonts/).
//
// Rating pill is computed, not editorial: a film's displayed X/10 is
// derived from the poster's rank position within the friend's own ranked
// list (10.0 = their #1, scaling down to their lowest-ranked film) — see
// `ratingOutOf10(rankPosition:totalRanked:)`.
//
// Hand-test on a physical device for scroll feel and the tap-to-expand
// caption/tag animation.

// MARK: - Rating formula

func ratingOutOf10(rankPosition: Int, totalRanked: Int) -> Double {
    guard totalRanked > 1 else { return 10 }
    let fraction = Double(rankPosition - 1) / Double(totalRanked - 1)
    return 10 * (1 - fraction)
}

// MARK: - Theme (exact tokens from the design handoff, converted from OKLCH to sRGB)

private enum MarqueeTheme {
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
    static let perforationLine = Color(red: 232 / 255, green: 219 / 255, blue: 209 / 255)

    enum Font {
        static func wordmark(_ size: CGFloat) -> SwiftUI.Font { .custom("LibreCaslonText-Regular", size: size) }
        static func wordmarkBold(_ size: CGFloat) -> SwiftUI.Font { .custom("LibreCaslonText-Bold", size: size) }
        static func body(_ size: CGFloat) -> SwiftUI.Font { .custom("NunitoSans-Regular", size: size) }
        static func bodySemiBold(_ size: CGFloat) -> SwiftUI.Font { .custom("NunitoSansSemiBold-Regular", size: size) }
        static func bodyBold(_ size: CGFloat) -> SwiftUI.Font { .custom("NunitoSans-Bold", size: size) }
    }
}

// MARK: - Mock data

private struct MockPop: Identifiable {
    let id: Int
    let friend: String
    let avatarColor: Color
    let posterDark: Color
    let posterDarker: Color
    let time: String
    let movie: String
    let year: Int
    let rankPosition: Int
    let totalRanked: Int
    let caption: String
    let tags: [String]
    let likes: Int
    let comments: Int

    var rating: Double { ratingOutOf10(rankPosition: rankPosition, totalRanked: totalRanked) }
    var ratingLabel: String { String(format: "%.1f", rating) }
}

// Colors sampled pixel-exact from oklch(0.62 0.11 {hue+40}) (avatar) and
// oklch(0.4/0.36 0.09 {hue}) (poster) for each friend's hue in the handoff's
// sample data. Rank/total chosen so the computed rating lands close to the
// original mockup's editorial numbers, to confirm the formula is sound.
private let mockPops: [MockPop] = [
    MockPop(id: 1, friend: "Sofia Chen",
            avatarColor: Color(red: 183/255, green: 116/255, blue: 61/255),
            posterDark: Color(red: 112/255, green: 49/255, blue: 53/255),
            posterDarker: Color(red: 100/255, green: 38/255, blue: 43/255),
            time: "2h", movie: "Past Lives", year: 2023, rankPosition: 7, totalRanked: 50,
            caption: "Cried on the subway home. Didn't expect that.",
            tags: ["Celine Song", "A24"], likes: 12, comments: 3),
    MockPop(id: 2, friend: "Marcus Webb",
            avatarColor: Color(red: 79/255, green: 138/255, blue: 198/255),
            posterDark: Color(red: 0/255, green: 84/255, blue: 98/255),
            posterDarker: Color(red: 0/255, green: 73/255, blue: 87/255),
            time: "4h", movie: "Dune: Part Two", year: 2024, rankPosition: 5, totalRanked: 50,
            caption: "IMAX was mandatory for this one. Sound alone is a 10.",
            tags: ["Denis Villeneuve", "Sci-Fi"], likes: 34, comments: 8),
    MockPop(id: 3, friend: "Priya Patel",
            avatarColor: Color(red: 159/255, green: 113/255, blue: 180/255),
            posterDark: Color(red: 58/255, green: 66/255, blue: 120/255),
            posterDarker: Color(red: 48/255, green: 55/255, blue: 108/255),
            time: "6h", movie: "The Bear", year: 2024, rankPosition: 12, totalRanked: 50,
            caption: "S3E1 — not as strong as season 1 but still good.",
            tags: ["TV", "FX"], likes: 9, comments: 1),
    MockPop(id: 4, friend: "Jordan Lee",
            avatarColor: Color(red: 191/255, green: 105/255, blue: 106/255),
            posterDark: Color(red: 103/255, green: 50/255, blue: 87/255),
            posterDarker: Color(red: 91/255, green: 40/255, blue: 76/255),
            time: "9h", movie: "Anora", year: 2024, rankPosition: 3, totalRanked: 50,
            caption: "Palme d'Or well deserved. Rewatching this weekend.",
            tags: ["Sean Baker", "Comedy"], likes: 41, comments: 12),
    MockPop(id: 5, friend: "Ava Torres",
            avatarColor: Color(red: 169/255, green: 126/255, blue: 44/255),
            posterDark: Color(red: 111/255, green: 52/255, blue: 31/255),
            posterDarker: Color(red: 99/255, green: 41/255, blue: 20/255),
            time: "11h", movie: "Twisters", year: 2024, rankPosition: 19, totalRanked: 50,
            caption: "Popcorn movie, exactly what I wanted on a Friday.",
            tags: ["Action"], likes: 6, comments: 0),
    MockPop(id: 6, friend: "Noah Kim",
            avatarColor: Color(red: 0/255, green: 155/255, blue: 149/255),
            posterDark: Color(red: 27/255, green: 85/255, blue: 44/255),
            posterDarker: Color(red: 13/255, green: 74/255, blue: 34/255),
            time: "1d", movie: "The Zone of Interest", year: 2023, rankPosition: 6, totalRanked: 50,
            caption: "Haunting. Still thinking about the sound design.",
            tags: ["Jonathan Glazer", "Drama"], likes: 22, comments: 5),
    MockPop(id: 7, friend: "Liam Ortiz",
            avatarColor: Color(red: 182/255, green: 117/255, blue: 59/255),
            posterDark: Color(red: 112/255, green: 49/255, blue: 51/255),
            posterDarker: Color(red: 100/255, green: 38/255, blue: 41/255),
            time: "1d", movie: "Challengers", year: 2024, rankPosition: 9, totalRanked: 50,
            caption: "That soundtrack lives in my head rent free.",
            tags: ["Luca Guadagnino"], likes: 28, comments: 6),
]

// MARK: - FeedMarqueeView

struct FeedMarqueeView: View {
    @State private var expandedIDs: Set<Int> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(mockPops) { pop in
                        PopCard(pop: pop, isExpanded: expandedIDs.contains(pop.id)) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedIDs.contains(pop.id) {
                                    expandedIDs.remove(pop.id)
                                } else {
                                    expandedIDs.insert(pop.id)
                                }
                            }
                        }
                    }
                } header: {
                    header
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(MarqueeTheme.background.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Popcorn")
                .font(MarqueeTheme.Font.wordmark(30))
                .foregroundStyle(MarqueeTheme.wordmark)
            Text("What your friends are watching")
                .font(MarqueeTheme.Font.body(12))
                .foregroundStyle(MarqueeTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(MarqueeTheme.background)
    }
}

// MARK: - Pop Card

private struct PopCard: View {
    let pop: MockPop
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PosterPlaceholder(dark: pop.posterDark, darker: pop.posterDarker)
                .frame(width: 96)

            TicketPerforation()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    InitialsAvatar(name: pop.friend, color: pop.avatarColor, size: 22)
                    Text(pop.friend)
                        .font(MarqueeTheme.Font.bodyBold(12.5))
                        .foregroundStyle(MarqueeTheme.nameText)
                    Text("· \(pop.time)")
                        .font(MarqueeTheme.Font.body(11.5))
                        .foregroundStyle(MarqueeTheme.tertiaryText)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(pop.movie)
                        .font(MarqueeTheme.Font.wordmark(19))
                        .foregroundStyle(MarqueeTheme.titleText)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(pop.ratingLabel)
                        .font(MarqueeTheme.Font.wordmarkBold(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MarqueeTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                }

                Text(pop.caption)
                    .font(MarqueeTheme.Font.body(13.5))
                    .foregroundStyle(MarqueeTheme.captionText)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    HStack(spacing: 6) {
                        ForEach(pop.tags, id: \.self) { tag in
                            Text(tag)
                                .font(MarqueeTheme.Font.bodySemiBold(11))
                                .foregroundStyle(MarqueeTheme.tagText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(MarqueeTheme.tagBackground, in: Capsule())
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 14) {
                    Text("♥ \(pop.likes)")
                    Text("💬 \(pop.comments)")
                }
                .font(MarqueeTheme.Font.bodySemiBold(12))
                .foregroundStyle(MarqueeTheme.secondaryText)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .background(MarqueeTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 60/255, green: 30/255, blue: 10/255).opacity(0.06), radius: 1, x: 0, y: 1)
        .shadow(color: Color(red: 60/255, green: 30/255, blue: 10/255).opacity(0.08), radius: 10, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Poster placeholder (diagonal stripe, stands in for real poster art)

private struct PosterPlaceholder: View {
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
}

// MARK: - Ticket perforation (tear-edge between poster and content)

private struct DashedVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        return p
    }
}

private struct TicketPerforation: View {
    var body: some View {
        ZStack {
            DashedVLine()
                .stroke(MarqueeTheme.perforationLine, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            VStack {
                Circle().fill(MarqueeTheme.background).frame(width: 14, height: 14)
                Spacer()
                Circle().fill(MarqueeTheme.background).frame(width: 14, height: 14)
            }
        }
        .frame(width: 14)
    }
}

// MARK: - Avatar

private struct InitialsAvatar: View {
    let name: String
    let color: Color
    let size: CGFloat

    private var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

#Preview {
    FeedMarqueeView()
}
