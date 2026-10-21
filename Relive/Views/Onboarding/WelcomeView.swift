import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // At the largest sizes everything scrolls together, button included, so no line
                // is ever hidden behind it. Text keeps its full size.
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        intro
                        findStoryButton
                            .padding(.top, Spacing.s)
                    }
                    .padding(.bottom, Spacing.m)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    // Calm and spacious when it fits; scrolls if it doesn't, with the button
                    // always on screen.
                    ViewThatFits(in: .vertical) {
                        intro
                        ScrollView {
                            intro
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    findStoryButton
                }
                .padding(.bottom, Spacing.m)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .reliveBackground()
    }

    private var findStoryButton: some View {
        Button("Find Our Story") {
            app.beginOnboarding()
        }
        .buttonStyle(.relivePrimary)
        .accessibilityIdentifier("onboardingFindStory")
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
