import ReliveCore
import SwiftUI

// First Experience V2: choosing how to begin, what discovery does, possible moments.

/// "How would you like to begin?" — Relive finds possible moments, or the couple chooses.
struct ChooseStartView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        OnboardingScaffold(onBack: { app.advance(to: .startDate) }) {
            Text("How would you like to begin?")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Spacing.s) {
                StartChoice(
                    title: "Let Relive find them",
                    message: "Relive looks for possible moments on this iPhone. You decide what to keep.",
                    isRecommended: true,
                    identifier: "startDiscovery"
                ) {
                    app.chooseStartPath(.discovery)
                }
                StartChoice(
                    title: "Choose memories myself",
                    message: "Start with a few photos. You can always add more.",
                    isRecommended: false,
                    identifier: "startManual"
                ) {
                    app.chooseStartPath(.manual)
                }
            }
            .padding(.top, Spacing.m)
        } footer: {
            EmptyView()
        }
    }
}

private struct StartChoice: View {
    let title: String
    let message: String
    let isRecommended: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.title3.weight(isRecommended ? .semibold : .regular))
                        .foregroundStyle(isRecommended ? Palette.background : Palette.textPrimary)
                    Text(message)
                        .font(Typography.callout)
                        .foregroundStyle(isRecommended ? Palette.background.opacity(0.85) : Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isRecommended ? Palette.background : Palette.textSecondary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isRecommended ? Palette.textPrimary : Palette.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// What "Let Relive find them" does, before Apple's Photos permission is asked for.
struct DiscoveryPrivacyView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(DiscoveryModel.self) private var discovery

    var body: some View {
        OnboardingScaffold(onBack: { app.advance(to: .chooseStart) }) {
            Text("Relive looks. You decide.")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.m) {
                PrivacyPoint(icon: "calendar", text: "Dates and places help Relive group photos into possible moments.")
                PrivacyPoint(icon: "person.2", text: "It may count faces in a few photos, but it doesn’t know who anyone is.")
                PrivacyPoint(icon: "iphone", text: "This happens on your iPhone. Your photos aren’t uploaded.")
                PrivacyPoint(icon: "checkmark.circle", text: "You choose which moments belong in your story. Only those are kept.")
                PrivacyPoint(icon: "lock", text: "No feed, no account, nothing posted anywhere.")
            }
            .padding(.top, Spacing.s)

            Text("Next, iOS asks for access to your photos. Allowing full access lets Relive look; you can change this anytime in Settings.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.s)
        } footer: {
            Button("Continue") {
                app.advance(to: .discovering)
                discovery.start(store: store, relationshipStart: app.relationship?.start?.date)
            }
            .buttonStyle(.relivePrimary)
            .accessibilityIdentifier("discoveryContinue")
            Button("Choose memories myself instead") {
                app.chooseStartPath(.manual)
            }
            .buttonStyle(.reliveQuiet)
            .accessibilityIdentifier("discoveryManualInstead")
        }
    }
}

private struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Looking for possible moments, then keeping the ones that are ours.
struct DiscoveringView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(DiscoveryModel.self) private var discovery
    @Environment(\.analytics) private var analytics
    @State private var isImporting = false
    @State private var inspecting: DiscoveryCandidate?

    var body: some View {
        Group {
            switch discovery.phase {
            case .ready:
                candidatesList
            case .idle, .requestingAccess, .scanning, .lookingAtPhotos:
                progress
            case .nothingFound:
                outcome(
                    title: "No moments yet",
                    message: "Relive didn’t find groups of photos to suggest. You can choose a few memories yourself instead."
                )
            case .denied:
                outcome(
                    title: "Relive can’t see your photos",
                    message: "Without access, Relive can’t suggest moments. You can allow access in Settings, or choose a few memories yourself.",
                    settings: true
                )
            case .cancelled:
                outcome(
                    title: "Stopped",
                    message: "Nothing was kept. You can look again, or choose a few memories yourself."
                )
            case .limitedAccess:
                limitedAccess
            }
        }
        .sheet(item: $inspecting) { candidate in
            CandidateDetailView(candidate: candidate)
        }
        .onAppear {
            if discovery.phase == .idle {
                discovery.start(store: store, relationshipStart: app.relationship?.start?.date)
            }
        }
    }

    // MARK: - Looking

    private var progress: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Spacer()
            Text("Looking for possible moments…")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(progressMessage)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .lookingAtPhotos(let done, let total) = discovery.phase, total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(Palette.textPrimary)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Palette.textPrimary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Cancel") {
                discovery.cancel()
            }
            .buttonStyle(.reliveQuiet)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("discoveryCancel")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.m)
        .reliveBackground()
    }

    private var progressMessage: String {
        switch discovery.phase {
        case .requestingAccess: "Waiting for access to your photos…"
        case .lookingAtPhotos(let done, let total): "Looking at a few photos from each moment — \(done) of \(total)"
        default: "Reading dates and places…"
        }
    }

    // MARK: - Possible moments

    private var candidatesList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Possible moments")
                            .eyebrowStyle()
                        Text("We found some moments that might belong in your story.")
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Keep the ones that are yours. Moments you don’t keep aren’t saved.")
                            .font(Typography.callout)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Spacing.l)

                    ForEach(discovery.candidates) { candidate in
                        CandidateMomentCard(
                            candidate: candidate,
                            decision: discovery.decision(for: candidate),
                            onDecide: { discovery.decide(candidate, $0) },
                            onInspect: { inspecting = candidate }
                        )
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.l)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: Spacing.xs) {
                Button(continueTitle) {
                    Task { await keep() }
                }
                .buttonStyle(.relivePrimary)
                .disabled(discovery.keptCount == 0 || isImporting)
                .accessibilityIdentifier("discoveryKeep")
                Button("Choose memories myself instead") {
                    discovery.cancel()
                    app.chooseStartPath(.manual)
                }
                .buttonStyle(.reliveQuiet)
                .accessibilityIdentifier("discoveryManualInstead")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.m)
            .background(Palette.background)
        }
        .reliveBackground()
    }

    private var continueTitle: String {
        let kept = discovery.keptCount
        return kept == 0 ? "Keep a moment to continue" : "Continue with \(Counted.text(kept, "moment", "moments"))"
    }

    private func keep() async {
        isImporting = true
        await discovery.importKept(into: store)
        isImporting = false
        PhotoImageLoader.shared.clearCache()
        guard store.hasSelection else { return }
        app.advance(to: .processing)
    }

    // MARK: - Outcomes

    private func outcome(title: String, message: String, settings: Bool = false) -> some View {
        OnboardingScaffold(onBack: {
            discovery.reset()
            app.advance(to: .chooseStart)
        }) {
            Text(title)
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Typography.title3)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            Button("Choose memories myself") {
                discovery.reset()
                app.chooseStartPath(.manual)
            }
            .buttonStyle(.relivePrimary)
            .accessibilityIdentifier("discoveryChooseManually")
            if settings {
                Button("Open Settings") { SystemPresenter.openSettings() }
                    .buttonStyle(.reliveQuiet)
            } else {
                Button("Look again") {
                    discovery.start(store: store, relationshipStart: app.relationship?.start?.date)
                }
                .buttonStyle(.reliveQuiet)
                .accessibilityIdentifier("discoveryRetry")
            }
        }
    }

    /// The couple chose specific photos in Apple's dialog: those are the story's start.
    private var limitedAccess: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Spacer()
            Text("Using the photos you chose")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
            Spacer()
        }
        .padding(.horizontal, Spacing.screenMargin)
        .reliveBackground()
        .task {
            let change = await store.syncWithAccessibleAssets()
            analytics.track(.manualSelectionCompleted, ["access": "limited", "photos": AnalyticsBucket.count(store.selectionCount)])
            _ = change
            discovery.reset()
            app.chooseStartPath(.manual)
            if store.selectionCount >= PhotoSelectionModel.minimumToBegin {
                app.advance(to: .processing)
            }
        }
    }
}

