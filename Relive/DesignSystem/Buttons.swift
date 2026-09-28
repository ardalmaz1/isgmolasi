import SwiftUI

/// Full-width filled button in the primary text color. Used for the one main action per screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundStyle(Palette.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Palette.textPrimary)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet text button for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.callout.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Outlined button used inside cards.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.callout.weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var relivePrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var reliveQuiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var reliveOutline: OutlineButtonStyle { OutlineButtonStyle() }
}
