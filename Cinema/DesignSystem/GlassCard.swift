import SwiftUI

// MARK: - GlassCard

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

// MARK: - Shared UI Components

struct CinemaButton: View {
    let title: String
    var isLoading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    init(_ title: String, isLoading: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(enabled ? CinemaTheme.Colors.gold : CinemaTheme.Colors.gold.opacity(0.35))
            .clipShape(Capsule())
        }
        .disabled(!enabled || isLoading)
    }
}

struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = false

    init(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .tint(CinemaTheme.Colors.gold)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(!autocorrect)
                .textInputAutocapitalization(autocapitalization)
                .padding(.bottom, 12)

            Rectangle()
                .fill(text.isEmpty ? Color.white.opacity(0.2) : CinemaTheme.Colors.gold)
                .frame(height: 1)
                .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        }
    }
}

struct OnboardingSecureField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        VStack(spacing: 0) {
            SecureField(placeholder, text: $text)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .tint(CinemaTheme.Colors.gold)
                .padding(.bottom, 12)

            Rectangle()
                .fill(text.isEmpty ? Color.white.opacity(0.2) : CinemaTheme.Colors.gold)
                .frame(height: 1)
                .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        }
    }
}

struct OnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)

            Text(subtitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GenreChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .black : CinemaTheme.Colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? CinemaTheme.Colors.gold : CinemaTheme.Colors.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? CinemaTheme.Colors.gold : CinemaTheme.Colors.border,
                        lineWidth: 1
                    )
                )
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

struct PosterImage: View {
    let path: String?
    var cornerRadius: CGFloat = CinemaTheme.Radius.md

    var body: some View {
        Group {
            if let path, let url = TMDBClient.shared.posterURL(path: path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    default:
                        CinemaTheme.Colors.surface
                            .overlay(ProgressView().tint(CinemaTheme.Colors.textSecondary))
                    }
                }
            } else {
                placeholderView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholderView: some View {
        CinemaTheme.Colors.surface
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 24))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
            )
    }
}
