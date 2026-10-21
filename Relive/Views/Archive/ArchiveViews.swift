import ReliveCore
import SwiftUI

/// The couple's own archive, reachable from Us (and from Today): every memory, every moment,
/// every place. Always free — Premium is only about what Relive makes from these.
enum ArchiveRoute: Hashable {
    case memories
    case moments
    case places
    case place(String)
    /// A trip's moments (from Today's "A trip to look back on").
    case trip(UUID)
}

extension View {
    /// Registers the archive screens for a navigation stack.
    func archiveDestinations() -> some View {
        navigationDestination(for: ArchiveRoute.self) { route in
            switch route {
            case .memories: MemoriesLibraryView()
            case .moments: MomentsLibraryView()
            case .places: PlacesView()
            case .place(let id): PlaceDetailView(placeID: id)
            case .trip(let id): TripDetailView(tripID: id)
            }
        }
    }
}

// MARK: - Memories

/// Every memory, newest month first, as a lazy grid of small thumbnails (each loaded at its cell
/// size, so a thousand memories scroll like a hundred). Tap to look; touch and hold to favorite,
/// open its moment, or ask Relive not to suggest it.
struct MemoriesLibraryView: View {
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var viewer: ArchiveViewerSelection?
    @State private var openMoment: MomentRoute?

    var body: some View {
        let archive = store.archive
        ScrollView {
            if archive.memoryCount == 0 {
                QuietMessageView(title: "No memories yet", message: "Add photos of the two of you and they’ll all be here.")
                    .padding(.top, Spacing.xl)
            } else {
                LazyVGrid(columns: columns, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(archive.months) { group in
                        Section {
                            ForEach(group.assetIDs, id: \.self) { id in
                                if let asset = store.assets[id] {
                                    MemoryCell(asset: asset, onOpen: {
                                        viewer = ArchiveViewerSelection(month: group.id, assetID: id)
                                    }, onOpenMoment: { momentID in
                                        openMoment = MomentRoute(momentID: momentID, source: "archive")
                                    })
                                }
                            }
                        } header: {
                            ArchiveMonthHeader(title: title(group), count: group.assetIDs.count)
                        }
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
        }
        .scrollIndicators(.automatic)
        .reliveBackground()
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $openMoment) { route in
            MomentDetailView(momentID: route.momentID, source: route.source)
        }
        .fullScreenCover(item: $viewer) { selection in
            // One month at a time: the viewer never holds the whole archive.
            let ids = archive.months.first { $0.id == selection.month }?.assetIDs ?? [selection.assetID]
            AssetViewer(assets: ids.compactMap { store.assets[$0] }, startAssetID: selection.assetID)
        }
        .onAppear { analytics.track(.archiveOpened, ["section": "memories", "count": String(archive.memoryCount)]) }
        .accessibilityIdentifier("memoriesLibrary")
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 96), spacing: 2)]
    }

    private func title(_ group: ArchiveIndex.MonthGroup) -> String {
        guard let month = group.month,
              let date = store.calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else { return "Undated" }
        return DateText.monthYear(date)
    }
}

/// Which memory the full-screen viewer opens on, and the month it pages through.
struct ArchiveViewerSelection: Identifiable {
    let month: String
    let assetID: AssetID
    var id: AssetID { assetID }
}

/// "August 2025 · 64", pinned while its month scrolls by.
private struct ArchiveMonthHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typography.title3)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Spacing.s)
            Text(count.formatted())
                .font(Typography.footnote.monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.opacity(0.96))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(Counted.text(count, "memory", "memories"))")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One memory in the grid, with its menu.
private struct MemoryCell: View {
    let asset: MemoryAsset
    let onOpen: () -> Void
    let onOpenMoment: (MomentID) -> Void

    @Environment(StoryStore.self) private var store

    var body: some View {
        let isFavorite = store.isFavorite(.memory, asset.id)
        let notSuggested = store.isNotSuggested(asset.id)
        Button(action: onOpen) {
            PhotoGridCell(asset: asset, isFavorite: isFavorite)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.toggleFavorite(.memory, asset.id) } label: {
                Label(isFavorite ? "Remove from Favorites" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            if let moment = store.archiveMoment(containing: asset.id) {
                Button { onOpenMoment(moment.id) } label: {
                    Label("Open Its Moment", systemImage: "rectangle.stack")
                }
            }
            Divider()
            NotSuggestedToggle(assetID: asset.id)
        }
        .accessibilityActions {
            Button(isFavorite ? "Remove from Favorites" : "Favorite") { store.toggleFavorite(.memory, asset.id) }
            Button(notSuggested ? "Suggest This Memory Again" : "Don’t Suggest This Memory") { store.setNotSuggested(asset.id, !notSuggested) }
        }
        .accessibilityIdentifier("archiveMemory")
    }
}

/// "Don't Suggest This Memory" / "Suggest Again": the memory stays in the story either way.
struct NotSuggestedToggle: View {
    let assetID: AssetID

    @Environment(StoryStore.self) private var store

