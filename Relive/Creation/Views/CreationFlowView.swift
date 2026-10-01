import ReliveCore
import SwiftUI

/// Hosts one creation from start to finish: choosing photos or a moment when needed, then the
/// collage editor or Story Maker. Presented full screen over the app.
struct CreationFlowView: View {
    let request: CreationRequest

    @Environment(StoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage?

    private enum Stage {
        case choosePhotos(preselected: [AssetID])
        case chooseMoment
        case collage(CollageEditorModel)
        case story(StoryMakerModel)
        case notEnough(message: String, preselected: [AssetID])
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .none:
                    Color.clear
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
                case .collage(let model):
                    CollageEditorView(model: model, onClose: close)
                case .story(let model):
                    StoryMakerView(model: model, onClose: close) {
                        stage = .choosePhotos(preselected: store.creationLibrary.availablePhotos(for: model.source))
                    }
                case .notEnough(let message, let preselected):
                    QuietMessageView(
                        title: "Not enough photos",
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
        .onAppear {
            guard stage == nil else { return }
            switch request.start {
            case .choosePhotos: stage = .choosePhotos(preselected: [])
            case .chooseMoment: stage = .chooseMoment
            case .source(let source): begin(with: source)
            }
        }
    }

    private func close() {
        dismiss()
    }

    /// Opens the editor for `source`, or explains gently when there isn't enough to work with.
    private func begin(with source: CreationSource) {
        let library = store.creationLibrary
        switch request.kind {
        case .collage:
            let photos = sourcePhotos(source, library: library)
            if photos.count < CreationLimits.collage.lowerBound {
                stage = .notEnough(
                    message: photos.isEmpty
                        ? "There are no photos here that can go into a collage."
                        : "A collage needs at least two photos. Choose another to go with this one.",
                    preselected: photos
                )
            } else {
                stage = .collage(CollageEditorModel(source: source, photos: photos, library: library))
            }
        case .story:
            stage = .story(StoryMakerModel(source: source, library: library))
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
