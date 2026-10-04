import Observation
import ReliveCore
import SwiftUI
import UIKit

/// State of a story being made. Relive designs the story (`StoryDesigner`); the user can ask for
/// another design ("Make it for me"), pick a style, and make small corrections to a card.
/// Every change is kept by `keeper` (a draft, then a finished story — one record).
@Observable
@MainActor
final class StoryMakerModel {
    /// Long side of preview images; story cards are tall, so previews need a little more.
    static let previewLongSide: Double = 1800

    let source: CreationSource
    private(set) var design: StoryDesign?
    private(set) var shortfall: CreationShortfall?
    private(set) var previewImages: CanvasImages = [:]
    private(set) var missing: Set<AssetID> = []
    /// Shapes measured from loaded images; they win over stored metadata.
    private(set) var measuredAspects: [AssetID: Double] = [:]
    /// The card on screen.
    var currentCardID: Int = 0
    let export = ExportController()
    /// Keeps the story as a draft, then as a finished creation.
    let keeper: CreationKeeper

    @ObservationIgnored private var library: CreationLibrary
    @ObservationIgnored private var variation = 0
    /// Relive's own design, untouched by the user: if a photo disappears it may simply design
    /// the story again. A story the user corrected or reopened is never redesigned behind their
    /// back — its missing photos are shown as missing instead.
    @ObservationIgnored private var isRelivesDesign = true

    /// A new story: Relive designs the first version itself.
    init(source: CreationSource, library: CreationLibrary, store: StoryStore? = nil) {
        self.source = source
        self.library = library
        self.keeper = CreationKeeper(kind: .story, source: source, store: store)
        apply(StoryDesigner(library: library).makeItForMe(source: source, variation: 0, excluding: []))
        startKeeping()
    }

    /// A draft or saved story, reopened exactly as it was: cards, order, layouts, photos, style
    /// and the user's show/hide choices. Photos that can't be shown now are marked missing.
    init(restoring creation: SavedCreation, state: StoryState, library: CreationLibrary, store: StoryStore?) {
        self.source = creation.source
        self.library = library
        self.design = state.design
        self.variation = state.design.variation
        self.missing = Set(creation.missingPhotos(in: library))
        self.currentCardID = state.design.cards.first?.id ?? 0
        self.isRelivesDesign = false
        self.keeper = CreationKeeper(kind: .story, source: creation.source, store: store, existing: creation)
        startKeeping()
    }

    private func startKeeping() {
        keeper.content = { [weak self] in
            guard let design = self?.design else { return nil }
            return .story(StoryState(design: design))
        }
    }

    // MARK: - Keeping

    /// Writes pending changes now (closing, going to the background).
    func flush() {
        keeper.flush()
    }

    /// "Save": the story moves to My Creations.
    func markSaved() {
        keeper.markSaved()
    }

    /// Its cards were saved to Photos or shared: it is finished too.
    func markExported() {
        keeper.markExported()
    }

    /// The design changed: a new image, kept shortly.
    private func noteChange() {
        export.clearMessage()
        keeper.changed()
    }

    var style: StoryStyle { design?.style ?? .minimal }
    var cards: [StoryCard] { design?.cards ?? [] }

    var currentCard: StoryCard? {
        cards.first { $0.id == currentCardID } ?? cards.first
    }

    /// Photos in the story that can't be shown now (deleted, or no longer shared with Relive).
    var missingInStory: [AssetID] {
        (design?.photoIDs ?? []).filter { missing.contains($0) }
    }

    var canExport: Bool { !cards.isEmpty && missingInStory.isEmpty && !export.isBusy }

    var analyticsProperties: [String: String] {
        ["kind": "story", "style": style.rawValue, "cards": String(cards.count), "variation": String(variation)]
    }

    /// The shapes of a card's photos, for its layout.
    func aspects(for card: StoryCard) -> [Double] {
        card.photos.map { measuredAspects[$0] ?? library.assets[$0]?.aspectRatio ?? 0.75 }
    }

    // MARK: - Designing

    /// "Make it for me": another complete design — style, sequence, layouts.
    func makeItForMe() {
        variation += 1
        let designer = StoryDesigner(library: library)
        var result = designer.makeItForMe(source: source, variation: variation, excluding: missing)
        if case .failure = result, let photos = design?.photoIDs.filter({ !missing.contains($0) }), !photos.isEmpty {
            // A reopened story whose source isn't there any more (Start Over, hidden): design
            // it again from its own photos.
            result = designer.makeItForMe(source: .photos(photos), variation: variation, excluding: missing)
        }
        // Never trade a story the user has for nothing.
        guard case .success = result else { return }
        apply(result)
        isRelivesDesign = true
        noteChange()
    }

