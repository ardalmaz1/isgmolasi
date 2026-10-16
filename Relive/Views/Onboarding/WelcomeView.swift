import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            // Calm and spacious when it fits; scrolls at the largest text sizes so the button
            // below is always on screen.
            ViewThatFits(in: .vertical) {
                intro
                ScrollView {
                    intro
                }
                .scrollBounceBehavior(.basedOnSize)
            }
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ReliveMark()
                .padding(.top, Spacing.xl)
            Spacer(minLength: Spacing.l)
            Text("Your relationship, told through the photos you already have.")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("On this iPhone. No account. Nothing posted anywhere.")
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.l)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
