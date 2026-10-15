import Observation
import os
import ReliveCore
import SwiftUI

/// One Memory Movie being made: the plan Relive built, and the user's own decisions on top.
///
/// - Relive's first cut (and every "Make it for me") comes from `MovieStoryPlanner` on top of
///   Memory Intelligence.
/// - The user's edits win: reordering, removing, replacing a photo or choosing the opening turns
///   the cut into the user's own (`isUserCut`), and from then on only an explicit "Make it for
///   me" may replace it. Style, shape, length and text never change which photos are used.
/// - Drafts are kept like collages and stories (`CreationKeeper`): the state, never frames.
@Observable
@MainActor
final class MovieEditorModel {
    let source: CreationSource
    private(set) var plan: MoviePlan
    private(set) var settings: MovieSettings
    /// The photos the user removed (so a re-plan of Relive's cut doesn't bring them back).
    private(set) var isUserCut: Bool
    /// Photos that can't be shown now (deleted, or no longer shared).
    private(set) var missing: Set<AssetID> = []
    /// The scene selected in the strip.
    var selectedSceneID: AssetID?

    let export = MovieExportController()
    let keeper: CreationKeeper

    @ObservationIgnored private var library: CreationLibrary
    @ObservationIgnored private let analytics: any AnalyticsTracking
    @ObservationIgnored private var tracksChanges = false
    @ObservationIgnored private let editorial: EditorialService

    /// A new movie: Relive makes the first cut.
    init(source: CreationSource, library: CreationLibrary, store: StoryStore? = nil, analytics: any AnalyticsTracking = InMemoryAnalyticsTracker(), settings: MovieSettings = MovieSettings(), editorial: EditorialService = .shared) {
        self.source = source
        self.editorial = editorial
        self.library = library
        self.analytics = analytics
        self.settings = settings
        let plan = MovieStoryPlanner(library: library).plan(source: source, settings: settings)
        self.plan = plan
        self.isUserCut = plan.isUserCut
        self.keeper = CreationKeeper(kind: .movie, source: source, store: store)
        logPlan()
        startKeeping()
    }

    /// A draft or saved movie, reopened as it was. Photos that are gone are left out of the cut
    /// and reported; nothing is swapped in for them.
    init(restoring creation: SavedCreation, state: MovieState, library: CreationLibrary, store: StoryStore?, analytics: any AnalyticsTracking = InMemoryAnalyticsTracker(), editorial: EditorialService = .shared) {
        self.source = creation.source
        self.editorial = editorial
        self.library = library
        self.analytics = analytics
        self.settings = state.settings
        self.isUserCut = state.isUserCut
        self.missing = Set(state.photoIDs.filter { !library.isUsable($0) })
        self.plan = MovieStoryPlanner(library: library).plan(source: creation.source, photos: state.photoIDs, cover: state.cover, settings: state.settings, isUserCut: state.isUserCut)
        self.keeper = CreationKeeper(kind: .movie, source: creation.source, store: store, existing: creation)
        startKeeping()
    }

    private func startKeeping() {
        keeper.content = { [weak self] in
            guard let self else { return nil }
            return .movie(self.state)
        }
        tracksChanges = true
        offerMoreTitles()
    }

    /// What a draft or saved movie keeps.
    var state: MovieState {
        MovieState(photoIDs: plan.photoIDs, cover: plan.cover, settings: settings, isUserCut: isUserCut)
    }

    var canExport: Bool { plan.isReady }

    /// Non-identifying analytics properties.
    var analyticsProperties: [String: String] {
        [
            "source": source.kindCode,
            "style": settings.style.rawValue,
            "aspect": settings.aspect.rawValue,
            "length": settings.length.rawValue,
        ]
    }

    // MARK: - Settings (never change the photos)

    func setStyle(_ style: MovieStyle) {
        guard style != settings.style else { return }
        settings.style = style
        replan()
        analytics.track(.movieStyleChanged, analyticsProperties)
    }

    func setAspect(_ aspect: MovieAspect) {
        guard aspect != settings.aspect else { return }
        settings.aspect = aspect
        replan()
    }

    /// A new length re-chooses photos only for Relive's own cut; a user's cut keeps its photos
    /// (only the rhythm changes).
    func setLength(_ length: MovieLength) {
        guard length != settings.length else { return }
        settings.length = length
        if isUserCut {
            replan()
        } else {
            plan = MovieStoryPlanner(library: library).plan(source: source, settings: settings)
            logPlan()
            changed()
        }
    }

    func setShowsText(_ shows: Bool) {
        guard shows != settings.showsText else { return }
        settings.showsText = shows
        replan()
    }

    // MARK: - The cut (the user's decisions win)

    func move(_ id: AssetID, by offset: Int) {
        var ids = plan.photoIDs
        guard let index = ids.firstIndex(of: id) else { return }
        let target = min(max(0, index + offset), ids.count - 1)
        guard target != index else { return }
        ids.remove(at: index)
        ids.insert(id, at: target)
        applyCut(ids, cover: ids.first)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = plan.photoIDs
        ids.move(fromOffsets: source, toOffset: destination)
        applyCut(ids, cover: ids.first)
    }

