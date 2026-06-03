import SwiftUI
import Supabase
import PhotosUI
import Contacts
import UserNotifications

// MARK: - Genre Data

struct Genre: Identifiable, Hashable {
    let id: Int
    let name: String
}

let allGenres: [Genre] = [
    Genre(id: 28,    name: "Action"),
    Genre(id: 12,    name: "Adventure"),
    Genre(id: 16,    name: "Animation"),
    Genre(id: 35,    name: "Comedy"),
    Genre(id: 80,    name: "Crime"),
    Genre(id: 99,    name: "Documentary"),
    Genre(id: 18,    name: "Drama"),
    Genre(id: 14,    name: "Fantasy"),
    Genre(id: 27,    name: "Horror"),
    Genre(id: 10402, name: "Musical"),
    Genre(id: 9648,  name: "Mystery"),
    Genre(id: 10749, name: "Romance"),
    Genre(id: 878,   name: "Sci-Fi"),
    Genre(id: 53,    name: "Thriller"),
    Genre(id: 10752, name: "War"),
    Genre(id: 37,    name: "Western"),
]

// MARK: - Seed Films

private let seedMovieIDs = [
    155, 27205, 157336, 680, 278, 238, 603, 769, 550, 329,
    496243, 313369, 76341, 438631, 545611, 361743, 597, 419430, 299534, 324857, 13, 8587,
]

// MARK: - ViewModel

@Observable
@MainActor
final class OnboardingViewModel {
    // Step order: name → username → email → password → photo → genreDislikes → genreLikes
    //             → letterboxd → phone → contacts → notifications → movieWall → complete
    enum Step: Int {
        case name = 0, username, email, password, photo
        case genreDislikes, genreLikes, letterboxd
        case phone, contacts, notifications
        case movieWall, complete
    }

    var step: Step = .name

    // Account data
    var firstName = ""
    var lastName = ""
    var username = ""
    var email = ""
    var password = ""
    var phone = ""
    var selectedPhoto: PhotosPickerItem?
    var profileUIImage: UIImage?

    // Taste data
    var dislikedGenres: Set<Int> = []
    var likedGenres: Set<Int> = []

    // Movie wall
    var wallPair: (MediaItem, MediaItem)?
    var wallSeenIDs: Set<Int> = []
    var wallRankings: [(winner: Int, loser: Int)] = []
    var wallFilms: [MediaItem] = []
    var wallIsLoading = true
    var topFilm: MediaItem?

    var isLoading = false
    var error: String?
    var usernameStatus: UsernameStatus = .idle

    enum UsernameStatus { case idle, checking, available, taken }

    var canContinue: Bool {
        switch step {
        case .name:     return !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case .username: return usernameStatus == .available
        case .email:    return email.contains("@") && email.contains(".")
        case .password: return password.count >= 8
        case .photo:    return profileUIImage != nil
        default:        return true
        }
    }

