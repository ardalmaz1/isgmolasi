import Foundation
import Observation
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
/// - The first change writes the draft at once. Later changes are written after a short pause
///   (not on every frame), and at once when the editor closes or disappears, or the app resigns
///   active, goes to the background or terminates (`flush`).
/// - "Save", or saving/sharing the image, turns the same record into a finished creation — the
///   draft never lingers as a duplicate.
/// - Without a store (previews, some tests) it keeps nothing.
@Observable
@MainActor
final class CreationKeeper {
    static let pause: Duration = .milliseconds(800)

    let id: UUID
    let kind: SavedCreationKind
    let source: CreationSource
    let createdAt: Date
    /// The record as last written, if it has been.
    private(set) var record: SavedCreation?
    @ObservationIgnored private(set) var hasUnsavedChanges = false
    /// The user deleted it: nothing may write it back.
    @ObservationIgnored private var isDiscarded = false

    @ObservationIgnored private weak var store: StoryStore?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// What the editor holds right now; set by the editor once it exists.
    @ObservationIgnored var content: @MainActor () -> CreationContent? = { nil }

    init(kind: SavedCreationKind, source: CreationSource, store: StoryStore?, existing: SavedCreation? = nil, now: Date = Date()) {
        self.id = existing?.id ?? UUID()
        self.kind = kind
        self.source = existing?.source ?? source
        self.createdAt = existing?.createdAt ?? now
        self.record = existing
        self.store = store
    }

    /// Finished (in My Creations), rather than a draft.
    var isSaved: Bool { record?.status == .saved }
    /// Written at least once.
    var exists: Bool { record != nil }

    /// The user changed something: write it shortly. The first change creates the draft at once,
    /// so it exists even if the app is closed straight away.
    func changed() {
        guard store != nil, !isDiscarded else { return }
        hasUnsavedChanges = true
        pending?.cancel()
        if record == nil {
            flush()
            return
        }
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

    /// Forgets the record after the user deleted it, so nothing writes it back.
    func forget() {
        pending?.cancel()
        pending = nil
        hasUnsavedChanges = false
        isDiscarded = true
        record = nil
    }

    /// Its image was saved to Photos or shared: it is finished too.
    func markExported(now: Date = Date()) {
        pending?.cancel()
        write(now: now) { $0.markExported(at: now) }
    }

    private func write(now: Date, _ change: (inout SavedCreation) -> Void) {
        guard let store, !isDiscarded, let content = content() else { return }
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
