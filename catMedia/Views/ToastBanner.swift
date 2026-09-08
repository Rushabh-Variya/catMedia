import SwiftUI

struct ToastBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
        }
        .shadow(color: .black.opacity(shadowOpacity), radius: 14, x: 0, y: 6)
    }

    private var borderOpacity: Double {
        colorScheme == .dark ? 0.25 : 0.5
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.34 : 0.2
    }
}

#Preview {
    ToastBanner(message: "Success. Output stored in /Documents")
        .padding()
}
