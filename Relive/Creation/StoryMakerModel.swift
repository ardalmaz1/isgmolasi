import Observation
import ReliveCore
import SwiftUI
import UIKit

/// State of a story being made: the cards Relive arranged and the chosen look.
@Observable
@MainActor
final class StoryMakerModel {
    /// Long side of preview images; story cards are tall, so previews need a little more.
    static let previewLongSide: Double = 1800

    let source: CreationSource
    var style: StoryStyle
    private(set) var sequence: StorySequence?
    private(set) var shortfall: CreationShortfall?
    private(set) var previewImages: CanvasImages = [:]
    private(set) var missing: Set<AssetID> = []
    /// The card on screen.
    var currentCardID: Int = 0
    let export = ExportController()

    @ObservationIgnored private let library: CreationLibrary

    init(source: CreationSource, library: CreationLibrary) {
        self.source = source
        self.library = library
        // A real place suits the Travel look; otherwise start quiet.
        let facts = library.facts(for: source, photos: library.initialPhotos(for: source, limit: CreationLimits.story.upperBound))
        self.style = facts.place != nil ? .travel : .minimal
        rebuild()
    }

    var cards: [StoryCardPlan] { sequence?.cards ?? [] }

    var currentCard: StoryCardPlan? {
        cards.first { $0.id == currentCardID } ?? cards.first
    }

    var canExport: Bool { !cards.isEmpty && !export.isBusy }

    var analyticsProperties: [String: String] {
        ["kind": "story", "style": style.rawValue, "cards": String(cards.count)]
    }

    /// Re-arranges the cards, leaving out photos that turned out to be unavailable.
    private func rebuild() {
        switch StorySequenceBuilder(library: library).sequence(for: source, excluding: missing) {
        case .success(let sequence):
            self.sequence = sequence
            shortfall = nil
            if !sequence.cards.contains(where: { $0.id == currentCardID }) {
                currentCardID = sequence.cards.first?.id ?? 0
            }
        case .failure(let shortfall):
            sequence = nil
            self.shortfall = shortfall
        }
    }

    func loadPreviews(using images: CreationImageSource) async {
        var lostAny = false
        for id in sequence?.photoIDs ?? [] where previewImages[id] == nil && !missing.contains(id) {
            guard !Task.isCancelled else { return }
            if let image = await images.previewImage(for: id, longSide: Self.previewLongSide) {
                previewImages[id] = image
            } else if !Task.isCancelled {
                missing.insert(id)
                lostAny = true
            }
        }
        if lostAny {
            // A photo disappeared from the library: arrange the story without it.
            rebuild()
            await loadPreviews(using: images)
        }
    }

    /// High-resolution images of the given cards, in order.
    func renderExport(cardIDs: [Int], using images: CreationImageSource) async throws -> [UIImage] {
        let style = self.style
        var rendered: [UIImage] = []
        for card in cards where cardIDs.contains(card.id) {
            try Task.checkCancellation()
            var loaded: CanvasImages = [:]
            if let id = card.assetID {
                loaded = try await images.exportImages(for: [(id, StoryCardCanvas.size)])
            }
            let canvas = StoryCardCanvas(card: card, style: style, image: card.assetID.flatMap { loaded[$0] }, number: card.id)
            guard let image = CreationRenderer.render(canvas, size: StoryCardCanvas.size) else {
                throw CreationExportError.renderFailed
            }
            rendered.append(image)
        }
        return rendered
    }
}
