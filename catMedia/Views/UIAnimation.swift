import SwiftUI

enum UIAnimation {
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    static let stateChange = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
}

struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(UIAnimation.stateChange, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardButtonStyle {
    static var pressableCard: PressableCardButtonStyle { PressableCardButtonStyle() }
}
