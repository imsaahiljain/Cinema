import SwiftUI
import Supabase

// MARK: - ViewModel

/// Moved out of Search (was a "Films / People" segment there) — Search is a movie-discovery
/// screen (trending poster grid, genre chips) and finding people never belonged next to that.
/// Lives in Profile instead, reached via the person-search icon next to Settings.
@Observable
@MainActor
final class PeopleSearchViewModel {
    var query = ""
    var results: [CinemaUser] = []
    var followedIDs: Set<UUID> = []
    var isSearching = false

    var isQueryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchTask: Task<Void, Never>?

    func onQueryChange() {
        searchTask?.cancel()
        guard !isQueryEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        results = (try? await SupabaseClient.shared
            .from("users").select()
            .ilike("username", pattern: "%\(q.lowercased())%")
            .limit(20).execute().value) ?? []
        isSearching = false
    }

    func loadFollowedIDs(userID: UUID?) async {
        guard let userID else { return }
        struct FE: Decodable {
            let followingID: UUID
            enum CodingKeys: String, CodingKey { case followingID = "following_id" }
        }
        do {
            let edges: [FE] = try await SupabaseClient.shared
                .from("follows").select("following_id").eq("follower_id", value: userID).execute().value
            followedIDs = Set(edges.map { $0.followingID })
        } catch {}
    }

    func toggleFollow(user: CinemaUser, currentUserID: UUID?) async {
        guard let currentUserID else { return }
        if followedIDs.contains(user.id) {
            do {
                try await SupabaseClient.shared.from("follows").delete()
                    .eq("follower_id", value: currentUserID.uuidString)
                    .eq("following_id", value: user.id.uuidString).execute()
                followedIDs.remove(user.id)
            } catch {}
        } else {
            do {
                try await SupabaseClient.shared.from("follows")
                    .upsert(["follower_id": currentUserID.uuidString, "following_id": user.id.uuidString])
                    .execute()
                followedIDs.insert(user.id)
            } catch {}
        }
    }
}

// MARK: - PeopleSearchView

struct PeopleSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm = PeopleSearchViewModel()
    @FocusState private var searchFocused: Bool
    @State private var selectedUser: CinemaUser?

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaTheme.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 14)

                    if vm.isSearching {
                        Spacer()
                        ProgressView().tint(CinemaTheme.Colors.gold)
                        Spacer()
                    } else if vm.isQueryEmpty {
                        Spacer()
                        Text("Search for a username to find friends.")
                            .font(.system(size: 15))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    } else if vm.results.isEmpty {
                        Spacer()
                        Text("No one found for \u{201C}\(vm.query)\u{201D}")
                            .font(.system(size: 15))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(vm.results) { user in
                                    PeopleResultRow(
                                        user: user,
                                        isFollowing: vm.followedIDs.contains(user.id),
                                        isCurrentUser: user.id == appState.currentUser?.id,
                                        onTap: { selectedUser = user },
                                        onFollow: { Task { await vm.toggleFollow(user: user, currentUserID: appState.currentUser?.id) } }
                                    )
                                    Divider()
                                        .background(CinemaTheme.Colors.border)
                                        .padding(.leading, 78)
                                }
                            }
                            .padding(.bottom, 100)
                        }
                        .scrollDismissesKeyboard(.immediately)
                    }
                }
            }
            .navigationTitle("Find People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
        }
        .task { await vm.loadFollowedIDs(userID: appState.currentUser?.id) }
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileView(user: user)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedUser = nil }
                                .foregroundStyle(CinemaTheme.Colors.gold)
                        }
                    }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    searchFocused || !vm.query.isEmpty
                        ? CinemaTheme.Colors.textPrimary
                        : CinemaTheme.Colors.textSecondary
                )
                .animation(.easeInOut(duration: 0.15), value: searchFocused)

            TextField("Search by username...", text: $vm.query)
                .font(.system(size: 16))
                .foregroundStyle(CinemaTheme.Colors.textPrimary)
                .tint(CinemaTheme.Colors.gold)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .onChange(of: vm.query) { _, _ in vm.onQueryChange() }
                .submitLabel(.search)

            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(CinemaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    searchFocused
                        ? CinemaTheme.Colors.gold.opacity(0.5)
                        : CinemaTheme.Colors.border,
                    lineWidth: 1
                )
                .animation(.easeInOut(duration: 0.2), value: searchFocused)
        )
        .onAppear { searchFocused = true }
    }
}

// MARK: - People Result Row

private struct PeopleResultRow: View {
    let user: CinemaUser
    let isFollowing: Bool
    let isCurrentUser: Bool
    let onTap: () -> Void
    let onFollow: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CinemaTheme.Colors.surface)
                        .frame(width: 46, height: 46)
                        .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))
                    Text((user.displayName ?? user.username).prefix(1).uppercased())
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName ?? user.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }

                Spacer()

                if !isCurrentUser {
                    Button(action: onFollow) {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isFollowing ? CinemaTheme.Colors.textSecondary : .black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isFollowing ? CinemaTheme.Colors.surface : CinemaTheme.Colors.gold)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    isFollowing ? CinemaTheme.Colors.border : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