    func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    func back() {
        guard step.rawValue > 0, let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = prev }
    }

    func checkUsername() async {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 3 else { usernameStatus = .idle; return }
        usernameStatus = .checking
        Log.onboarding.info("checkUsername: checking '@\(trimmed)'")
        do {
            let rows: [CinemaUser] = try await SupabaseClient.shared
                .from("users").select().eq("username", value: trimmed).execute().value
            usernameStatus = rows.isEmpty ? .available : .taken
            Log.onboarding.info("checkUsername: '@\(trimmed)' is \(self.usernameStatus == .available ? "available" : "taken")")
        } catch {
            Log.onboarding.error("checkUsername: error — \(error.localizedDescription)")
            usernameStatus = .available
        }
    }

    // Called from NotificationsStep — creates account then transitions to movie wall
    // Does NOT call appState.checkSession() to avoid RootView re-routing mid-onboarding.
    func createAccount(appState: AppState) async {
        Log.onboarding.info("createAccount: starting signup for \(self.email)")
        isLoading = true
        error = nil
        do {
            let authResponse = try await SupabaseClient.shared.auth.signUp(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            let user = authResponse.user
            let display = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            Log.onboarding.info("createAccount: auth signup OK — uid=\(user.id)")

            try await SupabaseClient.shared
                .from("users")
                .insert([
                    "id": user.id.uuidString,
                    "username": username.lowercased().trimmingCharacters(in: .whitespaces),
                    "display_name": display,
                    "onboarded": "false",
                ])
                .execute()
            Log.onboarding.info("createAccount: user row inserted — proceeding to movie wall")

            // Set auth state manually — avoids calling checkSession which would trigger
            // RootView to swap to OnboardingView(startAtMovieWall:true) mid-flow.
            appState.isAuthenticated = true
            appState.currentUser = CinemaUser(
                id: user.id,
                username: username.lowercased().trimmingCharacters(in: .whitespaces),
                displayName: display,
                avatarURL: nil,
                bio: nil,
                onboarded: false,
                createdAt: Date()
            )

            withAnimation { step = .movieWall }
            await loadWallFilms()
        } catch {
            Log.onboarding.error("createAccount: failed — \(error.localizedDescription)")
            self.error = "Couldn't create account: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadWallFilms() async {
        Log.onboarding.info("loadWallFilms: fetching seed films")
        wallIsLoading = true
        var loaded: [MediaItem] = []
        for id in seedMovieIDs.shuffled() {
            guard loaded.count < 14 else { break }
            if let item = try? await TMDBClient.shared.details(tmdbID: id, mediaType: .movie) {
                loaded.append(item)
            }
        }
        wallFilms = loaded
        wallIsLoading = false
        Log.onboarding.info("loadWallFilms: loaded \(loaded.count) films")
        pickNextWallPair()
    }

    func pickNextWallPair() {
        let unseen = wallFilms.filter { !wallSeenIDs.contains($0.id) }
        if unseen.count >= 2 {
            wallPair = (unseen[0], unseen[1])
        } else if let a = wallFilms.randomElement(),
                  let b = wallFilms.filter({ $0.id != a.id }).randomElement() {
            wallPair = (a, b)
        }
    }

    func wallChoose(winner: MediaItem, loser: MediaItem) {
        wallSeenIDs.insert(winner.id)
        wallSeenIDs.insert(loser.id)
        wallRankings.append((winner: winner.id, loser: loser.id))
        Log.onboarding.info("wallChoose: '\(winner.title)' beat '\(loser.title)' — \(self.wallSeenIDs.count)/10 seen")
        if wallSeenIDs.count >= 10 {
            let wins = Dictionary(wallRankings.map { ($0.winner, 1) }, uniquingKeysWith: +)
            let topID = wins.max(by: { $0.value < $1.value })?.key
            topFilm = wallFilms.first { $0.id == topID } ?? wallFilms.first
            Log.onboarding.info("wallChoose: wall complete — #1 film = '\(self.topFilm?.title ?? "none")'")
        } else {
            pickNextWallPair()
        }
    }

    func completeOnboarding(appState: AppState) async {
        guard let userID = appState.currentUser?.id else { return }
        Log.onboarding.info("completeOnboarding: saving \(self.wallSeenIDs.count) ELO entries for \(userID)")
        isLoading = true
        var elo: [Int: Double] = Dictionary(uniqueKeysWithValues: wallSeenIDs.map { ($0, 1500.0) })
        for m in wallRankings {
            let (w, l) = ELOService.newRatings(winnerRating: elo[m.winner] ?? 1500, loserRating: elo[m.loser] ?? 1500)
            elo[m.winner] = w; elo[m.loser] = l
        }
        for (rank, entry) in elo.sorted(by: { $0.value > $1.value }).enumerated() {
            do {
                try await SupabaseClient.shared
                    .from("ranked_items")
                    .upsert(["user_id": userID.uuidString, "tmdb_id": String(entry.key),
                             "media_type": "movie", "elo_score": String(entry.value),
                             "rank_position": String(rank + 1)])
                    .execute()
            } catch {
                Log.onboarding.error("completeOnboarding: upsert failed for tmdb_id=\(entry.key) — \(error.localizedDescription)")
            }
        }
        Log.onboarding.info("completeOnboarding: all ranked_items upserted — marking complete")
        UserDefaults.standard.set(likedGenres.map(String.init).joined(separator: ","), forKey: "cinema_liked_genres")
        UserDefaults.standard.set(dislikedGenres.map(String.init).joined(separator: ","), forKey: "cinema_disliked_genres")
        await appState.markOnboardingComplete()
        isLoading = false
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = OnboardingViewModel()
    let startAtMovieWall: Bool

    init(startAtMovieWall: Bool = false) {
        self.startAtMovieWall = startAtMovieWall
    }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()
            Group {
                switch vm.step {
                case .name:          NameStep(vm: vm)
                case .username:      UsernameStep(vm: vm)
                case .email:         EmailStep(vm: vm)
                case .password:      PasswordStep(vm: vm)
                case .photo:         PhotoStep(vm: vm)
                case .genreDislikes: GenreStep(vm: vm, isLikes: false)
                case .genreLikes:    GenreStep(vm: vm, isLikes: true)
                case .letterboxd:    LetterboxdStep(vm: vm)
                case .phone:         PhoneStep(vm: vm)
                case .contacts:      ContactsStep(vm: vm)
                case .notifications: NotificationsStep(vm: vm, appState: appState)
                case .movieWall:     MovieWallStep(vm: vm)
                case .complete:      Color.clear
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
        }
        .onAppear {
            if startAtMovieWall {
                vm.step = .movieWall
                Task { await vm.loadWallFilms() }
            }
        }
    }
}

// MARK: - Step Shell

private struct StepShell<Content: View>: View {
    let vm: OnboardingViewModel
    var showBack: Bool = true
    var trailingButton: (() -> Void)? = nil
    var trailingLabel: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if showBack {
                    Button { vm.back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Spacer().frame(width: 44)
                }
                Spacer()
                if let label = trailingLabel, let action = trailingButton {
                    Button(action: action) {
                        Text(label)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    }
                }
            }
            .padding(.top, 12)

            content()

            if let err = vm.error {
                Text(err)
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, CinemaTheme.Spacing.lg)
        .padding(.bottom, 48)
    }
}

// MARK: - Steps

private struct NameStep: View {
    @Bindable var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        StepShell(vm: vm, showBack: false) {
            OnboardingHeader(
                title: "What's your name?",
                subtitle: "This is how other cinephiles (yes, that is an actual word) will see you"
            )
            .padding(.top, 40)

            VStack(spacing: 28) {
                OnboardingTextField("First name", text: $vm.firstName)
                    .focused($focused)
                OnboardingTextField("Last name", text: $vm.lastName)
            }
            .padding(.top, 40)

            Spacer()

            CinemaButton("Continue", enabled: vm.canContinue) { vm.next() }
        }
        .onAppear { focused = true }
    }
}

