import Observation
import ReliveCore
import SwiftUI
import UIKit

/// State of one collage being made: which photos, in what order, how it looks.
///
/// The layout is a pure function of this state (see `CollageLayoutEngine`), so the preview and
/// the export are drawn from exactly the same arrangement. The same state is what a draft or a
/// saved collage keeps (`CollageState`); every change is kept by `keeper` after a short pause.
@Observable
@MainActor
final class CollageEditorModel {
    let source: CreationSource
    let range = CreationLimits.collage

    private(set) var photoIDs: [AssetID] { didSet { noteChange() } }
    var style: CollageStyle = .minimal { didSet { noteChange() } }
    var aspectRatio: CreationAspectRatio = .portrait { didSet { noteChange() } }
    var showsTitle = true { didSet { noteChange() } }
    var showsDate = true { didSet { noteChange() } }
    var showsPlace = true { didSet { noteChange() } }
    /// The photo picked up for swapping (tap one, then another).
    var selectedIndex: Int?

    private(set) var facts: CreationFacts
    private(set) var previewImages: CanvasImages = [:]
    private(set) var missing: Set<AssetID> = []
    /// Shapes measured from loaded images; they win over stored metadata.
    private(set) var measuredAspects: [AssetID: Double] = [:]
    let export = ExportController()
    /// Keeps the collage as a draft, then as a finished creation (one record).
    let keeper: CreationKeeper

    @ObservationIgnored private var library: CreationLibrary
    @ObservationIgnored private var suggestionIndex = 0
    @ObservationIgnored private let engine = CollageLayoutEngine()
    @ObservationIgnored private let designer = CollageAutoDesigner()
    /// Changes are kept only after setup (Relive's first design isn't the user's edit).
    @ObservationIgnored private var tracksChanges = false

    /// A new collage: Relive chooses its first look.
    init(source: CreationSource, photos: [AssetID], library: CreationLibrary, store: StoryStore? = nil) {
        self.source = source
        self.library = library
        let initial = Array(photos.prefix(CreationLimits.collage.upperBound))
        self.photoIDs = initial
        self.facts = library.facts(for: source, photos: initial)
        self.keeper = CreationKeeper(kind: .collage, source: source, store: store)
        makeItForMe()
        startKeeping()
    }

    /// A draft or saved collage, reopened exactly as it was. Photos that can't be shown now are
    /// marked missing; nothing is swapped in for them.
    init(restoring creation: SavedCreation, state: CollageState, library: CreationLibrary, store: StoryStore?) {
        self.source = creation.source
        self.library = library
        self.photoIDs = state.photoIDs
        self.style = state.style
        self.aspectRatio = state.aspectRatio
        self.showsTitle = state.showsTitle
        self.showsDate = state.showsDate
        self.showsPlace = state.showsPlace
        self.facts = creation.facts(in: library)
        self.missing = Set(creation.missingPhotos(in: library))
        self.keeper = CreationKeeper(kind: .collage, source: creation.source, store: store, existing: creation)
        startKeeping()
    }

    private func startKeeping() {
        keeper.content = { [weak self] in
            guard let self else { return nil }
            return .collage(self.state)
        }
        tracksChanges = true
    }

    /// What a draft or saved collage keeps.
    var state: CollageState {
        CollageState(photoIDs: photoIDs, style: style, aspectRatio: aspectRatio, showsTitle: showsTitle, showsDate: showsDate, showsPlace: showsPlace)
    }

    /// Any change makes a different image (it can be saved again) and is kept shortly.
    private func noteChange() {
        guard tracksChanges else { return }
        export.clearMessage()
        keeper.changed()
    }

    // MARK: - Keeping

    /// Writes pending changes now (closing, going to the background).
    func flush() {
        keeper.flush()
    }

    /// "Save": the collage moves to My Creations.
    func markSaved() {
        keeper.markSaved()
    }

    /// Its image was saved to Photos or shared: it is finished too.
    func markExported() {
        keeper.markExported()
    }

    /// Photos picked from the photo library become usable here, described by their own
    /// metadata. They are not added to the story.
    func addPhotoLibraryAssets(_ assets: [MemoryAsset]) {
        library = library.addingPhotoLibraryAssets(assets)
    }

    // MARK: - Derived

    var aspects: [Double] {
        photoIDs.map { measuredAspects[$0] ?? library.assets[$0]?.aspectRatio ?? 1 }
    }

    var titleText: String? { CreationText.title(facts.title) }
    var dateText: String? { CreationText.dateLine(facts.dateSpan) }
    var placeText: String? { CreationText.place(facts.place) }

    var hasTitle: Bool { titleText != nil }
    var hasDate: Bool { dateText != nil }
    var hasPlace: Bool { placeText != nil }

    var caption: CaptionContent {
        Self.caption(facts: facts, showsTitle: showsTitle, showsDate: showsDate, showsPlace: showsPlace)
    }

    var captionSpec: CollageCaptionSpec {
        Self.captionSpec(caption)
    }

    var layout: CollageLayout {
        engine.layout(photoAspects: aspects, style: style, canvas: aspectRatio.designSize, caption: captionSpec)
    }

