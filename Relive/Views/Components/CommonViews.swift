import SwiftUI

/// A thin horizontal rule.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Centered message for empty or unavailable states.
struct QuietMessageView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.s) {
            Text(title)
                .font(Typography.title2)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.reliveOutline)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// Small floating confirmation with an optional action ("Hidden · Undo").
struct ToastView: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.onPrimary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.onPrimary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(Palette.textPrimary, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Banner shown when Relive can no longer see some or all of the chosen photos.
struct AccessBanner: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(message)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textPrimary)
                Button(actionTitle, action: action)
                    .font(Typography.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
