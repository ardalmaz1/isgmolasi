import ReliveCore
import SwiftUI

/// The relationship timeline: Year → (Trip →) Moment, oldest first, photos first.
struct StoryTimelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @State private var path: [MomentRoute] = []
    @State private var isAddingMemories = false
    /// The row at the top of the screen (SwiftUI keeps it current while scrolling); setting it
    /// scrolls there.
    @State private var topRowID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Height of the year control at the current text size (the room the header leaves for it).
    @ScaledMetric(relativeTo: .callout) private var yearControlRoom: CGFloat = 28
    @Namespace private var yearRotor

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                timeline
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
    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                StoryHeader()
                    // Room for the year control floating over the top of the story.
                    .padding(.top, store.sections.count > 1 ? yearControlRoom : 0)
                    .padding(.bottom, Spacing.l)
                banners
                years
                TimelineFooter(isAddingMemories: $isAddingMemories)
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollPosition(id: $topRowID, anchor: .top)
        .scrollIndicators(.hidden)
        .reliveBackground()
        .overlay(alignment: .topTrailing) { yearControl }
        .accessibilityRotor("Years") {
            ForEach(store.sections) { section in
                AccessibilityRotorEntry(Text(section.title), id: Self.anchor(section), in: yearRotor)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if store.accessStatus == .denied || store.accessStatus == .restricted {
            AccessBanner(
                message: "Yuvi can’t see your photos right now, so your story is hidden. Your notes are safe.",
                actionTitle: "Open Settings",
                action: { SystemPresenter.openSettings() }
            )
            .padding(.bottom, Spacing.l)
        } else if !store.unavailableAssetIDs.isEmpty {
            AccessBanner(
                message: "Some photos are no longer available — they may have been deleted or removed from Yuvi’s access.",
                actionTitle: "Choose Photos",
                action: { isAddingMemories = true }
            )
            .padding(.bottom, Spacing.l)
        }

        if store.sections.isEmpty {
            QuietMessageView(
                title: "Nothing here yet",
                message: "Add photos of the two of you and Yuvi will arrange them into your story.",
                actionTitle: "Add Memories",
                action: { isAddingMemories = true }
            )
        }
    }

    /// One row of the timeline: a year heading or an item under it. Rows are the lazy stack's
    /// own identity, so the year control can scroll to a year that hasn't been drawn yet.
    private enum Row: Identifiable {
        case heading(TimelineSection)
        case item(TimelineSection, TimelineItem)

        var id: String {
            switch self {
            case .heading(let section): StoryTimelineView.anchor(section)
            case .item(_, let item): item.id
            }
        }
    }

    private var rows: [Row] {
        store.sections.flatMap { section in [Row.heading(section)] + section.items.map { Row.item(section, $0) } }
    }

    /// Year → (Trip →) Moment.
    private var years: some View {
        ForEach(rows) { row in
            switch row {
            case .heading(let section):
                YearHeader(title: section.title)
                    .accessibilityRotorEntry(id: Self.anchor(section), in: yearRotor)
            case .item(_, let item):
                timelineItem(item)
            }
        }
    }

    @ViewBuilder
    private var yearControl: some View {
        if store.sections.count > 1 {
            YearNavigator(sections: store.sections, current: currentSection) { target in
                jump(to: target)
            }
            .padding(.trailing, Spacing.screenMargin)
            .padding(.top, Spacing.xs)
        }
    }

    /// The year on screen: the year of the row at the top (the first year before scrolling).
    private var currentSection: TimelineSection? {
        guard let topRowID, let row = rows.first(where: { $0.id == topRowID }) else { return store.sections.first }
        switch row {
        case .heading(let section), .item(let section, _): return section
        }
    }

    static func anchor(_ section: TimelineSection) -> String { "year-\(section.id)" }

    private func jump(to target: YearNavigator.Target) {
        let id: String
        switch target {
        case .section(let section):
            id = Self.anchor(section)
            analytics.track(.storyYearJumped, ["target": "year", "years": String(store.sections.count)])
        case .latest:
            guard let last = rows.last else { return }
            id = last.id
            analytics.track(.storyYearJumped, ["target": "latest", "years": String(store.sections.count)])
        }
        let reduceMotion = reduceMotion
        // After the menu has closed: a scroll started while it dismisses can be dropped.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if reduceMotion {
                topRowID = id
            } else {
                withAnimation(.easeInOut(duration: 0.45)) { topRowID = id }
            }
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

/// "Our Story · You ♥ Emma · Together since March 2021 · 24 moments"
private struct StoryHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Our Story")
                .eyebrowStyle()
            CoupleTitle()
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
