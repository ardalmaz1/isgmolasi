import ReliveCore
import SwiftUI

/// A small picture of a kept collage, story or book, drawn again from its state — never a
/// stored image. Photos are loaded as small thumbnails (shared, bounded cache), never full size.
/// Photos that can't be shown appear as quiet placeholders; nothing is put in their place.
struct CreationPreview: View {
    let item: KeptPreviewItem

    var body: some View {
        switch item {
        case .creation(let creation):
            SavedCreationPreview(creation: creation)
        case .book(let book):
            BookPreview(book: book)
        }
    }
}

/// What a preview draws: a collage or story (finished or draft), or a book.
enum KeptPreviewItem: Hashable {
    case creation(SavedCreation)
    case book(MemoryBook)

    init(_ item: KeptItem) {
        switch item {
        case .creation(let creation): self = .creation(creation)
        case .book(let book): self = .book(book)
        }
    }
}

/// Long side of preview thumbnails, in pixels: sharp on a card, cheap to decode.
private let previewLongSide: Double = 360

private struct SavedCreationPreview: View {
    let creation: SavedCreation

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @State private var images: CanvasImages = [:]

    var body: some View {
        let library = store.creationLibrary(for: creation)
        let missing = Set(creation.missingPhotos(in: library))
        Group {
            switch creation.kind {
            case .collage:
                if let state = creation.collage {
                    collage(state, library: library, missing: missing)
                }
            case .story:
                if let design = creation.story?.design, let card = design.cards.first {
                    let aspects = card.photos.map { library.assets[$0]?.aspectRatio ?? 0.75 }
                    ScaledCanvas(designSize: StoryCardCanvas.size) {
                        StoryCardCanvas(card: card, style: design.style, images: images, missing: missing, aspects: aspects, number: 1, showsWatermark: false)
                    }
                }
            }
        }
        .task(id: PreviewKey(id: creation.id, photos: previewPhotos)) {
            await load(previewPhotos, missing: missing)
        }
    }

    private func collage(_ state: CollageState, library: CreationLibrary, missing: Set<AssetID>) -> some View {
        let facts = creation.facts(in: library)
        let caption = CollageEditorModel.caption(facts: facts, showsTitle: state.showsTitle, showsDate: state.showsDate, showsPlace: state.showsPlace)
        let aspects = state.photoIDs.map { library.assets[$0]?.aspectRatio ?? 1 }
        let layout = CollageLayoutEngine().layout(photoAspects: aspects, style: state.style, canvas: state.aspectRatio.designSize, caption: CollageEditorModel.captionSpec(caption))
        return ScaledCanvas(designSize: layout.canvas) {
            CollageCanvas(layout: layout, photoIDs: state.photoIDs, images: images, missing: missing, caption: caption, showsWatermark: false)
        }
    }

    /// The photos the preview shows: a collage's photos, a story's first card.
    private var previewPhotos: [AssetID] {
        switch creation.kind {
        case .collage: creation.collage?.photoIDs ?? []
        case .story: creation.story?.design.cards.first?.photos ?? []
        }
    }

    private func load(_ ids: [AssetID], missing: Set<AssetID>) async {
        let source = CreationImageSource(loader: loader)
        for id in ids where images[id] == nil && !missing.contains(id) {
            guard !Task.isCancelled else { return }
            if let image = await source.previewImage(for: id, longSide: previewLongSide) {
                images[id] = image
            }
        }
    }

    private struct PreviewKey: Hashable {
        let id: UUID
        let photos: [AssetID]
    }
}

private struct BookPreview: View {
    let book: MemoryBook

    @Environment(StoryStore.self) private var store

    var body: some View {
        let library = store.creationLibrary(for: book)
        let cover = book.coverAssetID.flatMap { library.isUsable($0) ? $0 : nil } ?? book.photoIDs.first(where: library.isUsable)
        BookCoverThumbnail(assetID: cover)
            .padding(Spacing.s)
    }
}

/// A kept creation in a library grid or row: its picture, what it is, a factual title (or a
/// neutral one), its period, and whether it is a favorite.
struct CreationCard: View {
    let item: KeptItem
    var width: CGFloat?

    @Environment(StoryStore.self) private var store

    var body: some View {
        let summary = KeptSummary(item: item, store: store)
        let isFavorite = store.isFavorite(.creation, item.favoriteID)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Palette.surface
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay {
                    CreationPreview(item: KeptPreviewItem(item))
                        .padding(Spacing.xs)
                }
                .overlay(alignment: .topTrailing) {
                    if isFavorite { FavoriteMark(onPhoto: false) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
            Text(summary.title)
                .font(Typography.footnote.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary.detail)
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel(isFavorite: isFavorite))
    }
}

/// The words on a creation's card, all derived from its photos (the one metadata rule).
struct KeptSummary {
    let kind: KeptKind
    let title: String
    /// "Collage · 6 photos · August 2025" / "Book · 24 photos · Film".
    let detail: String
    /// Photos that can't be shown now.
    let missingCount: Int

    @MainActor
    init(item: KeptItem, store: StoryStore) {
        kind = item.kind
        switch item {
        case .creation(let creation):
            let library = store.creationLibrary(for: creation)
            let facts = creation.facts(in: library)
            title = CreationText.title(facts.title) ?? item.kind.neutralTitle
            missingCount = creation.missingPhotos(in: library).count
            var parts = [item.kind.name]
            switch creation.kind {
            case .collage: parts.append(Counted.text(creation.photoIDs.count, "photo", "photos"))
            case .story: parts.append(Counted.text(creation.story?.design.cards.count ?? 0, "card", "cards"))
            }
            if let period = CreationText.periodLine(facts.dateSpan), period != title { parts.append(period) }
            detail = parts.joined(separator: " · ")
        case .book(let book):
            let layout = BookLayoutEngine(library: store.creationLibrary(for: book)).layout(book)
            title = CreationText.title(layout.facts.title) ?? CreationText.periodLine(layout.facts.dateSpan) ?? item.kind.neutralTitle
            missingCount = layout.missingAssetIDs.count
            detail = [item.kind.name, Counted.text(layout.photoIDs.count, "photo", "photos"), book.style.displayName].joined(separator: " · ")
        }
    }

    func accessibilityLabel(isFavorite: Bool) -> String {
        var parts = [title, detail]
        if missingCount > 0 { parts.append(Counted.text(missingCount, "photo missing", "photos missing")) }
        if isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }
}

enum EditedText {
    /// "Edited 12 minutes ago".
    static func edited(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let interval = date.timeIntervalSince(now)
        return interval > -60 ? "Edited just now" : "Edited \(formatter.localizedString(for: date, relativeTo: now))"
    }
}