private struct UsernameStep: View {
    @Bindable var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        StepShell(vm: vm) {
            OnboardingHeader(title: "Your username", subtitle: "How do you want to be known on Cinema?")
                .padding(.top, 40)

            HStack(spacing: 4) {
                Text("@").font(.system(size: 20)).foregroundStyle(CinemaTheme.Colors.textSecondary)
                OnboardingTextField("username", text: $vm.username)
                    .focused($focused)
                    .onChange(of: vm.username) { _, _ in Task { await vm.checkUsername() } }
            }
            .padding(.top, 40)

            HStack(spacing: 6) {
                switch vm.usernameStatus {
                case .checking:
                    ProgressView().scaleEffect(0.7).tint(CinemaTheme.Colors.gold)
                    Text("Checking...").font(.system(size: 13)).foregroundStyle(CinemaTheme.Colors.textSecondary)
                case .available:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Available").font(.system(size: 13)).foregroundStyle(.green)
                case .taken:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Already taken").font(.system(size: 13)).foregroundStyle(.red)
                case .idle:
                    Text("At least 3 characters").font(.system(size: 13)).foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }
            .padding(.top, 12)

            Spacer()
            CinemaButton("Continue", enabled: vm.canContinue) { vm.next() }
        }
        .onAppear { focused = true }
    }
}

