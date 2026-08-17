import SwiftUI
import PhotosUI
import Supabase

// MARK: - ViewModel

@Observable
@MainActor
final class EditProfileViewModel {
    var displayName: String
    var username: String
    var bio: String
    var selectedPhoto: PhotosPickerItem?
    var profileUIImage: UIImage?

    var isSaving = false
    var isCheckingUsername = false
    var errorMessage: String?

    private let originalUsername: String
    private let originalAvatarURL: String?

    init(user: CinemaUser) {
        displayName = user.displayName ?? ""
        username = user.username
        bio = user.bio ?? ""
        originalUsername = user.username
        originalAvatarURL = user.avatarURL
    }

    var bioCharsRemaining: Int { 150 - bio.count }
    var isUsernameValid: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3
            && trimmed.count <= 20
            && trimmed.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil
    }

    func loadPickedPhoto() async {
        guard let item = selectedPhoto,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        profileUIImage = img
    }

    /// Returns the updated user on success, or nil (with `errorMessage` set) on failure.
    func save(userID: UUID) async -> CinemaUser? {
        errorMessage = nil
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isUsernameValid else {
            errorMessage = "Username must be 3–20 characters: letters, numbers, underscores only."
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if trimmedUsername != originalUsername.lowercased() {
                struct UsernameRow: Decodable { let id: UUID }
                let existing: [UsernameRow] = try await SupabaseClient.shared
                    .from("users")
                    .select("id")
                    .eq("username", value: trimmedUsername)
                    .neq("id", value: userID.uuidString)
                    .execute()
                    .value
                guard existing.isEmpty else {
                    errorMessage = "That username is already taken."
                    return nil
                }
            }

            var avatarURL = originalAvatarURL
            if let image = profileUIImage, let jpegData = image.jpegData(compressionQuality: 0.8) {
                let path = "\(userID.uuidString)/avatar.jpg"
                try await SupabaseClient.shared.storage
                    .from("avatars")
                    .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: true))
                let publicURL = try SupabaseClient.shared.storage
                    .from("avatars")
                    .getPublicURL(path: path, cacheNonce: UUID().uuidString)
                avatarURL = publicURL.absoluteString
            }

            struct UpdatePayload: Encodable {
                let username: String
                let display_name: String?
                let bio: String?
                let avatar_url: String?
            }
            let payload = UpdatePayload(
                username: trimmedUsername,
                display_name: trimmedName.isEmpty ? nil : trimmedName,
                bio: trimmedBio.isEmpty ? nil : trimmedBio,
                avatar_url: avatarURL
            )
            try await SupabaseClient.shared
                .from("users")
                .update(payload)
                .eq("id", value: userID)
                .execute()

            let updated: CinemaUser = try await SupabaseClient.shared
                .from("users")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            return updated
        } catch {
            Log.app.error("EditProfile save failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save changes. Check your connection and try again."
            return nil
        }
    }
}

// MARK: - EditProfileView

struct EditProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EditProfileViewModel
    @FocusState private var focusedField: Field?

    private enum Field { case name, username, bio }

    init(user: CinemaUser) {
        _vm = State(initialValue: EditProfileViewModel(user: user))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaTheme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        avatarPicker

                        VStack(spacing: 16) {
                            field(label: "Name", text: $vm.displayName, placeholder: "Your name", focus: .name)
                            usernameField
                            bioField
                        }
                        .padding(.horizontal, CinemaTheme.Spacing.lg)

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, CinemaTheme.Spacing.lg)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            guard let userID = appState.currentUser?.id else { return }
                            if let updated = await vm.save(userID: userID) {
                                appState.currentUser = updated
                                dismiss()
                            }
                        }
                    } label: {
                        if vm.isSaving {
                            ProgressView().tint(CinemaTheme.Colors.gold)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(CinemaTheme.Colors.gold)
                    .disabled(vm.isSaving || !vm.isUsernameValid)
                }
            }
        }
        .onChange(of: vm.selectedPhoto) { _, _ in Task { await vm.loadPickedPhoto() } }
    }

    // MARK: - Avatar

    private var avatarPicker: some View {
        PhotosPicker(selection: $vm.selectedPhoto, matching: .images) {
            ZStack {
                Group {
                    if let img = vm.profileUIImage {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else if let urlString = appState.currentUser?.avatarURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                            else { avatarInitial }
                        }
                    } else {
                        avatarInitial
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))

                Circle()
                    .fill(CinemaTheme.Colors.gold)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "camera.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black))
                    .offset(x: 34, y: 34)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarInitial: some View {
        CinemaTheme.Colors.surface.overlay(
            Text((vm.displayName.isEmpty ? vm.username : vm.displayName).prefix(1).uppercased())
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
        )
    }

    // MARK: - Fields

    private func field(label: String, text: Binding<String>, placeholder: String, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .tint(CinemaTheme.Colors.gold)
                .focused($focusedField, equals: focus)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CinemaTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm).strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USERNAME")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CinemaTheme.Colors.textSecondary)
            HStack(spacing: 4) {
                Text("@")
                    .font(.system(size: 16))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                TextField("username", text: $vm.username)
                    .font(.system(size: 16))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .tint(CinemaTheme.Colors.gold)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .username)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(CinemaTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm)
                    .strokeBorder(vm.isUsernameValid ? CinemaTheme.Colors.border : Color.red.opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BIO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                Spacer()
                Text("\(vm.bioCharsRemaining)")
                    .font(.system(size: 11))
                    .foregroundStyle(vm.bioCharsRemaining < 0 ? .red.opacity(0.85) : CinemaTheme.Colors.textSecondary)
            }
            TextEditor(text: $vm.bio)
                .font(.system(size: 15))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 80)
                .focused($focusedField, equals: .bio)
                .padding(10)
                .background(CinemaTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: CinemaTheme.Radius.sm).strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                .onChange(of: vm.bio) { _, newValue in
                    if newValue.count > 150 { vm.bio = String(newValue.prefix(150)) }
                }
        }
    }
}
