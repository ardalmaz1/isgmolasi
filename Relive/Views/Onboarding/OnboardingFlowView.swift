import SwiftUI

/// Welcome → Partner → Start date → Photos → Processing → Reveal.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            Group {
                switch app.onboardingStep {
                case .welcome: WelcomeView()
                case .partner: PartnerNameView()
                case .startDate: RelationshipDateView()
                case .photos: PhotoSelectionView()
                case .processing: OnboardingProcessingView()
                case .reveal: StoryRevealView()
                }
            }
            .id(app.onboardingStep)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 20)),
                removal: .opacity
            ))
        }
        .animation(.easeInOut(duration: 0.35), value: app.onboardingStep)
    }
}

/// Shared layout: optional back button, scrolling content, pinned footer.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    var onBack: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 44, height: 44, alignment: .leading)
                    }
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
            .frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: Spacing.xs) {
                footer
            }
            .padding(.top, Spacing.s)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.m)
        .reliveBackground()
    }
}

/// Two overlapping rings: the app's quiet mark.
struct ReliveMark: View {
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -size * 0.46) {
            Circle().stroke(Palette.textPrimary, lineWidth: size * 0.07)
            Circle().stroke(Palette.textPrimary, lineWidth: size * 0.07)
        }
        .frame(width: size * 1.54, height: size)
        .accessibilityHidden(true)
    }
}