    var body: some View {
        if store.isNotSuggested(assetID) {
            Button { store.setNotSuggested(assetID, false) } label: {
                Label("Suggest This Memory Again", systemImage: "sparkles")
            }
        } else {
            Button { store.setNotSuggested(assetID, true) } label: {
                Label("Don’t Suggest This Memory", systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - Moments

/// Every moment, newest first: cover, title, dates, how many memories.
struct MomentsLibraryView: View {
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics

    var body: some View {
        let ids = store.archive.momentIDs
        ScrollView {
            if ids.isEmpty {
                QuietMessageView(title: "No moments yet", message: "Relive gathers your photos into moments as your story grows.")
                    .padding(.top, Spacing.xl)
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(ids, id: \.self) { id in
                        if let moment = store.moment(id: id) {
                            NavigationLink(value: MomentRoute(momentID: id, source: "archive")) {
                                ArchiveMomentRow(moment: moment)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("archiveMoment")
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .reliveBackground()
        .navigationTitle("Moments")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { analytics.track(.archiveOpened, ["section": "moments", "count": String(ids.count)]) }
    }
}

/// A moment as one compact row: cover, title, dates, count.
struct ArchiveMomentRow: View {
    let moment: Moment

    @Environment(StoryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s)) : AnyLayout(HStackLayout(spacing: Spacing.m))
        layout {
            Color.clear
                .frame(width: typeSize.isAccessibilitySize ? 120 : Thumb.row.width, height: typeSize.isAccessibilitySize ? 150 : Thumb.row.height)
                .overlay { AssetImageView(assetID: store.heroAssetID(for: moment)) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(moment.title.primary.isEmpty ? "A moment" : moment.title.primary)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                    Text(range)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(Counted.text(store.archiveMemoryCount(of: moment), "memory", "memories"))
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Places

/// The places of the story, most memories first. A location Relive couldn't name is listed
/// as such — never given an invented name.
struct PlacesView: View {
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics

    var body: some View {
        let places = store.archive.places
        ScrollView {
            if places.isEmpty {
                QuietMessageView(title: "No places yet", message: "Photos with a location appear here by place.")
                    .padding(.top, Spacing.xl)
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(places) { place in
                        NavigationLink(value: ArchiveRoute.place(place.id)) {
                            PlaceRow(place: place)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("archivePlace")
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .reliveBackground()
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { analytics.track(.archiveOpened, ["section": "places", "count": String(places.count)]) }
    }
}

extension ArchiveIndex.Place {
    /// "Kaş", or "A place without a name" — Relive never invents one.
    var displayName: String { name?.name ?? "A place without a name" }
}

private struct PlaceRow: View {
    let place: ArchiveIndex.Place

    @Environment(StoryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let cover = place.momentIDs.compactMap(store.moment(id:)).max { store.archiveMemoryCount(of: $0) < store.archiveMemoryCount(of: $1) }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s)) : AnyLayout(HStackLayout(spacing: Spacing.m))
        layout {
            Color.clear
                .frame(width: typeSize.isAccessibilitySize ? 120 : 72, height: typeSize.isAccessibilitySize ? 120 : 72)
                .overlay { AssetImageView(assetID: cover.flatMap(store.heroAssetID(for:))) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(place.displayName)
                    .font(Typography.title3)
                    .foregroundStyle(place.name == nil ? Palette.textSecondary : Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Text("\(Counted.text(place.momentIDs.count, "moment", "moments")) · \(Counted.text(place.memoryCount, "memory", "memories"))")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if let range = DateText.range(start: place.firstDate, end: place.lastDate, includeYear: true) {
                    Text(range)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One place: its moments, oldest first, as in the story.
struct PlaceDetailView: View {
    let placeID: String

    @Environment(StoryStore.self) private var store

    var body: some View {
        if let place = store.archive.place(id: placeID) {
            MomentListView(
                title: place.displayName,
                summary: "\(Counted.text(place.momentIDs.count, "moment", "moments")) · \(Counted.text(place.memoryCount, "memory", "memories"))",
                note: place.name == nil ? "Relive couldn’t find a name for this location." : nil,
                momentIDs: place.momentIDs,
                source: "place"
            )
        } else {
            GoneView(message: "Its moments may have been hidden.")
        }
    }
}

/// A trip's moments, in the order they happened.
struct TripDetailView: View {
    let tripID: UUID

    @Environment(StoryStore.self) private var store

    var body: some View {
        let moments = store.story.chapter(id: tripID)?.momentIDs.filter { id in store.moment(id: id).map(store.isVisible) ?? false } ?? []
        if let chapter = store.story.chapter(id: tripID), !moments.isEmpty {
            let memories = moments.compactMap(store.moment(id:)).reduce(0) { $0 + store.archiveMemoryCount(of: $1) }
            MomentListView(
                title: chapter.title.primary.isEmpty ? "A trip" : chapter.title.primary,
                summary: [DateText.range(start: chapter.startDate, end: chapter.endDate, includeYear: true), "\(Counted.text(moments.count, "moment", "moments")) · \(Counted.text(memories, "memory", "memories"))"].compactMap { $0 }.joined(separator: " · "),
                note: nil,
                momentIDs: moments,
                source: "trip"
            )
        } else {
            GoneView(message: "Its moments may have been hidden.")
        }
    }
}

private struct GoneView: View {
    let message: String

    var body: some View {
        QuietMessageView(title: "This isn’t in your story anymore", message: message)
            .frame(maxHeight: .infinity)
            .reliveBackground()
    }
}

/// Moments as the story shows them, under a short factual summary.
private struct MomentListView: View {
    let title: String
    let summary: String
    let note: String?
    let momentIDs: [MomentID]
    let source: String

    @Environment(StoryStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(summary)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                    if let note {
                        Text(note)
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                ForEach(momentIDs, id: \.self) { id in
                    if let moment = store.moment(id: id) {
                        NavigationLink(value: MomentRoute(momentID: id, source: source)) {
                            MomentCard(moment: moment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .reliveBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

extension StoryStore {
    /// The visible moment holding this memory.
    func archiveMoment(containing id: AssetID) -> Moment? {
        story.moments.first { $0.assetIDs.contains(id) && isVisible($0) }
    }

    /// Memories of a moment as the archive counts them (available, no duplicate copies).
    func archiveMemoryCount(of moment: Moment) -> Int {
        let duplicates = Set(moment.duplicateAssetIDs)
        return moment.assetIDs.filter { isAvailable($0) && !duplicates.contains($0) }.count
    }
}
