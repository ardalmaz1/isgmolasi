import ReliveCore
import SwiftUI

/// One recap page. Photos first, one meaningful fact, quiet supporting text. Every page scrolls
/// vertically, so large text and small screens never clip it.
struct RecapPageView: View {
    let page: RecapExperienceView.Page
    let plan: RecapPlan
    let actions: RecapActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                switch page {
                case .premium:
                    premiumPage
                case .chapter(let chapter):
                    chapterView(chapter)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.l)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { appeared = true }
        }
    }

    // MARK: - Chapters

    @ViewBuilder
    private func chapterView(_ chapter: RecapChapter) -> some View {
        switch chapter.kind {
        case .opening:
            if let hero = chapter.hero {
                FramedAssetImage(assetID: hero, aspectRatio: 4 / 5, cornerRadius: Radius.card)
                    .accessibilityHidden(true)
            }
            words(chapter.text, large: true)
        case .visualGrid:
            words(chapter.text, large: false)
            grid(chapter.photos)
        case .places, .timeline, .monthByMonth:
            words(chapter.text, large: false)
            rows(chapter.entries)
        case .numbers:
            words(chapter.text, large: false)
            numbers(chapter.entries)
        case .compactSummary:
            words(chapter.text, large: true)
            grid(chapter.photos)
        case .closing:
            closing(chapter)
        case .firstMemory, .tripHighlight, .placeHighlight, .dayHighlight, .peopleGallery, .favoriteHighlight:
            // Square, so the words and the smaller photos fit above the footer on one screen.
            if let hero = chapter.hero {
                FramedAssetImage(assetID: hero, aspectRatio: 1, cornerRadius: Radius.card)
                    .accessibilityHidden(true)
            }
            words(chapter.text, large: false)
            let others = chapter.photos.filter { $0 != chapter.hero }.prefix(3)
            if !others.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(others), id: \.self) { id in
                        FramedAssetImage(assetID: id, aspectRatio: 1)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    /// Eyebrow, serif title, quiet detail — read as one sentence by VoiceOver.
    private func words(_ text: EditorialText, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let eyebrow = text.eyebrow {
                Text(eyebrow).eyebrowStyle()
            }
            Text(text.title)
                .font(large ? Typography.display : Typography.title)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recapChapterTitle")
            if let detail = text.detail, !detail.isEmpty {
                Text(detail)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func grid(_ photos: [AssetID]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: photos.count <= 4 ? 2 : 3)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(photos, id: \.self) { id in
                FramedAssetImage(assetID: id, aspectRatio: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(photos.count) photos")
    }

    private func rows(_ entries: [RecapChapter.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: Spacing.m) {
                    Color.clear
                        .frame(width: 56, height: 70)
                        .overlay { AssetImageView(assetID: entry.photo) }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(Typography.title3)
                            .foregroundStyle(Palette.textPrimary)
                        if let detail = entry.detail, !detail.isEmpty {
                            Text(detail)
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.s)
                .accessibilityElement(children: .combine)
                if index < entries.count - 1 { Hairline() }
            }
        }
    }

    private func numbers(_ entries: [RecapChapter.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(entry.title)
                        .font(Typography.display.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text(entry.detail ?? "")
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Closing and Premium

    private func closing(_ chapter: RecapChapter) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if let hero = chapter.hero {
                FramedAssetImage(assetID: hero, aspectRatio: 4 / 3, cornerRadius: Radius.card)
                    .accessibilityHidden(true)
            }
            words(chapter.text, large: true)
            VStack(spacing: Spacing.s) {
                Button {
                    actions.share()
                } label: {
                    Label("Share Recap", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.relivePrimary)
                .disabled(actions.export.isBusy)
                .accessibilityIdentifier("recapShareCard")
                HStack(spacing: Spacing.s) {
                    Button("Make Collage") { actions.create(.collage) }
                        .buttonStyle(.reliveOutline)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("recapMakeCollage")
                    Button("Create Story") { actions.create(.story) }
                        .buttonStyle(.reliveOutline)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("recapCreateStory")
                }
                Button("Make a Memory Book") { actions.create(.book) }
                    .buttonStyle(.reliveOutline)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("recapMakeBook")
                ExportStatusView(controller: actions.export)
            }
        }
    }

    private var premiumPage: some View {
        let isYear = plan.period.isYearPeriod
        let remaining = max(0, plan.chapters.count - 1 - (1 + RecapExperienceView.freePreviewChapters))
        return VStack(alignment: .leading, spacing: Spacing.l) {
            if let hero = plan.chapters.dropFirst().compactMap(\.hero).last {
                FramedAssetImage(assetID: hero, aspectRatio: 4 / 3, cornerRadius: Radius.card)
                    .blur(radius: 18)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityHidden(true)
            }
            PremiumTeaser(
                title: "The rest of \(actions.periodName)",
                message: "\(remaining == 1 ? "One more chapter" : "\(remaining) more chapters") — and a card to share — are part of Relive Premium.",
                actionTitle: isYear ? "Relive Your Full Year" : "See the Full Recap",
                identifier: "recapSeeAll",
                action: actions.seeAll
            )
        }
    }
}
