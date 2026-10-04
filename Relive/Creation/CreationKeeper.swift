import Foundation
import ReliveCore

/// What a collage or story editor currently holds.
enum CreationContent {
    case collage(CollageState)
    case story(StoryState)
}

/// Keeps one collage or story safe while it is made.
///
/// - Nothing is written until the user changes something: a story Relive designed and left
///   untouched isn't a draft.
/// - After a change, the draft is written after a short pause (not on every frame), and at once
///   when the editor closes or the app goes to the background (`flush`).
/// - "Save", or saving/sharing the image, turns the same record into a finished creation — the
///   draft never lingers as a duplicate.
@MainActor
final class CreationKeeper {
    static let pause: Duration = .milliseconds(800)

    let id: UUID
    let kind: SavedCreationKind
    let source: CreationSource
    let createdAt: Date
    /// The record as last written, if it has been.
    private(set) var record: SavedCreation?
    private(set) var hasUnsavedChanges = false

    private weak var store: StoryStore?
    private var pending: Task<Void, Never>?
    private let content: () -> CreationContent?

    init(kind: SavedCreationKind, source: CreationSource, store: StoryStore?, existing: SavedCreation? = nil, now: Date = Date(), content: @escaping () -> CreationContent?) {
        self.id = existing?.id ?? UUID()
        self.kind = kind
        self.source = existing?.source ?? source
        self.createdAt = existing?.createdAt ?? now
        self.record = existing
        self.store = store
        self.content = content
    }

    /// Finished (in My Creations), rather than a draft.
    var isSaved: Bool { record?.status == .saved }
    /// Written at least once.
    var exists: Bool { record != nil }

    /// The user changed something: write it shortly.
    func changed() {
        guard store != nil else { return }
        hasUnsavedChanges = true
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes pending changes now (closing, backgrounding).
    func flush(now: Date = Date()) {
        pending?.cancel()
        pending = nil
        guard hasUnsavedChanges else { return }
        write(now: now) { _ in }
    }

    /// The creation is finished: it moves to My Creations (the same record).
    func markSaved(now: Date = Date()) {
        pending?.cancel()
        write(now: now) { $0.markSaved(at: now) }
    }

    /// Its image was saved to Photos or shared: it is finished too.
    func markExported(now: Date = Date()) {
        pending?.cancel()
        write(now: now) { $0.markExported(at: now) }
    }

    private func write(now: Date, _ change: (inout SavedCreation) -> Void) {
        guard let store, let content = content() else { return }
        var creation = record ?? SavedCreation(id: id, kind: kind, createdAt: createdAt, source: source)
        switch content {
        case .collage(let state): creation.collage = state
        case .story(let state): creation.story = state
        }
        creation.updatedAt = now
        change(&creation)
        store.saveCreation(creation)
        record = store.creation(id: id) ?? creation
        hasUnsavedChanges = false
    }
}
