import SwiftUI

struct MainTabView: View {
    enum Tab: CaseIterable, Hashable {
        case home
        case mediaInfo
        case conversion
        case extract

        var title: String {
            switch self {
            case .home: "Home"
            case .mediaInfo: "Media Info"
            case .conversion: "Conversion"
            case .extract: "Extract"
            }
        }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .mediaInfo: "info.circle"
            case .conversion: "arrow.triangle.2.circlepath"
            case .extract: "scissors"
            }
        }
    }

    @State private var selectedTab: Tab = .home

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .mediaInfo:
                    MediaInfoView()
                case .conversion:
                    MediaConverterView()
                case .extract:
                    MediaExtractView()
                }
            }
            .id(selectedTab)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .animation(UIAnimation.easeOut, value: selectedTab)
        .preferredColorScheme(.dark)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.subheadline.weight(.semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.48))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color.black)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
    }
}

#Preview {
    MainTabView()
}
