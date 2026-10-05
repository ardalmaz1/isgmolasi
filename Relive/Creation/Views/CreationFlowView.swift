import ReliveCore
import SwiftUI
import UIKit

/// Hosts one creation from start to finish: choosing photos, a moment, a trip, a month or a year
/// when needed, then the collage editor, Story Maker or the new Memory Book. Presented full
/// screen over the app.
struct CreationFlowView: View {
    let request: CreationRequest

    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage: Stage?
    /// The source the editor was started from (favorites get their own "not enough" words).
    @State private var startedFrom: CreationSource?
    /// Photos picked from the photo library for this creation (metadata only, never imported).
    @State private var photoLibraryAssets: [MemoryAsset] = []
    @State private var isPickingFromLibrary = false

    private enum Stage {
        case chooseSource
        case readingLibrary
        case libraryUnavailable(count: Int)
        case choosePhotos(preselected: [AssetID])
        case chooseMoment
        case choosePeriod(PeriodPickerView.Kind)
        case collage(CollageEditorModel)
        case story(StoryMakerModel)
        case book(UUID)
        case notEnough(message: String, preselected: [AssetID])
        /// A kept creation that was deleted meanwhile.
        case gone
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .none:
                    Color.clear
                case .chooseSource:
                    PhotoSourceChooserView(
                        kind: request.kind,
                        onRelive: { stage = .choosePhotos(preselected: []) },
                        onPhotoLibrary: { isPickingFromLibrary = true },
                        onCancel: close
                    )
                case .readingLibrary:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .reliveBackground()
                case .libraryUnavailable(let count):
                    PhotoLibraryUnavailableView(count: count, onChooseAgain: { stage = .chooseSource }, onCancel: close)
                case .choosePhotos(let preselected):
                    MemoryPickerView(
                        title: "Choose Photos",
                        range: request.kind.photoRange,
                        initialSelection: preselected,
                        onDone: { ids in begin(with: .photos(ids)) },
                        onCancel: close
                    )
                case .chooseMoment:
                    MomentPickerView(kind: request.kind, onPick: { id in begin(with: .moment(id)) }, onCancel: close)
                case .choosePeriod(let kind):
                    PeriodPickerView(kind: kind, minimumPhotos: request.kind.photoRange.lowerBound, onPick: begin(with:), onCancel: close)
                case .book(let id):
                    MemoryBookReaderView(bookID: id, onClose: close)
                case .collage(let model):
                    CollageEditorView(model: model, onClose: close)
                case .story(let model):
                    StoryMakerView(
                        model: model,
                        onClose: close,
                        onChoosePhotos: { stage = .chooseSource },
                        isFromFavorites: startedFrom == .favorites
                    )
                case .gone:
                    QuietMessageView(title: "This isn’t here anymore", message: "It may have been deleted.")
                        .frame(maxHeight: .infinity)
                        .reliveBackground()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close", action: close)
                            }
                        }
                case .notEnough(let message, let preselected):
                    QuietMessageView(
                        title: startedFrom == .favorites ? "Not enough favorites" : "Not enough photos",
                        message: message,
                        actionTitle: "Choose Photos",
                        action: { stage = .choosePhotos(preselected: preselected) }
                    )
                    .frame(maxHeight: .infinity)
                    .reliveBackground()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", action: close)
                        }
                    }
                }
            }
        }
        .tint(Palette.accent)
        .photoLibraryPicker(isPresented: $isPickingFromLibrary, maximum: request.kind.photoRange.upperBound) { identifiers in
            Task { await usePhotoLibraryPicks(identifiers) }
        }
        .onAppear {
            guard stage == nil else { return }
            switch request.start {
            case .choosePhotos: stage = .chooseSource
            case .choosePhotoLibrary:
                stage = .chooseSource
                isPickingFromLibrary = true
            case .chooseMoment: stage = .chooseMoment
            case .chooseTrip: stage = .choosePeriod(.trip)
            case .chooseMonth: stage = .choosePeriod(.month)
            case .chooseYear: stage = .choosePeriod(.year)
            case .source(let source): begin(with: source)
            case .resume(let id): resume(id)
            }
        }
        // Drafts are kept when the app leaves the screen, not only after the editor's pause —
        // from the scene phase and, independently, from the app's own lifecycle notifications.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flush() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in flush() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in flush() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in flush() }
        .onDisappear { flush() }
    }

    private func close() {
        flush()
        dismiss()
    }

    /// Writes the open collage or story's pending changes now.
    private func flush() {
        switch stage {
        case .collage(let model): model.flush()
        case .story(let model): model.flush()
        default: break
        }
    }

    /// Reopens a kept book, collage or story where it was left. Photos that are gone are shown
    /// as missing; nothing is swapped in for them.
    private func resume(_ id: UUID) {
        if request.kind == .book {
            stage = store.book(id: id) == nil ? .gone : .book(id)
            return
        }
        guard let creation = store.creation(id: id) else {
            stage = .gone
            return
        }
        let library = store.creationLibrary(for: creation)
        switch creation.kind {
        case .collage:
            guard let state = creation.collage else { stage = .gone; return }
            stage = .collage(CollageEditorModel(restoring: creation, state: state, library: library, store: store))
        case .story:
            guard let state = creation.story else { stage = .gone; return }
            stage = .story(StoryMakerModel(restoring: creation, state: state, library: library, store: store))
        }
        startedFrom = creation.source
        analytics.track(creation.isDraft ? .draftResumed : .creationReopened, ["kind": creation.kind.rawValue])
    }

    /// The story, plus the photos picked from the photo library for this creation.
    private var library: CreationLibrary {
        store.creationLibrary.addingPhotoLibraryAssets(photoLibraryAssets)
    }

    /// Reads the picked photos' own metadata, then starts the creation from them.
    private func usePhotoLibraryPicks(_ identifiers: [AssetID]) async {
        guard !identifiers.isEmpty else { return }
        stage = .readingLibrary
        let picks = await store.resolvePhotoLibraryPicks(identifiers)
        if picks.ids.isEmpty {
            stage = .libraryUnavailable(count: max(1, picks.unavailableCount))
            return
        }
        photoLibraryAssets += picks.libraryAssets.filter { asset in !photoLibraryAssets.contains { $0.id == asset.id } }
        analytics.track(.photoLibraryPicked, [
            "kind": request.kind.rawValue,
            "photos": String(picks.ids.count),
            "outside_story": String(picks.libraryAssets.count),
        ])
        begin(with: .photos(picks.ids))
    }

    /// Opens the editor for `source`, or explains gently when there isn't enough to work with.
    private func begin(with source: CreationSource) {
        let library = self.library
        startedFrom = source
        switch request.kind {
        case .collage:
            let photos = sourcePhotos(source, library: library)
            if photos.count < CreationLimits.collage.lowerBound {
                let message: String
                if source == .favorites {
                    message = photos.isEmpty
                        ? "Favorite a few memories to make a collage from them."
                        : "Add a few more favorites to make a collage. A collage needs at least two photos."
                } else {
                    message = photos.isEmpty
                        ? "There are no photos here that can go into a collage."
                        : "A collage needs at least two photos. Choose another to go with this one."
                }
                stage = .notEnough(message: message, preselected: photos.filter { store.assets[$0] != nil })
            } else {
                stage = .collage(CollageEditorModel(source: source, photos: photos, library: library, store: store))
            }
        case .story:
            stage = .story(StoryMakerModel(source: source, library: library, store: store))
        case .book:
            switch MemoryBookBuilder(library: library).makeBook(from: source, now: Date()) {
            case .success(let book):
                store.saveBook(book)
                analytics.track(.memoryBookCreated, ["photos": String(book.photoIDs.count), "origin": request.origin])
                stage = .book(book.id)
            case .failure(.notEnoughPhotos(let available, let required)):
                let message: String
                if source == .favorites {
                    message = available == 0
                        ? "Favorite a few memories to make a book from them. A book needs at least \(required) photos."
                        : "Add a few more favorites to make a book. A book needs at least \(required) photos, and you have \(available == 1 ? "1 favorite" : "\(available) favorites") that can be used."
                } else {
                    message = available == 0
                        ? "A book needs at least \(required) photos, and there are none here that can be used."
                        : "A book needs at least \(required) photos, and there \(available == 1 ? "is only 1" : "are only \(available)") here. Choose a few more to go with them."
                }
                stage = .notEnough(message: message, preselected: library.availablePhotos(for: source).filter { store.assets[$0] != nil })
            }
        }
    }

    private func sourcePhotos(_ source: CreationSource, library: CreationLibrary) -> [AssetID] {
        switch source {
        case .photos(let ids):
            library.initialPhotos(for: source, limit: ids.count)
        default:
            library.initialPhotos(for: source, limit: CreationLimits.collagePreselection)
        }
    }
}
