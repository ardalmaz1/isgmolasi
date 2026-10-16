import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ReliveMark()
                .padding(.top, Spacing.xl)
            Spacer()
            Text("Your relationship, told through the photos you already have.")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("On this iPhone. No account. Nothing posted anywhere.")
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
            Button("Find Our Story") {
                app.beginOnboarding()
            }
            .buttonStyle(.relivePrimary)
            .accessibilityIdentifier("onboardingFindStory")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.m)
        .reliveBackground()
    }
}
