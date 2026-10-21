import ReliveCore
import SwiftUI

/// Today: one rediscovered memory, the strongest thing Relive prepared, a way back into the
/// story, and — only when the archive really has them — a couple of factual ways back into it
/// (on this day, a trip, a place they returned to, a recent moment). Never filler.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(MadeForYouStore.self) private var madeForYou
    @Environment(\.analytics) private var analytics
    @State private var path = NavigationPath()
    @State private var isAddingMemories = false
    /// Chosen when Today refreshes (not on every redraw).
    @State private var discoveries: [TodayDiscovery] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(DateText.todayHeader(Date()))
                            .eyebrowStyle()
                        Text("Today")
                            .font(Typography.display)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.top, Spacing.l)

                    if app.shouldAskSmileQuestion {
                        SmileQuestionCard()
                    }

                    if let surprise = app.surpriseMemory {
                        SurpriseMemoryCard(
                            memory: surprise,
                            onOpen: { path.append(SurpriseRoute(momentID: surprise.momentID, assetID: surprise.assetID)) },
                            onDismiss: { withAnimation { app.dismissSurprise() } }
                        )
                    }

                    if let memory = app.foundMemory {
                        FoundForYouCard(memory: memory) {
                            app.openFoundMemory()
                            path.append(MomentRoute(momentID: memory.momentID, source: "found_for_you"))
                        }
                    } else if store.hasStory {
                        QuietMessageView(
                            title: "Nothing to resurface yet",
                            message: "As your story grows older, Relive will bring back memories here."
                        )
                    }

                    // At most one Made for You card, and only a strong one; never the surprise's moment.
                    if !ProcessInfo.processInfo.arguments.contains("-ReliveUITestHideMadeForYou"),
                       let suggestion = madeForYou.todaySuggestion(excluding: app.surpriseMemory?.momentID) {
                        MadeForYouTodayCard(
                            suggestion: suggestion,
                            onOpen: {
                                MadeForYouOpener.open(suggestion, app: app, madeForYou: madeForYou, origin: "made_for_you_today")
                            },
                            onDismiss: { withAnimation { madeForYou.dismiss(suggestion, store: store) } }
                        )
                        .onAppear { madeForYou.recordShown([suggestion]) }
                    }

                    if let next = app.nextMomentToContinue {
                        ContinueStoryCard(moment: next) {
                            app.continueStory()
                        }
                    }

                    if !discoveries.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            ForEach(discoveries, id: \.self) { discovery in
                                TodayDiscoveryCard(discovery: discovery) { kind in
                                    analytics.track(.todayDiscoveryOpened, ["kind": kind])
                                }
                            }
                        }
                    }

                    AddMemoriesCard {
                        isAddingMemories = true
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .reliveBackground()
            .statusBarBackdrop()
            .toolbar(.hidden, for: .navigationBar)
            .momentDestination()
            .archiveDestinations()
            .navigationDestination(for: SurpriseRoute.self) { route in
                SurpriseMemoryView(route: route)
            }
            .navigationDestination(for: CreateRoute.self) { route in
                switch route {
                case .months: MonthlyRecapListView()
                case .month(let month): MonthlyRecapView(month: month)
                case .years: YearListView()
                case .year(let year): OurYearView(year: year)
                case .trend(let id): TrendDetailView(trendID: id)
                }
            }
        }
        .addMemoriesFlow(isPresented: $isAddingMemories)
        .onAppear { refreshResurfacing() }
        .onChange(of: store.story.generatedAt) { _, _ in refreshResurfacing() }
        .onChange(of: store.archive) { _, _ in refreshDiscoveries() }
    }

    /// Found for You first, so the occasional Surprise never repeats its moment.
    private func refreshResurfacing() {
        app.refreshFoundMemory()
        app.refreshSurprise()
        madeForYou.refresh(from: store)
        refreshDiscoveries()
    }

    /// Up to two discoveries that don't repeat a moment already on Today.
    private func refreshDiscoveries() {
        var shown = Set<MomentID>()
        if let id = app.foundMemory?.momentID { shown.insert(id) }
        if let id = app.surpriseMemory?.momentID { shown.insert(id) }
        if let id = app.nextMomentToContinue?.id { shown.insert(id) }
        if let suggestion = madeForYou.todaySuggestion(excluding: app.surpriseMemory?.momentID) {
            switch suggestion.source {
            case .moment(let id): shown.insert(id)
            case .trip(let id): shown.formUnion(store.story.chapter(id: id)?.momentIDs ?? [])
            default: break
            }
        }
        let next = TodayPlanner(calendar: store.calendar).discoveries(
            story: store.story,
            visibleMoments: store.visibleMoments,
            places: store.archive.places,
            excluding: shown,
            isRestingFromSurfacing: { store.userState(for: $0).isExcludedFromSurfacing },
            now: Date()
        )
        if next != discoveries { discoveries = next }
    }
}

/// One way back into the archive: a small cover, a factual eyebrow and title. Opens the moment,
/// trip or place — never a paywall.
struct TodayDiscoveryCard: View {
    let discovery: TodayDiscovery
    let onOpen: (String) -> Void

    @Environment(StoryStore.self) private var store

