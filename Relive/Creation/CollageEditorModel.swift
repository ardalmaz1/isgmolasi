import Observation
import ReliveCore
import SwiftUI
import UIKit

/// State of one collage being made: which photos, in what order, how it looks.
///
/// The layout is a pure function of this state (see `CollageLayoutEngine`), so the preview and
/// the export are drawn from exactly the same arrangement.
@Observable
@MainActor
final class CollageEditorModel {
    let source: CreationSource
    let range = CreationLimits.collage

    private(set) var photoIDs: [AssetID]
    var style: CollageStyle = .minimal
    var aspectRatio: CreationAspectRatio = .portrait
    var showsTitle = true
    var showsDate = true
    var showsPlace = true
    /// The photo picked up for swapping (tap one, then another).
    var selectedIndex: Int?

    private(set) var facts: CreationFacts
    private(set) var previewImages: CanvasImages = [:]
    private(set) var missing: Set<AssetID> = []
    /// Shapes measured from loaded images; they win over stored metadata.
    private(set) var measuredAspects: [AssetID: Double] = [:]
    let export = ExportController()

    @ObservationIgnored private var library: CreationLibrary
    @ObservationIgnored private var suggestionIndex = 0
    @ObservationIgnored private let engine = CollageLayoutEngine()
    @ObservationIgnored private let designer = CollageAutoDesigner()

    init(source: CreationSource, photos: [AssetID], library: CreationLibrary) {
        self.source = source
        self.library = library
        let initial = Array(photos.prefix(CreationLimits.collage.upperBound))
        self.photoIDs = initial
        self.facts = library.facts(for: source, photos: initial)
        makeItForMe()
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
        let title = showsTitle ? titleText : nil
        var detail: [String] = []
        if showsDate, let dateText { detail.append(dateText) }
        // The place is already the title when they're the same name.
        if showsPlace, let placeText, placeText != title { detail.append(placeText) }
        return CaptionContent(title: title, detail: detail.isEmpty ? nil : detail.joined(separator: " · "))
    }

    var captionSpec: CollageCaptionSpec {
        let content = caption
        return CollageCaptionSpec(showsTitle: content.title != nil, showsDetail: content.detail != nil)
    }

    var layout: CollageLayout {
        engine.layout(photoAspects: aspects, style: style, canvas: aspectRatio.designSize, caption: captionSpec)
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
        facts = library.facts(for: source, photos: photoIDs)
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
