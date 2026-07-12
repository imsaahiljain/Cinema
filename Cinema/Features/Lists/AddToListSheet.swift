import SwiftUI
import Supabase

// MARK: - AddToListSheetModel

@Observable
@MainActor
final class AddToListSheetModel {
    let tmdbID: Int
    let mediaType: MediaType
    let userID: UUID?

    var customLists: [CustomList] = []
    var inWatchlist = false
    var inListIDs: Set<UUID> = []
    var isLoading = true

    init(tmdbID: Int, mediaType: MediaType, userID: UUID?) {
        self.tmdbID = tmdbID
        self.mediaType = mediaType
        self.userID = userID
    }

    func load() async {
        guard let userID else { isLoading = false; return }
        async let listsTask: [CustomList] = (try? await SupabaseClient.shared
            .from("custom_lists").select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: true)
            .execute().value) ?? []
        async let watchlistTask: [WatchlistEntry] = (try? await SupabaseClient.shared
            .from("watchlist").select()
            .eq("user_id", value: userID)
            .eq("tmdb_id", value: tmdbID)
            .execute().value) ?? []
        struct Membership: Decodable {
            let listID: UUID
            enum CodingKeys: String, CodingKey { case listID = "list_id" }
        }
        async let membershipTask: [Membership] = (try? await SupabaseClient.shared
            .from("list_items").select("list_id")
            .eq("tmdb_id", value: tmdbID)
            .execute().value) ?? []

        customLists = await listsTask
        inWatchlist = !(await watchlistTask).isEmpty
        inListIDs = Set(await membershipTask.map { $0.listID })
        isLoading = false
    }

    func toggleWatchlist() async {
        guard let userID else { return }
        if inWatchlist {
            try? await SupabaseClient.shared.from("watchlist")
                .delete().eq("user_id", value: userID).eq("tmdb_id", value: tmdbID).execute()
            inWatchlist = false
        } else {
            try? await SupabaseClient.shared.from("watchlist")
                .upsert(["user_id": userID.uuidString, "tmdb_id": String(tmdbID), "media_type": mediaType.rawValue])
                .execute()
            inWatchlist = true
        }
    }

    func toggle(list: CustomList) async {
        if inListIDs.contains(list.id) {
            try? await SupabaseClient.shared.from("list_items")
                .delete().eq("list_id", value: list.id).eq("tmdb_id", value: tmdbID).execute()
            inListIDs.remove(list.id)
        } else {
            try? await SupabaseClient.shared.from("list_items")
                .upsert(["list_id": list.id.uuidString, "tmdb_id": String(tmdbID), "media_type": mediaType.rawValue])
                .execute()
            inListIDs.insert(list.id)
        }
    }

    @discardableResult
    func createList(name: String) async -> CustomList? {
        guard let userID else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let newList = CustomList(id: UUID(), userID: userID, name: trimmed, createdAt: Date())
        do {
            try await SupabaseClient.shared.from("custom_lists")
                .insert(["id": newList.id.uuidString, "user_id": userID.uuidString, "name": trimmed])
                .execute()
            customLists.append(newList)
            return newList
        } catch { return nil }
    }
}

// MARK: - AddToListSheet

/// Bookmark tap in Search opens this instead of silently adding straight to Watchlist —
/// lets you pick Watchlist and/or any of your custom lists, matching how many-list apps
/// (Pinterest boards, etc.) handle "save" instead of assuming there's only one destination.
struct AddToListSheet: View {
    @State private var model: AddToListSheetModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCreateList = false

    init(tmdbID: Int, mediaType: MediaType, userID: UUID?) {
        _model = State(initialValue: AddToListSheetModel(tmdbID: tmdbID, mediaType: mediaType, userID: userID))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaTheme.Colors.background.ignoresSafeArea()

                if model.isLoading {
                    ProgressView().tint(CinemaTheme.Colors.gold)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            listRow(title: "Watchlist", icon: "bookmark", isOn: model.inWatchlist) {
                                Task { await model.toggleWatchlist() }
                            }
                            Divider().background(CinemaTheme.Colors.border).padding(.leading, 52)

                            ForEach(model.customLists) { list in
                                listRow(title: list.name, icon: "list.bullet", isOn: model.inListIDs.contains(list.id)) {
                                    Task { await model.toggle(list: list) }
                                }
                                Divider().background(CinemaTheme.Colors.border).padding(.leading, 52)
                            }

                            Button {
                                showCreateList = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(CinemaTheme.Colors.gold)
                                        .frame(width: 24)
                                    Text("New List")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CinemaTheme.Colors.gold)
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showCreateList) {
            CreateListSheet { name in
                if let list = await model.createList(name: name) {
                    await model.toggle(list: list)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func listRow(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? CinemaTheme.Colors.gold : CinemaTheme.Colors.textSecondary.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
