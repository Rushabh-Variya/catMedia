import SwiftUI

struct MainTabView: View {
    enum Tab {
        case home
        case mediaInfo
        case conversion
        case extract
    }

    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

            MediaInfoView()
                .tabItem {
                    Label("Media Info", systemImage: "info.circle")
                }
                .tag(Tab.mediaInfo)

            MediaConverterView()
                .tabItem {
                    Label("Conversion", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(Tab.conversion)

            MediaExtractView()
                .tabItem {
                    Label("Extract", systemImage: "scissors")
                }
                .tag(Tab.extract)
        }
            .tint(.white)
            .toolbarColorScheme(.dark, for: .tabBar)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    MainTabView()
}
