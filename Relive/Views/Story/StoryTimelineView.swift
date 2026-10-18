import ReliveCore
import SwiftUI

/// The relationship timeline: Year → (Trip →) Moment, oldest first, photos first.
struct StoryTimelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @State private var path: [MomentRoute] = []
    @State private var isAddingMemories = false
    /// How many rows of each year are on screen; the earliest year with any is "current".
    @State private var visibleRows: [String: Int] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var yearRotor

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                timeline(proxy: proxy)
                    .statusBarBackdrop()
                    // "Open This Memory" from the first discovery.
                    .onChange(of: app.pendingMomentID, initial: true) { _, id in
                        guard let id else { return }
                        app.pendingMomentID = nil
                        path.append(MomentRoute(momentID: id, source: "first_discovery"))
                    }
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

    /// The scrolling story, with the year control over it.
    private func timeline(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                StoryHeader()
                    // Room for the year control floating over the top of the story.
                    .padding(.top, store.sections.count > 1 ? Spacing.l : 0)
                    .padding(.bottom, Spacing.l)
                banners
                years
                TimelineFooter(isAddingMemories: $isAddingMemories)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .overlay(alignment: .topTrailing) { yearControl(proxy: proxy) }
        .accessibilityRotor("Years") {
            ForEach(store.sections) { section in
                AccessibilityRotorEntry(section.title, id: Self.anchor(section), in: yearRotor)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
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
    }

    /// Year → (Trip →) Moment, each row counted while it is on screen.
    private var years: some View {
        ForEach(store.sections) { section in
            YearHeader(title: section.title)
                .id(Self.anchor(section))
                .accessibilityRotorEntry(id: Self.anchor(section), in: yearRotor)
                .tracksVisibility(of: section.id, in: $visibleRows)
            ForEach(section.items) { item in
                timelineItem(item)
                    .tracksVisibility(of: section.id, in: $visibleRows)
            }
        }
    }

    @ViewBuilder
    private func yearControl(proxy: ScrollViewProxy) -> some View {
        if store.sections.count > 1 {
            YearNavigator(sections: store.sections, current: currentSection) { target in
                jump(to: target, proxy: proxy)
            }
            .padding(.trailing, Spacing.screenMargin)
            .padding(.top, Spacing.xs)
        }
    }

    /// The year on screen: the earliest year with a visible row (the first year before scrolling).
    private var currentSection: TimelineSection? {
        store.sections.first { (visibleRows[$0.id] ?? 0) > 0 } ?? store.sections.first
    }

    static func anchor(_ section: TimelineSection) -> String { "year-\(section.id)" }

    private func jump(to target: YearNavigator.Target, proxy: ScrollViewProxy) {
        func scroll<ID: Hashable>(_ id: ID) {
            if reduceMotion {
                proxy.scrollTo(id, anchor: .top)
            } else {
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(id, anchor: .top) }
            }
        }
        switch target {
        case .section(let section):
            scroll(Self.anchor(section))
            analytics.track(.storyYearJumped, ["target": "year", "years": String(store.sections.count)])
        case .latest:
            guard let last = store.sections.last?.items.last?.moments.last else { return }
            scroll(last.id)
            analytics.track(.storyYearJumped, ["target": "latest", "years": String(store.sections.count)])
        }
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
        .accessibilityIdentifier("momentCard")
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

/// "Our Story · You + Emma · Together since March 2021 · 24 moments"
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

    /// "Together since March 2021 · 24 moments" counts only moments from the start on; without a
    /// start date there is no "together since" claim — "Since your first memory · June 2019".
    private var subtitle: String? {
        var parts: [String] = []
        if let start = app.relationship?.start {
            parts.append("Together since \(DateText.relationshipStart(start))")
        } else if let first = store.firstMemoryDate {
            parts.append("Since your first memory · \(DateText.monthYear(first))")
        }
        let moments = store.sections
            .filter { $0.id != TimelineBuilder.beforeStartID }
            .flatMap(\.items)
            .reduce(0) { $0 + $1.moments.count }
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

/// A compact "2025 ▾" control over the timeline: shows the year on screen and jumps to any
/// year of the story, or to the latest memories. The years come from the story itself.
struct YearNavigator: View {
    enum Target {
        case section(TimelineSection)
        case latest
    }

    let sections: [TimelineSection]
    let current: TimelineSection?
    let onJump: (Target) -> Void

    var body: some View {
        Menu {
            Section("Jump to") {
                ForEach(sections) { section in
                    Button {
                        onJump(.section(section))
                    } label: {
                        if section.id == current?.id {
                            Label(section.title, systemImage: "checkmark")
                        } else {
                            Text(section.title)
                        }
                    }
                }
            }
            Button {
                onJump(.latest)
            } label: {
                Label("Latest Memories", systemImage: "arrow.down.to.line")
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text(current?.title ?? "Years")
                    .font(Typography.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel("Jump to a year")
        .accessibilityValue(current.map { "Showing \($0.title)" } ?? "")
        .accessibilityHint("Lists the years of your story")
        .accessibilityIdentifier("storyYearNavigator")
    }
}

private extension View {
    /// Counts this row in `rows[key]` while it is on screen.
    func tracksVisibility(of key: String, in rows: Binding<[String: Int]>) -> some View {
        onScrollVisibilityChange(threshold: 0.01) { isVisible in
            rows.wrappedValue[key, default: 0] += isVisible ? 1 : -1
            if (rows.wrappedValue[key] ?? 0) <= 0 { rows.wrappedValue[key] = nil }
        }
    }
}
