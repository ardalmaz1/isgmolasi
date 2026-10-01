import ReliveCore
import SwiftUI
import UIKit

// MARK: - Monthly Recap

/// Every month with memories, newest first.
struct MonthlyRecapListView: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        let builder = MonthlyRecapBuilder(library: store.creationLibrary)
        let recaps = builder.availableMonths().map(builder.recap(for:))

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
    @State private var export = ExportController()

    var body: some View {
        let recap = MonthlyRecapBuilder(library: store.creationLibrary).recap(for: month)
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
                    PhotoSpread(photoIDs: recap.highlights(limit: 5))

                    CreationActions(
                        export: export,
                        actions: [
                            .init(title: "Make a Collage", identifier: "recapCollage") {
                                app.startCreation(.collage, from: .source(.month(month)), origin: "monthly_recap")
                            },
                            .init(title: "Create a Story", identifier: "recapStory") {
                                app.startCreation(.story, from: .source(.month(month)), origin: "monthly_recap")
                            },
                        ],
                        shareTitle: "Share",
                        onShare: { Task { await share(recap, headline: headline) } }
                    )

                    ForEach(recap.chapters) { chapter in
                        TripHeader(chapter: chapter, coverID: tripCover(chapter, in: recap.moments))
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
        .onAppear { analytics.track(.recapOpened, ["kind": "month", "sufficient": recap.isSufficient ? "true" : "false"]) }
    }

    private func tripCover(_ chapter: Chapter, in moments: [Moment]) -> AssetID? {
        let library = store.creationLibrary
        return moments.first { $0.chapterID == chapter.id }.flatMap(library.lead(of:))
    }

    private func share(_ recap: MonthlyRecap, headline: String) async {
        let library = store.creationLibrary
        let source = CreationImageSource(loader: loader)
        await export.share(name: headline, analytics: analytics, properties: ["kind": "monthly_recap"]) {
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

// MARK: - Our Year

/// Every year with memories, newest first.
struct YearListView: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        let builder = YearInReviewBuilder(library: store.creationLibrary)
        let reviews = builder.availableYears().map(builder.review(for:))

        Group {
            if reviews.isEmpty {
                QuietMessageView(title: "No years yet", message: "Your years together will appear here as your story grows.")
            } else {
                List(reviews, id: \.year) { review in
                    NavigationLink(value: CreateRoute.year(review.year)) {
                        PeriodRow(
                            title: "Our \(review.year)",
                            detail: review.isSufficient ? CreationText.counts(review.statistics, includeTrips: true) : "Just a few memories",
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

/// A year together, month by month — only what happened, in the order it happened.
struct OurYearView: View {
    let year: Int

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @State private var export = ExportController()

    var body: some View {
        let library = store.creationLibrary
        let review = YearInReviewBuilder(library: library).review(for: year)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PeriodHeader(
                    eyebrow: app.coupleName,
                    title: "Our \(year)",
                    detail: review.statistics.memoryCount > 0 ? CreationText.counts(review.statistics, includeTrips: true) : nil
                )

                if !review.isSufficient {
                    QuietMessageView(
                        title: "Just a few memories from \(String(year))",
                        message: "There isn’t enough here for a look back yet. As you add photos from this year, it will fill in."
                    )
                    if !review.moments.isEmpty {
                        MomentLinks(moments: review.moments)
                    }
                } else {
                    if let lead = library.best(review.highlights(limit: 12)) {
                        FramedAssetImage(assetID: lead, aspectRatio: 4 / 5)
                            .accessibilityHidden(true)
                    }

                    actions(review)

                    if let first = review.firstMoment, let date = first.startDate {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("The first memory of \(String(year))").eyebrowStyle()
                            Text("\(first.title.primary) · \(DateText.range(start: date, end: date) ?? "")")
                                .font(Typography.title3)
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    ForEach(review.months) { section in
                        MonthSection(section: section, coverForTrip: { chapter in
                            section.moments.first { $0.chapterID == chapter.id }.flatMap(library.lead(of:))
                        })
                    }

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Hairline()
                        Text("And that’s our \(String(year)).")
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                        actions(review)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle("Our \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { analytics.track(.recapOpened, ["kind": "year", "sufficient": review.isSufficient ? "true" : "false"]) }
    }

    private func actions(_ review: YearInReview) -> some View {
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
            shareTitle: "Share Our Year",
            onShare: { Task { await share(review) } }
        )
    }

    private func share(_ review: YearInReview) async {
        let library = store.creationLibrary
        let source = CreationImageSource(loader: loader)
        await export.share(name: "Our \(year)", analytics: analytics, properties: ["kind": "our_year"]) {
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
    let shareTitle: String
    let onShare: () -> Void

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
            Button {
                onShare()
            } label: {
                Label(shareTitle, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.reliveQuiet)
            .disabled(export.isBusy)
            ExportStatusView(controller: export)
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
