import Observation
import ReliveCore
import SwiftUI
import UIKit

/// State of a story being made. Relive designs the story (`StoryDesigner`); the user can ask for
/// another design ("Make it for me"), pick a style, and make small corrections to a card.
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

    @ObservationIgnored private var library: CreationLibrary
    @ObservationIgnored private var variation = 0

    init(source: CreationSource, library: CreationLibrary) {
        self.source = source
        self.library = library
        // Relive designs the first version itself.
        apply(StoryDesigner(library: library).makeItForMe(source: source, variation: 0, excluding: []))
    }

    var style: StoryStyle { design?.style ?? .minimal }
    var cards: [StoryCard] { design?.cards ?? [] }

    var currentCard: StoryCard? {
        cards.first { $0.id == currentCardID } ?? cards.first
    }

    var canExport: Bool { !cards.isEmpty && !export.isBusy }

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
        apply(StoryDesigner(library: library).makeItForMe(source: source, variation: variation, excluding: missing))
        export.clearMessage()
    }

    /// A different look for the same cards; the user's corrections stay.
    func setStyle(_ style: StoryStyle) {
        guard var design, design.style != style else { return }
        design.style = style
        self.design = design
        export.clearMessage()
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
        edit { $0.removeCard(cardID) }
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
        export.clearMessage()
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
        if lostAny {
            // A photo disappeared from the library: design the story again without it.
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
