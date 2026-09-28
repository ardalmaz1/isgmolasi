import SwiftUI

struct PartnerNameView: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        OnboardingScaffold(onBack: { app.advance(to: .welcome) }) {
            Text("Who’s your favorite person?")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextField("Their first name", text: $name)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .onSubmit(save)
                    .accessibilityLabel("Partner’s first name")
                Hairline()
            }
            .padding(.top, Spacing.l)
        } footer: {
            Button("Continue", action: save)
                .buttonStyle(.relivePrimary)
                .disabled(trimmedName.isEmpty)
        }
        .onAppear {
            name = app.relationship?.partnerName ?? ""
            isFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        app.setPartnerName(trimmedName)
        app.advance(to: .startDate)
    }
}
