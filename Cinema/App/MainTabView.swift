import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedMarqueeView()
                .tabItem { Image(systemName: "popcorn.fill").accessibilityLabel("Feed") }
                .tag(0)

            ListsView()
                .tabItem { Image(systemName: "list.number").accessibilityLabel("Lists") }
                .tag(1)

            SearchView()
                .tabItem { Image(systemName: "magnifyingglass").accessibilityLabel("Search") }
                .tag(2)

            DiscoverView()
                .tabItem { Image(systemName: "sparkles").accessibilityLabel("Discover") }
                .tag(3)

            ProfileView()
                .tabItem { Image(systemName: "person.fill").accessibilityLabel("Profile") }
                .tag(4)
        }
        .tint(CinemaTheme.Colors.gold)
    }
}
