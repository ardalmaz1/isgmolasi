import ReliveCore
import SwiftUI

/// "Your partner" in Us: connect, the connection's state, and a way into its settings. Free —
/// connecting is never behind Premium.
///
/// The explanation sheet is attached by `partnerConnectSheet` outside the List: a sheet attached
/// to a section inside a List doesn't present reliably.
struct PartnerSection: View {
    @Environment(PartnerConnectionModel.self) private var partner
    @Environment(AppModel.self) private var app
    @Binding var showsExplanation: Bool

    var body: some View {
        Section {
            content
        } header: {
            Text("Your partner")
        } footer: {
            if partner.state == .notConnected {
                Text("Free. Yuvi works just the same on your own.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var partnerName: String { app.couple?.partnerName ?? "your partner" }

    @ViewBuilder private var content: some View {
        switch partner.state {
        case .notConnected:
            Button("Connect Your Partner") { showsExplanation = true }
                .accessibilityIdentifier("usConnectPartner")
        case .checkingICloud:
            PartnerProgressRow(text: "Checking iCloud…")
        case .creatingRelationship:
            PartnerProgressRow(text: "Getting your invitation ready…")
        case .joining:
            PartnerProgressRow(text: "Joining…")
        case .disconnecting:
            PartnerProgressRow(text: "Disconnecting…")
        case .iCloudUnavailable(let message):
            PartnerMessageRow(message: message, showsSettings: true)
        case .ended(let message), .failed(let message):
            PartnerMessageRow(message: message, showsSettings: false)
        case .waitingForPartner(let isOffline):
            NavigationLink {
                PartnerSettingsView()
            } label: {
                PartnerStatusLabel(title: "Invitation sent", detail: isOffline ? "Offline for now" : "Waiting for \(partnerName) to accept")
            }
            .accessibilityIdentifier("usPartnerStatus")
            Button("Send Invitation") { Task { await partner.presentInvitation() } }
                .disabled(isOffline)
                .accessibilityIdentifier("usSendInvitation")
        case .connected(_, let isOffline):
            NavigationLink {
                PartnerSettingsView()
            } label: {
                PartnerStatusLabel(title: "Connected with \(partnerName)", detail: isOffline ? "Still connected · offline for now" : nil)
            }
            .accessibilityIdentifier("usPartnerStatus")
        }
    }
}

private struct PartnerStatusLabel: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typography.body)
            if let detail {
                Text(detail)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

private struct PartnerProgressRow: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            ProgressView()
            Text(text)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PartnerMessageRow: View {
    @Environment(PartnerConnectionModel.self) private var partner
    let message: PartnerMessage
    let showsSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(message.text)
                .font(Typography.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("usPartnerMessage")
            HStack(spacing: Spacing.m) {
                if showsSettings {
                    Button("Open Settings") { SystemPresenter.openSettings() }
                        .buttonStyle(.borderless)
                }
                Button("OK") { partner.acknowledge() }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("usPartnerMessageOK")
            }
            .font(Typography.callout.weight(.semibold))
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// What connecting means, before anything happens. Nothing touches iCloud until Continue.
struct ConnectPartnerView: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Connect your partner")
                            .eyebrowStyle()
                        Text("Yuvi, for the two of you")
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ConnectPoint(icon: "person", text: "Yuvi works fully on your own. Connecting is optional and free.")
                        ConnectPoint(icon: "photo.on.rectangle", text: "Connecting doesn’t upload your photo library.")
                        ConnectPoint(icon: "iphone", text: "What Yuvi learns from your photos stays private on this iPhone.")
                        ConnectPoint(icon: "hand.raised", text: "Only what you choose to share, later and one by one, is shared.")
                        ConnectPoint(icon: "location.slash", text: "No live location. Yuvi never shows where either of you is.")
                    }
                    Text("You’ll send an invitation from your iCloud. Your partner opens it on their iPhone with Yuvi installed.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.l)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Spacing.xs) {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.relivePrimary)
                        .accessibilityIdentifier("connectPartnerContinue")
                    Button("Not Now") { dismiss() }
                        .buttonStyle(.reliveQuiet)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.s)
                .background(Palette.background)
            }
            .reliveBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct ConnectPoint: View {
    let icon: String
    let text: String
    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: icon)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The connection's details and how to end it — honest about who holds what.
struct PartnerSettingsView: View {
    @Environment(PartnerConnectionModel.self) private var partner
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDisconnect = false

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: statusText)
                    .accessibilityIdentifier("partnerSettingsStatus")
                if let synced = partner.lastSyncedAt {
                    LabeledContent("Last checked", value: synced.formatted(.relative(presentation: .named)))
                }
            } footer: {
                if isOffline {
                    Text("Yuvi can’t reach iCloud right now. You’re still connected; it will check again when it can.")
                }
            }
            .listRowBackground(Palette.surface)

            Section("What’s shared") {
                Text("Right now, only the connection itself. Your photo library, what Yuvi learns from it, your hidden memories and your places stay on this iPhone. Sharing a photo or a note will always be something you choose, one at a time.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.vertical, Spacing.xxs)
            }
            .listRowBackground(Palette.surface)

            if partner.record?.role == .owner, partner.record?.status == .waitingForPartner {
                Section {
                    Button("Send Invitation Again") { Task { await partner.presentInvitation() } }
                        .disabled(isOffline)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                Button(endTitle, role: .destructive) { confirmsDisconnect = true }
                    .disabled(partner.state.isBusy || partner.record == nil)
                    .accessibilityIdentifier("partnerDisconnect")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .reliveBackground()
        .navigationTitle("Your Partner")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(endTitle + "?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button(endTitle, role: .destructive) {
                // Back to Us once the connection is gone (see onChange below).
                Task { await partner.disconnect() }
            }
            .accessibilityIdentifier("partnerDisconnectConfirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(endExplanation)
        }
        .onChange(of: partner.record == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private var partnerName: String { app.couple?.partnerName ?? "your partner" }
    private var possessiveName: String { app.couple.map { "\($0.partnerName)’s" } ?? "your partner’s" }

    private var isOffline: Bool {
        switch partner.state {
        case .waitingForPartner(let offline), .connected(_, let offline): offline
        default: false
        }
    }

    private var statusText: String {
        guard let record = partner.record else { return "Not connected" }
        switch record.status {
        case .waitingForPartner: return "Invitation sent"
        case .connected: return "Connected"
        }
    }

    private var endTitle: String {
        guard let record = partner.record else { return "Disconnect" }
        switch (record.role, record.status) {
        case (.owner, .waitingForPartner): return "Cancel Invitation"
        case (.owner, .connected): return "Disconnect Partner"
        case (.partner, _): return "Leave Connection"
        }
    }

    private var endExplanation: String {
        guard let record = partner.record else { return "" }
        switch (record.role, record.status) {
        case (.owner, .waitingForPartner):
            return "The invitation stops working. Nothing else changes."
        case (.owner, .connected):
            return "Sharing in Yuvi stops for both of you, and \(partnerName) no longer has access to your connection. Your photos and memories on this iPhone don’t change, and Yuvi goes back to just you. Nothing from your library was shared, so there is nothing of yours on their iPhone to remove."
        case (.partner, _):
            return "Sharing in Yuvi stops and you leave the connection. It was started from \(possessiveName) iCloud, so it stays theirs; Yuvi on their iPhone closes it the next time it opens. Your photos and memories on this iPhone don’t change, and Yuvi goes back to just you."
        }
    }
}

extension View {
    /// The "Connect your partner" explanation; Continue starts connecting once it has closed.
    func partnerConnectSheet(isPresented: Binding<Bool>) -> some View {
        modifier(PartnerConnectSheetModifier(isPresented: isPresented))
    }

    /// Shows the partner connection's one-off messages (an invitation accepted, refused or
    /// failed) over whatever is on screen.
    func partnerNotice() -> some View {
        modifier(PartnerNoticeModifier())
    }
}

private struct PartnerConnectSheetModifier: ViewModifier {
    @Environment(PartnerConnectionModel.self) private var partner
    @Binding var isPresented: Bool
    @State private var continueAfterExplanation = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            // Apple's invitation screen appears only once this sheet is gone.
            guard continueAfterExplanation else { return }
            continueAfterExplanation = false
            Task { await partner.connect() }
        }) {
            ConnectPartnerView {
                continueAfterExplanation = true
                isPresented = false
            }
        }
    }
}

private struct PartnerNoticeModifier: ViewModifier {
    @Environment(PartnerConnectionModel.self) private var partner

    func body(content: Content) -> some View {
        content.alert(
            partner.notice == .joined ? "Connected" : "Your partner connection",
            isPresented: Binding(get: { partner.notice != nil }, set: { if !$0 { partner.notice = nil } })
        ) {
            Button("OK") { partner.notice = nil }
        } message: {
            Text(partner.notice?.text ?? "")
        }
    }
}