private struct EmailStep: View {
    @Bindable var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        StepShell(vm: vm) {
            OnboardingHeader(
                title: "What's your email?",
                subtitle: "Let's make sure you don't lose that great username"
            )
            .padding(.top, 40)

            OnboardingTextField("email@example.com", text: $vm.email, keyboardType: .emailAddress)
                .focused($focused)
                .padding(.top, 40)

            Spacer()
            CinemaButton("Continue", enabled: vm.canContinue) { vm.next() }
        }
        .onAppear { focused = true }
    }
}

private struct PasswordStep: View {
    @Bindable var vm: OnboardingViewModel
    @State private var showPassword = false
    @FocusState private var focused: Bool

    var body: some View {
        StepShell(vm: vm) {
            OnboardingHeader(title: "Create a password", subtitle: "At least 8 characters")
                .padding(.top, 40)

            ZStack(alignment: .trailing) {
                if showPassword {
                    OnboardingTextField("Password", text: $vm.password).focused($focused)
                } else {
                    OnboardingSecureField("Password", text: $vm.password).focused($focused)
                }
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        .padding(.bottom, 12)
                }
            }
            .padding(.top, 40)

            Spacer()
            CinemaButton("Continue", enabled: vm.canContinue) { vm.next() }
        }
        .onAppear { focused = true }
    }
}

@MainActor
private struct PhotoStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav row: back left, Not now right
                HStack {
                    Button { vm.back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Button { vm.next() } label: {
                        Text("Not now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.top, 12)

                Spacer()

                // Photo picker — centered
                // Capture on main actor before passing into the nonisolated ViewBuilder closure
                let pickedImage = vm.profileUIImage
                PhotosPicker(selection: $vm.selectedPhoto, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(CinemaTheme.Colors.surface)
                            .frame(width: 120, height: 120)
                            .overlay(Circle().strokeBorder(CinemaTheme.Colors.border, lineWidth: 1))

                        if let img = pickedImage {
                            Image(uiImage: img)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120).clipShape(Circle())
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(CinemaTheme.Colors.textSecondary)
                        }

                        Circle()
                            .fill(CinemaTheme.Colors.gold)
                            .frame(width: 32, height: 32)
                            .overlay(Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.black))
                            .offset(x: 40, y: 40)
                    }
                }
                .onChange(of: vm.selectedPhoto) { _, item in
                    Task { @MainActor in
                        if let data = try? await item?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            vm.profileUIImage = img
                        }
                    }
                }

                Text("Add your profile photo")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)

                Text("Show off the face behind the taste")
                    .font(.system(size: 16))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .padding(.top, 8)

                Spacer()

                // Continue only enabled once photo chosen
                CinemaButton("Continue", enabled: pickedImage != nil) { vm.next() }
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.bottom, 48)
            }
        }
    }
}

private struct GenreStep: View {
    @Bindable var vm: OnboardingViewModel
    let isLikes: Bool

