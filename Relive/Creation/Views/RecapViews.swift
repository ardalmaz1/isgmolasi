import ReliveCore
import SwiftUI
import UIKit

// MARK: - Monthly Recap

/// Every month with memories, newest first.
struct MonthlyRecapListView: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        let library = store.creationLibrary
        let builder = MonthlyRecapBuilder(library: library)
        let index = TemporalIndex(library: library)
        let recaps = index.months.map { builder.recap(for: $0, index: index) }

        Group {
            if recaps.isEmpty {
                QuietMessageView(title: "No months yet", message: "Your recaps will appear here as your story grows.")
            } else {
                List(recaps, id: \.month) { recap in
                    NavigationLink(value: CreateRoute.month(recap.month)) {
                        PeriodRow(
                            title: CreationText.monthTitle(recap.month),
                            detail: recap.isSufficient ? CreationText.counts(recap.statistics) : "Just a few memories",
                            coverID: recap.highlights(limit: 1).first
                        )
                    }
                    .listRowBackground(Palette.background)
                    .accessibilityIdentifier("recapMonthRow")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .reliveBackground()
        .navigationTitle("Monthly Recap")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One month, looked back on: its best photos, its moments and trips, and real counts.
struct MonthlyRecapView: View {
    let month: MonthKey

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(PremiumStore.self) private var premium
    @State private var export = ExportController()
    @State private var gate = PremiumGate()

    var body: some View {
        let recap = MonthlyRecapBuilder(library: store.creationLibrary).recap(for: month)
        // Free: the month's counts, its first highlights and every moment (the archive is never
        // gated). Premium: every highlight, its trips, creating from it, and the shareable card.
        let isFull = premium.hasAccess(to: .fullMonthlyRecap)
        let headline = CreationText.title(.month(month)) ?? CreationText.monthTitle(month)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PeriodHeader(
                    eyebrow: CreationText.monthTitle(month),
                    title: headline,
                    detail: recap.statistics.memoryCount > 0 ? CreationText.counts(recap.statistics, includeTrips: true) : nil
                )

                if !recap.isSufficient {
                    QuietMessageView(
                        title: "Just a few memories this month",
                        message: "There isn’t enough here for a recap yet. When you add more photos from this month, Relive will include them."
                    )
                    if !recap.moments.isEmpty {
                        MomentLinks(moments: recap.moments)
                    }
                } else {
                    PhotoSpread(photoIDs: recap.highlights(limit: isFull ? 5 : 3))

                    if isFull {
                        CreationActions(
                            export: export,
                            actions: [
                                .init(title: "Make a Collage", identifier: "recapCollage") {
                                    app.startCreation(.collage, from: .source(.month(month)), origin: "monthly_recap")
                                },
                                .init(title: "Create a Story", identifier: "recapStory") {
                                    app.startCreation(.story, from: .source(.month(month)), origin: "monthly_recap")
                                },
                            ]
                        )

                        ForEach(recap.chapters) { chapter in
                            TripHeader(chapter: chapter, coverID: tripCover(chapter, in: recap.moments))
                        }
                    } else {
                        PremiumTeaser(
                            title: "See the whole month",
                            message: "The full recap — every highlight, the trips, a collage or story made from this month, and a card to share — is part of Relive Premium.",
                            actionTitle: "See the Full Recap",
                            identifier: "recapUnlock"
                        ) {
                            gate.showPaywall(.monthlyRecap, premium: premium, heroAssetID: recap.highlights(limit: 1).first)
                        }
                        ExportStatusView(controller: export)
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Moments").eyebrowStyle()
                        MomentLinks(moments: recap.moments)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle(CreationText.monthTitle(month))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recap.isSufficient {
                ShareToolbarButton(title: "Share", export: export, identifier: "recapShare") {
                    Task { await share(recap, headline: headline) }
                }
            }
        }
        .premiumPaywall(gate)
        .onAppear { analytics.track(.recapOpened, ["kind": "month", "sufficient": recap.isSufficient ? "true" : "false"]) }
    }

    private func tripCover(_ chapter: Chapter, in moments: [Moment]) -> AssetID? {
        let library = store.creationLibrary
        return moments.first { $0.chapterID == chapter.id }.flatMap(library.lead(of:))
    }

    private func share(_ recap: MonthlyRecap, headline: String) async {
        let library = store.creationLibrary
        let source = CreationImageSource(loader: loader)
        await gate.export(.fullMonthlyRecap, entry: .monthlyRecap, premium: premium, heroAssetID: recap.highlights(limit: 1).first) { succeeded in
            await export.share(name: headline, analytics: analytics, properties: ["kind": "monthly_recap"], onShared: succeeded) {
                let image = try await SummaryCardExport.render(
                    eyebrow: String(month.year),
                    title: headline,
                    counts: CreationText.counts(recap.statistics),
                    photoIDs: recap.highlights(limit: 4),
                    library: library,
                    images: source
                )
                return [image]
            }
        }
    }
}

// MARK: - Our Year

/// Every year with memories, newest first.
struct YearListView: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        let library = store.creationLibrary
        let builder = YearInReviewBuilder(library: library)
        let index = TemporalIndex(library: library)
        let reviews = index.years.map { builder.review(for: $0, index: index) }

        Group {
            if reviews.isEmpty {
                QuietMessageView(title: "No years yet", message: "Your years together will appear here as your story grows.")
            } else {
                List(reviews, id: \.year) { review in
                    NavigationLink(value: CreateRoute.year(review.year)) {
                        PeriodRow(
                            title: review.isSufficient ? "Our \(review.year)" : String(review.year),
                            detail: review.isSufficient ? CreationText.counts(review.statistics, includeTrips: true) : YearText.notYet(review.eligibility),
                            coverID: review.highlights(limit: 1).first
                        )
                    }
                    .listRowBackground(Palette.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .reliveBackground()
        .navigationTitle("Our Year")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A year together, month by month — only what happened, in the order it happened. Shown as a
/// year only when it really is one (memories from at least two months); otherwise an honest
/// "just getting started" with ways to add more.
struct OurYearView: View {
    let year: Int

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(PremiumStore.self) private var premium
    @State private var export = ExportController()
    @State private var gate = PremiumGate()
    @State private var isAddingMemories = false

    var body: some View {
        let library = store.creationLibrary
        let review = YearInReviewBuilder(library: library).review(for: year)
        // Free: the cover, the counts, the first memory and the first month. Premium: every
        // month, the closing, creating from the year, and the shareable card.
        let isFull = premium.hasAccess(to: .fullYearInReview)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PeriodHeader(
                    eyebrow: app.coupleName,
                    title: review.isSufficient ? "Our \(year)" : String(year),
                    detail: review.statistics.memoryCount > 0 ? CreationText.counts(review.statistics, includeTrips: true) : nil
                )

                if !review.isSufficient {
                    notYetAYear(review)
                } else {
                    if let lead = library.best(review.highlights(limit: 12)) {
                        FramedAssetImage(assetID: lead, aspectRatio: 4 / 5)
                            .accessibilityHidden(true)
                    }

                    if isFull {
                        actions(showsStatus: true)
                    }

                    // Literally the earliest memory taken this year, dated by that photo.
                    if let first = review.firstMemory, let moment = review.firstMoment {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("The first memory of \(String(year))").eyebrowStyle()
                            Text("\(moment.title.primary) · \(DateText.range(start: first.date, end: first.date) ?? "")")
                                .font(Typography.title3)
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    // Month by month, in order; months without memories aren't shown.
                    ForEach(isFull ? review.months : Array(review.months.prefix(1))) { section in
                        MonthSection(section: section, coverForTrip: { chapter in
                            section.moments.first { $0.chapterID == chapter.id }.flatMap(library.lead(of:))
                        })
                    }

                    if isFull {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Hairline()
                            Text("And that’s our \(String(year)).")
                                .font(Typography.title)
                                .foregroundStyle(Palette.textPrimary)
                            actions(showsStatus: false)
                        }
                    } else {
                        PremiumTeaser(
                            title: "Your \(String(year)) is ready",
                            message: "See all \(Counted.text(review.months.count, "month", "months")) of \(String(year)) with memories, the closing, a story or collage of the year, and a card to share, with Relive Premium.",
                            actionTitle: "Relive Your Full Year",
                            identifier: "yearUnlock"
                        ) {
                            gate.showPaywall(.ourYear, premium: premium, heroAssetID: library.best(review.highlights(limit: 12)))
                        }
                        ExportStatusView(controller: export)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle(review.isSufficient ? "Our \(String(year))" : String(year))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if review.isSufficient {
                ShareToolbarButton(title: "Share Our Year", export: export, identifier: "yearShare") {
                    Task { await share(review) }
                }
            }
        }
        .premiumPaywall(gate)
        .addMemoriesFlow(isPresented: $isAddingMemories)
        .onAppear { analytics.track(.recapOpened, ["kind": "year", "sufficient": review.isSufficient ? "true" : "false"]) }
    }

    /// Not a year yet: say so plainly, show what there is, and offer ways to add more.
    @ViewBuilder
    private func notYetAYear(_ review: YearInReview) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(YearText.notYetTitle(review.eligibility, year: year))
                .font(Typography.title2)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(YearText.notYetMessage(review.eligibility))
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("yearNotYet")

        VStack(spacing: Spacing.s) {
            Button("Add Memories") { isAddingMemories = true }
                .buttonStyle(.relivePrimary)
                .accessibilityIdentifier("yearAddMemories")
            Button("Build from Photo Library") {
                app.startCreation(.book, from: .choosePhotoLibrary, origin: "our_year")
            }
            .buttonStyle(.reliveOutline)
            .accessibilityHint("Choose photos from several months to make a book of your year")
            .accessibilityIdentifier("yearBuildFromLibrary")
        }

        if !review.moments.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("So far").eyebrowStyle()
                MomentLinks(moments: review.moments)
            }
        }
    }

    private func actions(showsStatus: Bool) -> some View {
        CreationActions(
            export: export,
            actions: [
                .init(title: "Create Story", identifier: "yearStory") {
                    app.startCreation(.story, from: .source(.year(year)), origin: "our_year")
                },
                .init(title: "Make a Collage", identifier: "yearCollage") {
                    app.startCreation(.collage, from: .source(.year(year)), origin: "our_year")
                },
            ],
            showsStatus: showsStatus
        )
    }

    private func share(_ review: YearInReview) async {
        let library = store.creationLibrary
        let source = CreationImageSource(loader: loader)
        await gate.export(.fullYearInReview, entry: .ourYear, premium: premium, heroAssetID: library.best(review.highlights(limit: 12))) { succeeded in
            await export.share(name: "Our \(year)", analytics: analytics, properties: ["kind": "our_year"], onShared: succeeded) {
                let image = try await SummaryCardExport.render(
                    eyebrow: app.relationship?.userName == nil ? nil : app.coupleName,
                    title: "Our \(year)",
                    counts: CreationText.counts(review.statistics, includeTrips: true),
                    photoIDs: review.highlights(limit: 6),
                    library: library,
                    images: source
                )
                return [image]
            }
        }
    }
}

/// Honest words for a year that isn't one yet.
@MainActor
enum YearText {
    static func notYet(_ eligibility: YearEligibility) -> String {
        switch eligibility {
        case .singleMonth(let month): "Just getting started · \(CreationText.monthName(month) ?? "one month") so far"
        case .tooFew: "Just a few memories"
        case .empty, .eligible: "No memories yet"
        }
    }

    static func notYetTitle(_ eligibility: YearEligibility, year: Int) -> String {
        switch eligibility {
        case .singleMonth, .empty, .eligible: "Your \(year) story is just getting started."
        case .tooFew: "Just a few memories from \(year) so far."
        }
    }

    static func notYetMessage(_ eligibility: YearEligibility) -> String {
        switch eligibility {
        case .singleMonth(let month):
            "Everything here is from \(CreationText.monthName(month) ?? "one month"). Add memories from another month to build Our Year."
        case .tooFew:
            "Add a few more memories from this year to build Our Year."
        case .empty, .eligible:
            "Add memories from this year to build Our Year."
        }
    }
}

/// One month inside Our Year.
private struct MonthSection: View {
    let section: YearMonthSection
    let coverForTrip: (Chapter) -> AssetID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Hairline()
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(CreationText.monthName(section.month) ?? CreationText.monthTitle(section.month))
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(Counted.text(section.memoryCount, "memory", "memories"))
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(section.chapters) { chapter in
                TripHeader(chapter: chapter, coverID: coverForTrip(chapter))
            }
            PhotoSpread(photoIDs: section.highlights)
            MomentLinks(moments: section.moments)
        }
    }
}

// MARK: - Shared pieces

/// Eyebrow, large title and an honest count line.
private struct PeriodHeader: View {
    let eyebrow: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(eyebrow).eyebrowStyle()
            Text(title)
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.top, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PeriodRow: View {
    let title: String
    let detail: String
    let coverID: AssetID?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Color.clear
                .frame(width: 60, height: 75)
                .overlay { AssetImageView(assetID: coverID) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One large photo and a row of smaller ones.
private struct PhotoSpread: View {
    let photoIDs: [AssetID]

    var body: some View {
        VStack(spacing: 4) {
            if let first = photoIDs.first {
                FramedAssetImage(assetID: first, aspectRatio: 4 / 3)
            }
            let rest = Array(photoIDs.dropFirst().prefix(4))
            if !rest.isEmpty {
                HStack(spacing: 4) {
                    ForEach(rest, id: \.self) { id in
                        FramedAssetImage(assetID: id, aspectRatio: 1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "A trip · Kaş · August 6 – 9" — only for trips the story actually contains.
private struct TripHeader: View {
    let chapter: Chapter
    let coverID: AssetID?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Color.clear
                .frame(width: 72, height: 90)
                .overlay { AssetImageView(assetID: coverID) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("A trip").eyebrowStyle()
                Text(chapter.title.primary)
                    .font(Typography.title2)
                    .foregroundStyle(Palette.textPrimary)
                if let range = DateText.range(start: chapter.startDate, end: chapter.endDate) {
                    Text(range)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Links to the moments themselves.
private struct MomentLinks: View {
    let moments: [Moment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(moments) { moment in
                NavigationLink(value: MomentRoute(momentID: moment.id, source: "recap")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(moment.title.primary)
                                .font(Typography.body)
                                .foregroundStyle(Palette.textPrimary)
                            if let range = DateText.range(start: moment.startDate, end: moment.endDate) {
                                Text(range)
                                    .font(Typography.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, Spacing.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
    }
}

/// The creation buttons under a recap.
struct CreationActions: View {
    struct Action {
        let title: String
        let identifier: String
        let perform: () -> Void

        init(title: String, identifier: String, perform: @escaping () -> Void) {
            self.title = title
            self.identifier = identifier
            self.perform = perform
        }
    }

    let export: ExportController
    let actions: [Action]
    var showsStatus = true

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ForEach(actions, id: \.title) { action in
                    Button(action.title, action: action.perform)
                        .buttonStyle(.reliveOutline)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(action.identifier)
                }
            }
            if showsStatus {
                ExportStatusView(controller: export)
            }
        }
    }
}

/// Share in the navigation bar, where the tab bar can never cover it.
struct ShareToolbarButton: ToolbarContent {
    let title: String
    let export: ExportController
    let identifier: String
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: action) {
                Label(title, systemImage: "square.and.arrow.up")
            }
            .disabled(export.isBusy)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Renders the shareable month or year card.
@MainActor
enum SummaryCardExport {
    static func render(
        eyebrow: String?,
        title: String,
        counts: String,
        photoIDs: [AssetID],
        library: CreationLibrary,
        images: CreationImageSource
    ) async throws -> UIImage {
        let aspects = photoIDs.map { library.assets[$0]?.aspectRatio ?? 1 }
        let mosaic = SummaryCardCanvas.makeMosaic(aspects: aspects)
        let frames = mosaic.slots.compactMap { slot -> (id: AssetID, frame: CanvasSize)? in
            photoIDs.indices.contains(slot.photoIndex) ? (photoIDs[slot.photoIndex], slot.photoFrame.size) : nil
        }
        let loaded = try await images.exportImages(for: frames)
        let canvas = SummaryCardCanvas(
            eyebrow: eyebrow,
            title: title,
            counts: counts,
            photoIDs: photoIDs,
            images: loaded,
            mosaic: mosaic
        )
        guard let image = CreationRenderer.render(canvas, size: SummaryCardCanvas.size) else {
            throw CreationExportError.renderFailed
        }
        return image
    }
}