/// One possible moment: its photos, when, how many — Keep or Not ours.
struct CandidateMomentCard: View {
    let candidate: DiscoveryCandidate
    let decision: DiscoveryModel.Decision?
    let onDecide: (DiscoveryModel.Decision) -> Void
    let onInspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button(action: onInspect) {
                CandidateCover(ids: candidate.representativeIDs)
                    .opacity(decision == .notOurs ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the photos of this moment")
            .accessibilityIdentifier("candidateInspect")

            VStack(alignment: .leading, spacing: 2) {
                Text(CandidateText.when(candidate))
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                Text(CandidateText.summary(candidate))
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: Spacing.s) {
                DecisionButton(title: "Keep", isSelected: decision == .keep, identifier: "candidateKeep") { onDecide(.keep) }
                    .accessibilityLabel("Keep, \(CandidateText.spoken(candidate))")
                DecisionButton(title: "Not ours", isSelected: decision == .notOurs, identifier: "candidateNotOurs") { onDecide(.notOurs) }
                    .accessibilityLabel("Not ours, \(CandidateText.spoken(candidate))")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("candidateMoment")
    }
}

private struct DecisionButton: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(Typography.callout.weight(.semibold))
            .foregroundStyle(isSelected ? Palette.background : Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(isSelected ? Palette.textPrimary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: isSelected ? 0 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Up to three photos side by side, from this iPhone only.
private struct CandidateCover: View {
    let ids: [AssetID]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ids.prefix(3), id: \.self) { id in
                Color.clear
                    .overlay { AssetImageView(assetID: id, localOnly: true) }
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(ids.count >= 3 ? 2.2 : 1.6, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Every photo of a possible moment, to check before keeping it.
struct CandidateDetailView: View {
    let candidate: DiscoveryCandidate
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(CandidateText.summary(candidate))
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                    LazyVGrid(columns: columns, spacing: 3) {
                        // A moment can be large; its first photos are enough to recognise it.
                        ForEach(candidate.assetIDs.prefix(60), id: \.self) { id in
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { AssetImageView(assetID: id, localOnly: true) }
                                .clipped()
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(Spacing.screenMargin)
            }
            .reliveBackground()
            .navigationTitle(CandidateText.when(candidate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Factual words for a possible moment: when, and how many — nothing else.
enum CandidateText {
    static func when(_ candidate: DiscoveryCandidate) -> String {
        DateText.range(start: candidate.start, end: candidate.end, includeYear: true) ?? DateText.monthYear(candidate.start)
    }

    static func summary(_ candidate: DiscoveryCandidate) -> String {
        var parts = [Counted.text(candidate.photoCount, "photo", "photos")]
        if candidate.videoCount > 0 { parts.append(Counted.text(candidate.videoCount, "video", "videos")) }
        let days = candidate.dayCount(calendar: .current)
        if days > 1 { parts.append(Counted.text(days, "day", "days")) }
        return parts.joined(separator: " · ")
    }

    static func spoken(_ candidate: DiscoveryCandidate) -> String {
        "\(when(candidate)), \(summary(candidate).replacingOccurrences(of: " · ", with: ", "))"
    }
}
