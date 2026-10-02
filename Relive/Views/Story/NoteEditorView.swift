import SwiftUI

/// A private note on a moment. Stored only on this iPhone.
struct NoteEditorView: View {
    let initialText: String
    var prompt = "What do you remember about this?"
    var privacyLine = "Only you can see this. It stays on this iPhone."
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(prompt)
                    .font(Typography.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $text)
                    .font(Typography.bodySerif)
                    .foregroundStyle(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 180)
                    .padding(Spacing.s)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel("Note")

                Label(privacyLine, systemImage: "lock")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)

                Spacer()
            }
            .padding(Spacing.screenMargin)
            .reliveBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = initialText
            isFocused = true
        }
    }
}
