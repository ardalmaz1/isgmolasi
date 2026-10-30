import ReliveCore
import SwiftUI

/// Edit names and the start date. No relationship labels, ever.
struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var partnerName = ""
    @State private var userName = ""
    @State private var date = RelationshipDateDraft()
    /// Off when the couple skipped the date: no date is invented on Save.
    @State private var hasDate = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Your favorite person") {
                    TextField("First name", text: $partnerName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Your first name (optional)", text: $userName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("You")
                } footer: {
                    Text("Used for “\(previewName)”.")
                        .accessibilityLabel("Used for \(previewCouple.spoken()).")
                }
                Section {
                    Toggle("I know when it began", isOn: $hasDate)
                        .accessibilityIdentifier("profileHasStartDate")
                    if hasDate {
                        RelationshipDatePicker(draft: $date)
                    }
                } header: {
                    Text("When your story began")
                } footer: {
                    Text(hasDate
                         ? String(localized: "An estimate is perfectly fine. Memories from before it are shown separately.")
                         : String(localized: "Without a date, Yuvi doesn’t count days together."))
                }
            }
            .scrollContentBackground(.hidden)
            .reliveBackground()
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (hasDate && !date.isComplete))
                }
            }
        }
        .onAppear {
            partnerName = app.relationship?.partnerName ?? ""
            userName = app.relationship?.userName ?? ""
            if let start = app.relationship?.start {
                date = RelationshipDateDraft(start: start)
                hasDate = true
            } else {
                hasDate = false
            }
        }
    }

    private var previewCouple: CoupleName {
        RelationshipProfile(partnerName: partnerName, userName: userName).coupleName
    }

    private var previewName: String {
        previewCouple.display()
    }

    private func save() {
        app.setPartnerName(partnerName)
        app.setUserName(userName)
        if hasDate {
            guard let start = date.start else { return }
            app.setRelationshipStart(start)
        } else {
            app.skipRelationshipStart()
        }
        dismiss()
    }
}