    /// A different look for the same cards; the user's corrections stay.
    func setStyle(_ style: StoryStyle) {
        guard var design, design.style != style else { return }
        design.style = style
        self.design = design
        isRelivesDesign = false
        noteChange()
    }

    /// Takes photos that are gone out of the story (cards left empty go too). Nothing is put in
    /// their place; the user can replace photos from Edit Card.
    func removeMissingPhotos() {
        let gone = Set(missingInStory)
        guard !gone.isEmpty else { return }
        edit { design in
            design.removingPhotos(gone, library: library)
            return true
        }
        if !cards.contains(where: { $0.id == currentCardID }) { currentCardID = cards.first?.id ?? 0 }
    }

    private func apply(_ result: Result<StoryDesign, CreationShortfall>) {
        switch result {
        case .success(let design):
            self.design = design
            shortfall = nil
            if !design.cards.contains(where: { $0.id == currentCardID }) {
                currentCardID = design.cards.first?.id ?? 0
            }
        case .failure(let shortfall):
            design = nil
            self.shortfall = shortfall
        }
    }

    // MARK: - Small corrections

    func changeLayout(of cardID: Int) {
        edit { $0.cycleLayout(of: cardID) }
    }

    func toggleDate(of cardID: Int) {
        edit { design in update(&design, cardID) { $0.showsDate.toggle() } }
    }

    func togglePlace(of cardID: Int) {
        edit { design in update(&design, cardID) { $0.showsPlace.toggle() } }
    }

    func toggleCoordinates(of cardID: Int) {
        edit { design in update(&design, cardID) { $0.showsCoordinates.toggle() } }
    }

    func removeCard(_ cardID: Int) {
        let library = self.library
        edit { $0.removeCard(cardID, library: library) }
        if !cards.contains(where: { $0.id == currentCardID }) { currentCardID = cards.first?.id ?? 0 }
    }

    /// Puts a photo (from Relive, or picked from the photo library) in one of a card's slots.
    func replacePhoto(cardID: Int, slot: Int, with id: AssetID, photoLibraryAssets: [MemoryAsset] = []) {
        library = library.addingPhotoLibraryAssets(photoLibraryAssets)
        let library = self.library
        edit { $0.replacePhoto(cardID: cardID, slot: slot, with: id, library: library) }
    }

    private func edit(_ change: (inout StoryDesign) -> Bool) {
        guard var design else { return }
        guard change(&design) else { return }
        self.design = design
        isRelivesDesign = false
        noteChange()
    }

    private func update(_ design: inout StoryDesign, _ cardID: Int, _ change: (inout StoryCard) -> Void) -> Bool {
        guard let index = design.cards.firstIndex(where: { $0.id == cardID }) else { return false }
        change(&design.cards[index])
        return true
    }

    // MARK: - Images

    func loadPreviews(using images: CreationImageSource) async {
        var lostAny = false
        for id in design?.photoIDs ?? [] where previewImages[id] == nil && !missing.contains(id) {
            guard !Task.isCancelled else { return }
            if let image = await images.previewImage(for: id, longSide: Self.previewLongSide) {
                previewImages[id] = image
                if image.size.height > 0 { measuredAspects[id] = image.size.width / image.size.height }
            } else if !Task.isCancelled {
                missing.insert(id)
                lostAny = true
            }
        }
        if lostAny, isRelivesDesign, !keeper.exists {
            // A photo disappeared from Relive's own, untouched design: design it again without
            // it. (A story the user corrected or kept shows the missing photo instead.)
            apply(StoryDesigner(library: library).makeItForMe(source: source, variation: variation, excluding: missing))
            await loadPreviews(using: images)
        }
    }

    /// High-resolution images of the given cards, in card order. Each photo is loaded at the
    /// size of its frame on its card.
    func renderExport(cardIDs: [Int], using images: CreationImageSource) async throws -> [UIImage] {
        let style = self.style
        var rendered: [UIImage] = []
        for (index, card) in cards.enumerated() where cardIDs.contains(card.id) {
            try Task.checkCancellation()
            let aspects = aspects(for: card)
            let slots = StoryCardGeometry.slots(for: card, style: style, aspects: aspects)
            let frames = zip(card.photos, slots).map { (id: $0.0, frame: CanvasSize(width: Double($0.1.frame.width), height: Double($0.1.frame.height))) }
            let loaded = try await images.exportImages(for: frames)
            let canvas = StoryCardCanvas(card: card, style: style, images: loaded, aspects: aspects, number: index + 1)
            guard let image = CreationRenderer.render(canvas, size: StoryCardCanvas.size) else {
                throw CreationExportError.renderFailed
            }
            rendered.append(image)
        }
        return rendered
    }
}
