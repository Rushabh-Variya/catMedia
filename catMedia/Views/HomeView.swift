import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack { background
                ScrollView { VStack(alignment: .leading, spacing: 18) { hero; dashboard }
                    .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 28) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ClearCacheToolbarButton()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.03), Color(red: 0.05, green: 0.05, blue: 0.06), Color(red: 0.08, green: 0.08, blue: 0.09)], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .topTrailing) { Circle().fill(Color.white.opacity(0.03)).frame(width: 240, height: 240).blur(radius: 20).offset(x: 120, y: -100) }
            .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Media Converter")
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.top, 6)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashboardHeader
            Divider().overlay(.white.opacity(0.10))
            dashboardRow(title: "Media Info", detail: "Inspect codecs, duration, bitrate, resolution", icon: "info.circle")
            Divider().overlay(.white.opacity(0.08))
            dashboardRow(title: "Conversion", detail: "Smart FFmpeg presets only", icon: "arrow.triangle.2.circlepath")
            Divider().overlay(.white.opacity(0.08))
            dashboardRow(title: "Extraction", detail: "Audio only or video only", icon: "scissors")
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Dashboard")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("3 tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.bottom, 12)
    }

    private func dashboardRow(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.60))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

#Preview {
    HomeView()
}
