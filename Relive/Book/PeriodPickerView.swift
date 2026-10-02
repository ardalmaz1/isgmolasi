import ReliveCore
import SwiftUI

/// Choose a trip, a month or a year to make something from. Only periods the story actually has
/// are listed; ones with too few photos are shown but can't be chosen.
struct PeriodPickerView: View {
    enum Kind: Hashable {
        case trip
        case month
        case year

        var title: String {
            switch self {
            case .trip: "Choose a Trip"
            case .month: "Choose a Month"
            case .year: "Choose a Year"
            }
        }
    }

    let kind: Kind
    let minimumPhotos: Int
    let onPick: (CreationSource) -> Void
    let onCancel: () -> Void

    @Environment(StoryStore.self) private var store

    private struct Row: Identifiable {
        let id: String
        let source: CreationSource
        let title: String
        let detail: String?
        let coverID: AssetID?
        let photoCount: Int
    }

    var body: some View {
        let rows = self.rows(library: store.creationLibrary)
        Group {
            if rows.isEmpty {
                QuietMessageView(title: emptyTitle, message: "As your story grows, they’ll appear here.")
            } else {
                List(rows) { row in
                    let enough = row.photoCount >= minimumPhotos
                    Button {
                        onPick(row.source)
                    } label: {
                        HStack(spacing: Spacing.m) {
                            Color.clear
                                .frame(width: 60, height: 75)
                                .overlay { AssetImageView(assetID: row.coverID) }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(Typography.title3)
                                    .foregroundStyle(Palette.textPrimary)
                                if let detail = row.detail {
                                    Text(detail)
                                        .font(Typography.footnote)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                Text(enough ? Counted.text(row.photoCount, "photo", "photos") : "Needs at least \(minimumPhotos) photos")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(enough ? 1 : 0.5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enough)
                    .listRowBackground(Palette.background)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("periodPickerRow")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .reliveBackground()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private var emptyTitle: String {
        switch kind {
        case .trip: "No trips yet"
        case .month: "No months yet"
        case .year: "No years yet"
        }
    }

    private func rows(library: CreationLibrary) -> [Row] {
        switch kind {
        case .trip:
            return library.visibleTrips.map { chapter in
                let source = CreationSource.trip(chapter.id)
                return Row(
                    id: chapter.id.uuidString,
                    source: source,
                    title: chapter.title.primary,
                    detail: DateText.range(start: chapter.startDate, end: chapter.endDate, includeYear: true),
                    coverID: library.initialPhotos(for: source, limit: 1).first,
                    photoCount: library.availablePhotos(for: source).count
                )
            }
        case .month:
            let builder = MonthlyRecapBuilder(library: library)
            return builder.availableMonths().map { month in
                let source = CreationSource.month(month)
                return Row(
                    id: "\(month.year)-\(month.month)",
                    source: source,
                    title: CreationText.monthTitle(month),
                    detail: nil,
                    coverID: builder.recap(for: month).highlights(limit: 1).first,
                    photoCount: library.availablePhotos(for: source).count
                )
            }
        case .year:
            let builder = YearInReviewBuilder(library: library)
            return builder.availableYears().map { year in
                let source = CreationSource.year(year)
                return Row(
                    id: String(year),
                    source: source,
                    title: String(year),
                    detail: nil,
                    coverID: builder.review(for: year).highlights(limit: 1).first,
                    photoCount: library.availablePhotos(for: source).count
                )
            }
        }
    }
}
