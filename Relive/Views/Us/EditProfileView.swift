import ReliveCore
import SwiftUI

/// Edit names and the start date. No relationship labels, ever.
struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var partnerName = ""
    @State private var userName = ""
    @State private var date = RelationshipDateDraft()

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
                }
                Section {
                    RelationshipDatePicker(draft: $date)
                } header: {
                    Text("When your story began")
                } footer: {
                    Text("An estimate is perfectly fine.")
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
                        .disabled(partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            partnerName = app.relationship?.partnerName ?? ""
            userName = app.relationship?.userName ?? ""
            if let start = app.relationship?.start {
                date = RelationshipDateDraft(start: start)
            }
        }
    }

    private var previewName: String {
        RelationshipProfile(partnerName: partnerName, userName: userName).coupleDisplayName
    }

    private func save() {
        app.setPartnerName(partnerName)
        app.setUserName(userName)
        app.setRelationshipStart(date.start)
        dismiss()
    }
}
