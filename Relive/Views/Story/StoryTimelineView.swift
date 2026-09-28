import ReliveCore
import SwiftUI

/// The relationship timeline: Year → (Trip →) Moment, oldest first, photos first.
struct StoryTimelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @State private var path: [MomentRoute] = []
    @State private var isAddingMemories = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        StoryHeader()
                            .padding(.bottom, Spacing.l)

                        if store.accessStatus == .denied || store.accessStatus == .restricted {
                            AccessBanner(
                                message: "Relive can’t see your photos right now, so your story is hidden. Your notes are safe.",
                                actionTitle: "Open Settings",
                                action: { SystemPresenter.openSettings() }
                            )
                            .padding(.bottom, Spacing.l)
                        } else if !store.unavailableAssetIDs.isEmpty {
                            AccessBanner(
                                message: "Some photos are no longer available — they may have been deleted or removed from Relive’s access.",
                                actionTitle: "Choose Photos",
                                action: { isAddingMemories = true }
                            )
                            .padding(.bottom, Spacing.l)
                        }

                        if store.sections.isEmpty {
                            QuietMessageView(
                                title: "Nothing here yet",
                                message: "Add photos of the two of you and Relive will arrange them into your story.",
                                actionTitle: "Add Memories",
                                action: { isAddingMemories = true }
                            )
                        }

                        ForEach(store.sections) { section in
                            YearHeader(title: section.title)
                            ForEach(section.items) { item in
                                timelineItem(item)
                            }
                        }

                        TimelineFooter(isAddingMemories: $isAddingMemories)
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.hidden)
                .reliveBackground()
                .onChange(of: app.storyScrollTarget, initial: true) { _, target in
                    guard let target else { return }
                    path = []
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        app.storyScrollTarget = nil
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .momentDestination()
            .overlay(alignment: .bottom) { hiddenToast }
        }
        .addMemoriesFlow(isPresented: $isAddingMemories)
        .onAppear { analytics.track(.timelineOpened) }
    }

    @ViewBuilder
    private func timelineItem(_ item: TimelineItem) -> some View {
        switch item {
        case .moment(let moment):
            momentLink(moment)
        case .chapter(let chapter, let moments):
            ChapterHeader(chapter: chapter, moments: moments)
            ForEach(moments) { moment in
                momentLink(moment)
            }
        }
    }

    private func momentLink(_ moment: Moment) -> some View {
        NavigationLink(value: MomentRoute(momentID: moment.id, source: "timeline")) {
            MomentCard(moment: moment)
        }
        .buttonStyle(.plain)
        .id(moment.id)
        .padding(.bottom, Spacing.xl)
    }

    @ViewBuilder
    private var hiddenToast: some View {
        if app.recentlyHiddenMomentID != nil {
            ToastView(message: "Memory hidden", actionTitle: "Undo") {
                withAnimation { app.undoHide() }
            }
            .padding(.bottom, Spacing.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { app.recentlyHiddenMomentID = nil }
            }
        }
    }
}

/// "Our Story · You + Emma · Since March 2021"
private struct StoryHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Our Story")
                .eyebrowStyle()
            Text(app.coupleName)
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.top, Spacing.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let start = app.relationship?.start {
            parts.append("Since \(DateText.relationshipStart(start))")
        }
        let moments = store.statistics.momentCount
        if moments > 0 {
            parts.append(Counted.text(moments, "moment", "moments"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A large, quiet year marker.
private struct YearHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Hairline()
            Text(title)
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.l)
    }
}

/// Introduces a trip: "AUGUST 6 – 9 · Kaş · 4 moments · 64 memories".
private struct ChapterHeader: View {
    let chapter: Chapter
    let moments: [Moment]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if let range = DateText.range(start: chapter.startDate, end: chapter.endDate) {
                Text(range)
                    .eyebrowStyle()
            }
            Text(chapter.title.primary)
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            Text(summary)
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.bottom, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var summary: String {
        let memories = moments.reduce(0) { $0 + $1.memoryCount }
        return "\(Counted.text(moments.count, "moment", "moments")) · \(Counted.text(memories, "memory", "memories"))"
    }
}

/// End of the story: the validation question (once), and a way to add more.
private struct TimelineFooter: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Binding var isAddingMemories: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if !store.sections.isEmpty {
                Hairline()
                if let start = app.relationship?.start {
                    Text("Your story began \(start.precision == .day ? "on" : "in") \(DateText.relationshipStart(start)). There’s more of it in your camera roll.")
                        .font(Typography.bodySerif)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if app.shouldAskSmileQuestion {
                SmileQuestionCard()
            }
            if !store.sections.isEmpty {
                Button("Add Memories") { isAddingMemories = true }
                    .buttonStyle(.reliveOutline)
            }
        }
        .padding(.top, Spacing.l)
    }
}