    var body: some View {
        if let content {
            Group {
                switch content.route {
                case .moment(let route): NavigationLink(value: route) { card(content) }
                case .archive(let route): NavigationLink(value: route) { card(content) }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { onOpen(content.kind) })
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("todayDiscovery")
        }
    }

    private func card(_ content: Content) -> some View {
        HStack(spacing: Spacing.m) {
            Color.clear
                .frame(width: Thumb.feature.width, height: Thumb.feature.height)
                .overlay { AssetImageView(assetID: content.cover) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(content.eyebrow)
                    .eyebrowStyle()
                Text(content.title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                if let detail = content.detail {
                    Text(detail)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Where it opens: a moment, or an archive screen.
    private enum Route {
        case moment(MomentRoute)
        case archive(ArchiveRoute)
    }

    private struct Content {
        var kind: String
        var eyebrow: String
        var title: String
        var detail: String?
        var cover: AssetID?
        var route: Route
    }

    private var content: Content? {
        switch discovery {
        case .onThisDay(let id, let years):
            guard let moment = store.moment(id: id) else { return nil }
            let age = years == 1 ? "A year ago" : "\(years) years ago"
            let eyebrow = [age, moment.place?.name].compactMap { $0 }.joined(separator: " · ")
            return Content(kind: "on_this_day", eyebrow: eyebrow, title: title(moment), detail: dates(moment.startDate, moment.endDate), cover: store.heroAssetID(for: moment), route: .moment(MomentRoute(momentID: id, source: "today_on_this_day")))
        case .trip(let id):
            guard let chapter = store.story.chapter(id: id) else { return nil }
            let moments = chapter.momentIDs.compactMap(store.moment(id:)).filter(store.isVisible)
            guard let first = moments.first else { return nil }
            let memories = moments.reduce(0) { $0 + store.archiveMemoryCount(of: $1) }
            let detail = [dates(chapter.startDate, chapter.endDate), "\(Counted.text(moments.count, "moment", "moments")) · \(Counted.text(memories, "memory", "memories"))"].compactMap { $0 }.joined(separator: "\n")
            return Content(kind: "trip", eyebrow: "A trip to look back on", title: chapter.title.primary.isEmpty ? "A trip" : chapter.title.primary, detail: detail, cover: store.heroAssetID(for: first), route: .archive(.trip(id)))
        case .returnedPlace(let placeID):
            guard let place = store.archive.place(id: placeID), let name = place.name?.name else { return nil }
            let cover = place.momentIDs.last.flatMap(store.moment(id:)).flatMap(store.heroAssetID(for:))
            let detail = "\(Counted.text(place.momentIDs.count, "moment", "moments")) in \(Counted.text(place.monthCount, "different month", "different months"))"
            return Content(kind: "returned_place", eyebrow: "A place you returned to", title: name, detail: detail, cover: cover, route: .archive(.place(placeID)))
        case .recentMoment(let id):
            guard let moment = store.moment(id: id) else { return nil }
            return Content(kind: "recent", eyebrow: "Recently", title: title(moment), detail: dates(moment.startDate, moment.endDate), cover: store.heroAssetID(for: moment), route: .moment(MomentRoute(momentID: id, source: "today_recent")))
        }
    }

    private func title(_ moment: Moment) -> String {
        moment.title.primary.isEmpty ? "A moment" : moment.title.primary
    }

    private func dates(_ start: Date?, _ end: Date?) -> String? {
        DateText.range(start: start, end: end, includeYear: true)
    }
}


/// "Found for you ❤️" — the photo carries the emotion; the words stay out of the way.
struct FoundForYouCard: View {
    let memory: FoundMemory
    let onOpen: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Found for you ❤️")
                    .eyebrowStyle()
                Spacer()
                Menu {
                    Button {
                        withAnimation { app.dontShowFoundMemoryAgain() }
                    } label: {
                        Label("Don’t Show This Again", systemImage: "eye.slash")
                    }
                    Button {
                        store.setNotSuggested(memory.assetID, true)
                        withAnimation { app.refreshFoundMemory() }
                    } label: {
                        Label("Don’t Suggest This Photo", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 44, height: 32, alignment: .trailing)
                }
                .accessibilityLabel("Options")
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FramedAssetImage(assetID: memory.assetID, aspectRatio: 4 / 5)
                    Text(caption)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Found for you: \(caption)")
            .accessibilityHint("Opens the memory")
        }
    }

    /// "2 years ago · Kaş"
    private var caption: String {
        [memory.ageDescription, memory.place?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Picks the story up where the user left it.
struct ContinueStoryCard: View {
    let moment: Moment
    let onContinue: () -> Void

    @Environment(StoryStore.self) private var store

    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: Spacing.m) {
                Color.clear
                    .frame(width: Thumb.feature.width, height: Thumb.feature.height)
                    .overlay { AssetImageView(assetID: store.heroAssetID(for: moment)) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Continue your story")
                        .eyebrowStyle()
                    Text(moment.title.primary)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                        Text(range)
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.m)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct AddMemoriesCard: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Found more photos of the two of you?")
                .font(Typography.title3)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Add them and Relive will place them in your story.")
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
            Button("Add Memories", action: onAdd)
                .buttonStyle(.reliveOutline)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Prototype 0.1's key validation signal. Asked once, answered once.
struct SmileQuestionCard: View {
    @Environment(AppModel.self) private var app
    @State private var answered: SmileResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let answered {
                Text(answered == .yes ? "That’s what it’s for. Thank you." : "Thank you. There’s more to find as your story grows.")
                    .font(Typography.bodySerif)
                    .foregroundStyle(Palette.textPrimary)
            } else {
                Text("Did you find something that made you smile?")
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s) {
                    Button("Yes") { answer(.yes) }
                        .buttonStyle(.relivePrimary)
                    Button("Not yet") { answer(.notYet) }
                        .buttonStyle(.reliveOutline)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func answer(_ response: SmileResponse) {
        withAnimation(.easeInOut(duration: 0.3)) {
            answered = response
        }
        // Record after the thank-you is visible, so the card doesn't vanish mid-tap.
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { app.answerSmileQuestion(response) }
        }
    }
}