    var body: some View {
        StepShell(vm: vm, trailingButton: { vm.next() }, trailingLabel: "Skip") {
            OnboardingHeader(
                title: isLikes ? "Genres you love?" : "Any genres you *never* watch?",
                subtitle: isLikes ? "We'll serve these first" : "We'll skip these in your recs"
            )
            .padding(.top, 40)

            ScrollView(showsIndicators: false) {
                FlowLayout(spacing: 10) {
                    ForEach(allGenres) { genre in
                        let sel = isLikes ? vm.likedGenres.contains(genre.id) : vm.dislikedGenres.contains(genre.id)
                        GenreChip(name: genre.name, isSelected: sel) {
                            if isLikes {
                                if vm.likedGenres.contains(genre.id) { vm.likedGenres.remove(genre.id) }
                                else { vm.likedGenres.insert(genre.id) }
                            } else {
                                if vm.dislikedGenres.contains(genre.id) { vm.dislikedGenres.remove(genre.id) }
                                else { vm.dislikedGenres.insert(genre.id) }
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 100)
            }

            Spacer()
            CinemaButton("Continue") { vm.next() }
        }
    }
}

private struct LetterboxdStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        StepShell(vm: vm) {
            Spacer()

            VStack(spacing: 0) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(CinemaTheme.Colors.gold)

                Text("Already on Letterboxd?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Text("Import your history and skip the cold start.\n\nGo to letterboxd.com → Settings → Data → Export Your Data, then share your ratings.csv here.")
                    .font(.system(size: 15))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 16) {
                CinemaButton("Import from Letterboxd") { vm.next() }
                Button { vm.next() } label: {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            }
        }
    }
}

private struct PhoneStep: View {
    @Bindable var vm: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        StepShell(vm: vm) {
            OnboardingHeader(
                title: "What's your number?",
                subtitle: "We'll use this to find friends already on Cinema"
            )
            .padding(.top, 40)

            OnboardingTextField("+1 (555) 000-0000", text: $vm.phone, keyboardType: .phonePad)
                .focused($focused)
                .padding(.top, 40)

            Spacer()
            CinemaButton("Continue") { vm.next() }
        }
        .onAppear { focused = true }
    }
}

private struct ContactsStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { vm.back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 0) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(CinemaTheme.Colors.gold)

                    Text("Find your friends")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 20) {
                        FeatureBullet(icon: "eye.fill",   text: "See what they're ranking")
                        FeatureBullet(icon: "bell.fill",  text: "Know when their #1 changes")
                        FeatureBullet(icon: "arrow.trianglehead.2.clockwise", text: "Settle taste debates")
                    }
                    .padding(.top, 32)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                Spacer()

                CinemaButton("Sync Contacts") {
                    CNContactStore().requestAccess(for: .contacts) { _, _ in
                        DispatchQueue.main.async { vm.next() }
                    }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.bottom, 48)
            }
        }
    }
}

private struct NotificationsStep: View {
    let vm: OnboardingViewModel
    let appState: AppState

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(CinemaTheme.Colors.gold)

                Text("Stay in the loop")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CinemaTheme.Colors.textPrimary)
                    .padding(.top, 24)

                Text("Know when your rankings get challenged, when friends join, and when your taste profile updates.")
                    .font(.system(size: 15))
                    .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)

                if let err = vm.error {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 16) {
                    CinemaButton("Allow Notifications", isLoading: vm.isLoading) {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                            DispatchQueue.main.async {
                                Task { await vm.createAccount(appState: appState) }
                            }
                        }
                    }
                    Button {
                        Task { await vm.createAccount(appState: appState) }
                    } label: {
                        Text("Not now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    }
                    .disabled(vm.isLoading)
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - Movie Wall

struct MovieWallStep: View {
    @Bindable var vm: OnboardingViewModel
    @State private var chosenSide: WallSide?

    enum WallSide { case left, right }

    var body: some View {
        ZStack {
            CinemaTheme.Colors.background.ignoresSafeArea()

            if vm.wallIsLoading {
                VStack(spacing: 20) {
                    ProgressView().tint(CinemaTheme.Colors.gold).scaleEffect(1.5)
                    Text("Loading your first battles...")
                        .font(.system(size: 16))
                        .foregroundStyle(CinemaTheme.Colors.textSecondary)
                }
            } else if vm.wallSeenIDs.count >= 10 {
                WallCompleteView(vm: vm)
            } else if let pair = vm.wallPair {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Which do you prefer?")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(CinemaTheme.Colors.textPrimary)
                        Text("\(min(vm.wallSeenIDs.count, 10)) of 10 films ranked")
                            .font(.system(size: 13))
                            .foregroundStyle(CinemaTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.top, 64)
                    .padding(.bottom, 16)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CinemaTheme.Colors.surface).frame(height: 4)
                            Capsule()
                                .fill(CinemaTheme.Colors.gold)
                                .frame(width: geo.size.width * CGFloat(min(vm.wallSeenIDs.count, 10)) / 10, height: 4)
                                .animation(.spring(duration: 0.5), value: vm.wallSeenIDs.count)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, CinemaTheme.Spacing.lg)
                    .padding(.bottom, 20)

                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            WallPosterSide(item: pair.0, isWinner: chosenSide == .left, isLoser: chosenSide == .right, width: geo.size.width / 2)
                                .onTapGesture { pick(.left, pair: pair) }
                            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                            WallPosterSide(item: pair.1, isWinner: chosenSide == .right, isLoser: chosenSide == .left, width: geo.size.width / 2)
                                .onTapGesture { pick(.right, pair: pair) }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func pick(_ side: WallSide, pair: (MediaItem, MediaItem)) {
        guard chosenSide == nil else { return }
        withAnimation(.spring(duration: 0.35)) { chosenSide = side }
        let winner = side == .left ? pair.0 : pair.1
        let loser  = side == .left ? pair.1 : pair.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            vm.wallChoose(winner: winner, loser: loser)
            withAnimation { chosenSide = nil }
        }
    }
}

private struct WallPosterSide: View {
    let item: MediaItem
    let isWinner: Bool
    let isLoser: Bool
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            PosterImage(path: item.posterPath, cornerRadius: 0)
                .frame(width: width).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 4) {
                if let y = item.releaseYear { Text(y).font(.system(size: 12, weight: .medium)).foregroundStyle(CinemaTheme.Colors.textSecondary) }
                Text(item.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 12)
            }
            .padding(.bottom, 48)
            if isWinner {
                Image(systemName: "hand.thumbsup.fill").font(.system(size: 40)).foregroundStyle(CinemaTheme.Colors.gold)
                    .padding(.bottom, 160).transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: width)
        .scaleEffect(isLoser ? 0.93 : 1.0)
        .opacity(isLoser ? 0.35 : 1.0)
        .animation(.spring(duration: 0.35), value: isWinner)
        .animation(.spring(duration: 0.35), value: isLoser)
    }
}

