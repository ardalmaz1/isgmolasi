import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ReliveMark()
                .padding(.top, Spacing.xl)
            Spacer()
            Text("You already have a beautiful story.")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Let’s find it.")
                .font(Typography.title2)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Spacer()
            Button("Find Our Story") {
                app.beginOnboarding()
            }
            .buttonStyle(.relivePrimary)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.m)
        .reliveBackground()
    }
}