    /// The caption a collage shows: the facts its photos support, as the user chose to show
    /// them. Shared with previews of saved collages, so they always match the editor.
    static func caption(facts: CreationFacts, showsTitle: Bool, showsDate: Bool, showsPlace: Bool) -> CaptionContent {
        let title = showsTitle ? CreationText.title(facts.title) : nil
        var detail: [String] = []
        if showsDate, let dateText = CreationText.dateLine(facts.dateSpan) { detail.append(dateText) }
        // The place is already the title when they're the same name.
        if showsPlace, let placeText = CreationText.place(facts.place), placeText != title { detail.append(placeText) }
        return CaptionContent(title: title, detail: detail.isEmpty ? nil : detail.joined(separator: " · "))
    }

    static func captionSpec(_ caption: CaptionContent) -> CollageCaptionSpec {
        CollageCaptionSpec(showsTitle: caption.title != nil, showsDetail: caption.detail != nil)
    }

    var missingInCollage: [AssetID] {
        photoIDs.filter { missing.contains($0) }
    }

    var canExport: Bool {
        range.contains(photoIDs.count) && missingInCollage.isEmpty && !export.isBusy
    }

    /// Just saved, and nothing has changed since: saving again would only make a duplicate.
    var isSaved: Bool {
        if case .finished = export.phase { return true }
        return false
    }

    var analyticsProperties: [String: String] {
        ["kind": "collage", "style": style.rawValue, "shape": aspectRatio.label, "photos": String(photoIDs.count)]
    }

    // MARK: - Make it for me

    /// Chooses a style, a shape and an order. Pressing again offers the next-best distinct look.
    func makeItForMe() {
        let infos = photoIDs.map { id in
            CollagePhotoInfo(
                id: id,
                aspectRatio: measuredAspects[id] ?? library.assets[id]?.aspectRatio ?? 1,
                quality: library.quality(id),
                date: library.assets[id]?.creationDate
            )
        }
        let suggestions = designer.distinctSuggestions(for: infos, caption: captionSpec)
        guard !suggestions.isEmpty else { return }
        let suggestion = suggestions[suggestionIndex % suggestions.count]
        suggestionIndex += 1
        style = suggestion.style
        aspectRatio = suggestion.aspectRatio
        photoIDs = suggestion.order
        selectedIndex = nil
    }

    // MARK: - Arranging

    /// Tap one photo, then another, to swap them. Tapping the same photo again lets go.
    func tapPhoto(at index: Int) {
        guard photoIDs.indices.contains(index) else { return }
        if let selected = selectedIndex {
            if selected != index { photoIDs.swapAt(selected, index) }
            selectedIndex = nil
        } else {
            selectedIndex = index
        }
    }

    /// Touch and hold a photo, drag it onto another: it takes that place and the photos between
    /// shift over to make room (the layout is worked out again for the new order).
    func movePhoto(_ id: AssetID, toPositionOf target: AssetID) {
        guard id != target, let from = photoIDs.firstIndex(of: id), let to = photoIDs.firstIndex(of: target) else { return }
        var reordered = photoIDs
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        photoIDs = reordered
        selectedIndex = nil
    }

    func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard photoIDs.indices.contains(index), photoIDs.indices.contains(target) else { return }
        photoIDs.swapAt(index, target)
        selectedIndex = nil
    }

    func replacePhoto(at index: Int, with id: AssetID) {
        guard photoIDs.indices.contains(index), !photoIDs.contains(id) else { return }
        photoIDs[index] = id
        selectedIndex = nil
        refreshFacts()
    }

    func removePhoto(at index: Int) {
        guard photoIDs.indices.contains(index), photoIDs.count > range.lowerBound else { return }
        photoIDs.remove(at: index)
        selectedIndex = nil
        refreshFacts()
    }

    /// After editing the selection: photos still chosen keep their places, new ones join the end.
    func setPhotos(_ ids: [AssetID]) {
        let chosen = Set(ids)
        var updated = photoIDs.filter { chosen.contains($0) }
        updated += ids.filter { !updated.contains($0) }
        photoIDs = Array(updated.prefix(range.upperBound))
        selectedIndex = nil
        refreshFacts()
    }

    private func refreshFacts() {
        facts = library.facts(for: source, photos: photoIDs.filter(library.isUsable))
    }

    // MARK: - Images

    /// Loads preview images for photos that don't have one yet. Photos that can't be loaded
    /// (deleted, access removed) are marked missing rather than failing the collage.
    func loadPreviews(using images: CreationImageSource) async {
        for id in photoIDs where previewImages[id] == nil && !missing.contains(id) {
            guard !Task.isCancelled else { return }
            if let image = await images.previewImage(for: id) {
                previewImages[id] = image
                if image.size.height > 0 {
                    measuredAspects[id] = image.size.width / image.size.height
                }
            } else if !Task.isCancelled {
                missing.insert(id)
            }
        }
    }

    /// The final, high-resolution collage.
    func renderExport(using images: CreationImageSource) async throws -> UIImage {
        let layout = self.layout
        let ids = photoIDs
        let caption = self.caption
        let frames = layout.slots.compactMap { slot -> (id: AssetID, frame: CanvasSize)? in
            ids.indices.contains(slot.photoIndex) ? (ids[slot.photoIndex], slot.photoFrame.size) : nil
        }
        let loaded = try await images.exportImages(for: frames)
        let canvas = CollageCanvas(layout: layout, photoIDs: ids, images: loaded, caption: caption)
        guard let image = CreationRenderer.render(canvas, size: layout.canvas) else {
            throw CreationExportError.renderFailed
        }
        return image
    }
}