private struct WallCompleteView: View {
    let vm: OnboardingViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if let top = vm.topFilm {
                PosterImage(path: top.posterPath, cornerRadius: 0).ignoresSafeArea().opacity(0.3)
            }
            LinearGradient(colors: [.clear, CinemaTheme.Colors.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Text("🎬").font(.system(size: 64))
                Text("You're in.").font(.system(size: 44, weight: .bold)).foregroundStyle(CinemaTheme.Colors.textPrimary).padding(.top, 16)
                if let top = vm.topFilm {
                    VStack(spacing: 6) {
                        Text("Your #1 film so far").font(.system(size: 15)).foregroundStyle(CinemaTheme.Colors.textSecondary)
                        Text(top.title).font(.system(size: 22, weight: .bold)).foregroundStyle(CinemaTheme.Colors.gold)
                    }
                    .padding(.top, 20)
                }
                Spacer()
                CinemaButton("See my list", isLoading: vm.isLoading) {
                    Task { await vm.completeOnboarding(appState: appState) }
                }
                .padding(.horizontal, CinemaTheme.Spacing.lg)
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = makeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.maxH).reduce(0, +) + CGFloat(Swift.max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in makeRows(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for sv in row.views {
                let s = sv.sizeThatFits(.unspecified)
                sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.maxH + spacing
        }
    }

    private struct Row { var views: [LayoutSubview] = []; var maxH: CGFloat = 0; var w: CGFloat = 0 }

    private func makeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? 0
        var rows: [Row] = []
        var cur = Row()
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            let needed = cur.w == 0 ? s.width : s.width + spacing
            if cur.w + needed > maxW && !cur.views.isEmpty { rows.append(cur); cur = Row() }
            cur.views.append(sv); cur.w += needed; cur.maxH = Swift.max(cur.maxH, s.height)
        }
        if !cur.views.isEmpty { rows.append(cur) }
        return rows
    }
}

// MARK: - Helpers

private struct FeatureBullet: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(CinemaTheme.Colors.gold).frame(width: 28)
            Text(text).font(.system(size: 16)).foregroundStyle(CinemaTheme.Colors.textPrimary)
        }
    }
}