    func remove(_ id: AssetID) {
        let ids = plan.photoIDs.filter { $0 != id }
        guard ids.count < plan.photoIDs.count else { return }
        if selectedSceneID == id { selectedSceneID = nil }
        applyCut(ids, cover: ids.first)
    }

    func replace(_ id: AssetID, with newID: AssetID) {
        guard !plan.photoIDs.contains(newID) else { return }
        let ids = plan.photoIDs.map { $0 == id ? newID : $0 }
        selectedSceneID = newID
        applyCut(ids, cover: ids.first)
    }

    /// The photo the movie opens on.
    func makeOpening(_ id: AssetID) {
        applyCut(plan.photoIDs, cover: id)
    }

    /// "Make it for me": Relive makes a fresh cut — a different but still reasonable one each
    /// time (another opening photo, another style). The only action that replaces a user's cut.
    func makeItForMe() {
        settings.variation += 1
        let styles = MovieStyle.allCases
        settings.style = styles[settings.variation % styles.count]
        isUserCut = false
        missing = []
        plan = MovieStoryPlanner(library: library).plan(source: source, settings: settings)
        logPlan()
        changed()
        analytics.track(.movieRegenerated, analyticsProperties)
    }

    // MARK: - The opening title (Relive's words; the user's words win)

    var titleChoice: EditorialChoice { settings.titleChoice ?? EditorialChoice() }

    /// The title as the movie opens with it (`nil`: the user removed it).
    var openingTitle: String? { plan.openingTitle }

    /// More than one safe title is on offer, and the user hasn't written their own.
    var canTryAnotherTitle: Bool {
        plan.titleVariants.count > 1 || (!titleChoice.isDefault && !plan.titleVariants.isEmpty)
    }

    /// "Try another": the next of Relive's validated titles. Never changes the photos.
    func tryAnotherTitle() {
        guard canTryAnotherTitle else { return }
        let next = titleChoice.next(in: plan.titleVariants)
        settings.titleChoice = next.isDefault ? nil : next
        replan()
        analytics.track(.editorialVariantChanged, editorialProperties(["variant": String(next.variant)]))
    }

    /// The user's own title: kept exactly as written (trimmed), never checked or rewritten.
    /// Empty words bring Relive's title back.
    func setOwnTitle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetTitle()
            return
        }
        guard trimmed != openingTitle || plan.openingTitleAuthorship != .user else { return }
        settings.titleChoice = EditorialChoice(userText: String(trimmed.prefix(Self.maximumTitleLength)))
        replan()
        analytics.track(.editorialUserEdited, editorialProperties(["action": "edited"]))
    }

    /// No opening title (the period still shows when it is known).
    func removeTitle() {
        settings.titleChoice = EditorialChoice(isRemoved: true)
        replan()
        analytics.track(.editorialUserEdited, editorialProperties(["action": "removed"]))
    }

    /// Relive's first choice again.
    func resetTitle() {
        guard settings.titleChoice != nil else { return }
        settings.titleChoice = nil
        replan()
        analytics.track(.editorialUserEdited, editorialProperties(["action": "reset"]))
    }

    static let maximumTitleLength = 60

    private func editorialProperties(_ extra: [String: String]) -> [String: String] {
        ["surface": EditorialSurface.movie.rawValue, "kind": EditorialRequestKind.title.rawValue].merging(extra) { $1 }
    }

    /// Where an on-device model can run, it may add a validated alternative or two for "Try
    /// another". What is on screen doesn't change; nothing waits for it.
    private func offerMoreTitles() {
        let request = plan.titleRequest
        let editorial = editorial
        Task { [weak self] in
            guard await editorial.enhance(request) else { return }
            self?.refreshWords()
        }
    }

    /// The same cut with the words available now (no change to the draft).
    private func refreshWords() {
        plan = MovieStoryPlanner(library: library).plan(source: source, photos: plan.photoIDs, cover: plan.cover, settings: settings, isUserCut: isUserCut)
    }

    /// Photos that could replace `id`: the source's own photos not already in the movie.
    var replacementCandidates: [AssetID] {
        let used = Set(plan.photoIDs)
        return library.availablePhotos(for: source).filter { !used.contains($0) && library.isUsable($0) }
    }

    // MARK: - Private

    private func applyCut(_ ids: [AssetID], cover: AssetID?) {
        isUserCut = true
        plan = MovieStoryPlanner(library: library).plan(source: source, photos: ids, cover: cover, settings: settings, isUserCut: true)
        missing = missing.intersection(ids)
        changed()
    }

    /// Settings changed: the same photos in the same order, re-edited.
    private func replan() {
        plan = MovieStoryPlanner(library: library).plan(source: source, photos: plan.photoIDs, cover: plan.cover, settings: settings, isUserCut: isUserCut)
        changed()
    }

    private func changed() {
        guard tracksChanges else { return }
        keeper.changed()
    }

    func flush() {
        keeper.flush()
    }

    private func logPlan() {
        #if DEBUG
        Logger(subsystem: "app.relive", category: "movie").notice("\(self.plan.diagnosticsLine, privacy: .public)")
        #endif
    }
}
