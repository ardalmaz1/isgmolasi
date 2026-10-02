import Foundation
import Observation
import os
import ReliveCore

/// How an import changed the selection.
struct SelectionChange: Equatable, Sendable {
    var added: Int
    var removed: Int

    var hasChanges: Bool { added > 0 || removed > 0 }
}

/// The user's story and everything they decided about it.
///
/// Owns the selected assets (as references + cached metadata), the generated story, per-moment
/// user state and photo availability. Views read from it; all changes go through its methods so
/// persistence and derived values (timeline, statistics) stay consistent.
@Observable
@MainActor
final class StoryStore {
    enum ProcessingState: Equatable {
        case idle
        case running(MemoryEngineProgress)
        case finished(MemoryEngineDiagnostics)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    /// How a processing run ended. Every caller of `process()` receives it, so leaving the
    /// processing screen is driven by an awaited result — not by catching a state change.
    enum ProcessingOutcome: Equatable, Sendable {
        case finished(MemoryEngineDiagnostics)
        case failed(String)
        /// Stopped by Start Over; the result, if any, was discarded.
        case cancelled
    }

    private(set) var story: Story
    private(set) var assets: [AssetID: MemoryAsset]
    private(set) var userStates: [MomentID: MomentUserState]
    /// Assets that no longer resolve in the library (deleted, or access removed).
    private(set) var unavailableAssetIDs: Set<AssetID> = []
    private(set) var accessStatus: PhotoAccessStatus
    private(set) var processing: ProcessingState = .idle
    /// Derived: what the timeline shows.
    private(set) var sections: [TimelineSection] = []
    /// Derived: what the reveal and Us screens count.
    private(set) var statistics: StoryStatistics = .zero
    /// Images Relive saved to the library itself; never imported as memories.
    private(set) var createdAssetIDs: Set<AssetID>
    /// Saved Memory Books, most recently changed first.
    private(set) var books: [MemoryBook]

    let calendar: Calendar
    let photoLibrary: any PhotoLibraryProviding
    private let repository: any StoryRepository
    private let analyzer: any AssetAnalyzing
    private let placeResolver: any ManagedPlaceNameResolving
    private let analytics: any AnalyticsTracking
    private static let logger = Logger(subsystem: "app.relive", category: "story")

    /// The run in flight. Callers arriving while it runs wait for it instead of starting another.
    @ObservationIgnored private var activeRun: Task<ProcessingOutcome, Never>?
    /// Identifies the current run; a run that is no longer current (cancelled by Start Over)
    /// can't write progress or an outcome.
    @ObservationIgnored private var activeRunID: UUID?

    init(
        repository: any StoryRepository,
        photoLibrary: any PhotoLibraryProviding,
        analyzer: any AssetAnalyzing,
        placeResolver: any ManagedPlaceNameResolving,
        analytics: any AnalyticsTracking,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.photoLibrary = photoLibrary
        self.analyzer = analyzer
        self.placeResolver = placeResolver
        self.analytics = analytics
        self.calendar = calendar
        self.story = repository.loadStory() ?? .empty
        self.assets = Dictionary(repository.loadAssets().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.userStates = repository.loadMomentStates()
        self.createdAssetIDs = repository.loadCreatedAssetIDs()
        self.books = repository.loadBooks().sorted { $0.updatedAt > $1.updatedAt }
        self.accessStatus = photoLibrary.accessStatus()
        recomputeDerived()
    }

    // MARK: - Reading

    var hasSelection: Bool { !assets.isEmpty }
    var hasStory: Bool { !story.moments.isEmpty }
    var selectionCount: Int { assets.count }

    func isAvailable(_ id: AssetID) -> Bool {
        !unavailableAssetIDs.contains(id)
    }

    func userState(for id: MomentID) -> MomentUserState {
        userStates[id] ?? MomentUserState()
    }

    func moment(id: MomentID) -> Moment? {
        story.moment(id: id)
    }

    func chapter(for moment: Moment) -> Chapter? {
        story.chapter(for: moment)
    }

    func isVisible(_ moment: Moment) -> Bool {
        !userState(for: moment.id).isHidden && moment.assetIDs.contains(where: isAvailable)
    }

    /// The cover to show, honouring the user's choice.
    func heroAssetID(for moment: Moment) -> AssetID? {
        HeroSelector.resolvedHero(for: moment, userState: userStates[moment.id], isAvailable: isAvailable)
    }

    /// Featured assets (and optionally the collapsed similar ones) that can still be shown.
    func displayAssets(for moment: Moment, includeSimilar: Bool) -> [MemoryAsset] {
        let ids = includeSimilar ? moment.featuredAssetIDs + moment.similarAssetIDs : moment.featuredAssetIDs
        return ids.filter(isAvailable).compactMap { assets[$0] }
    }

    func similarCount(for moment: Moment) -> Int {
        moment.similarAssetIDs.filter(isAvailable).count
    }

    /// Visible moments in timeline order.
    var visibleMoments: [Moment] {
        sections.flatMap(\.items).flatMap(\.moments)
    }

    var hiddenMoments: [Moment] {
        story.moments.filter { userState(for: $0.id).isHidden }
    }

    /// Photos spread evenly across the story, for the reveal mosaic: one cover per moment, and
    /// when there are fewer moments than slots, more photos from the same moments.
    func representativeHeroIDs(limit: Int) -> [AssetID] {
        let moments = visibleMoments.filter { $0.kind != .undated }
        guard !moments.isEmpty, limit > 0 else { return [] }
        let step = max(1, moments.count / limit)
        var picked = stride(from: 0, to: moments.count, by: step)
            .prefix(limit)
            .compactMap { heroAssetID(for: moments[$0]) }
        var round = 0
        while picked.count < limit, round < 8 {
            var addedThisRound = false
            for moment in moments where picked.count < limit {
                let extras = moment.featuredAssetIDs.filter { isAvailable($0) && !picked.contains($0) && assets[$0]?.kind == .photo }
                if let next = extras.first {
                    picked.append(next)
                    addedThisRound = true
                }
            }
            if !addedThisRound { break }
            round += 1
        }
        return picked
    }

    /// Where "Continue your story" should take the user.
    func nextMoment(after lastViewed: MomentID?) -> Moment? {
        let moments = visibleMoments
        guard let lastViewed, let index = moments.firstIndex(where: { $0.id == lastViewed }) else {
            return moments.first
        }
        let next = moments.index(after: index)
        return next < moments.endIndex ? moments[next] : nil
    }

    // MARK: - Found for You

    func selectFoundMemory(now: Date) -> FoundMemory? {
        FoundForYouService(calendar: calendar).select(
            story: story,
            assets: assets,
            userStates: userStates,
            isAvailable: isAvailable,
            now: now
        )
    }

    /// Rebuilds a previously chosen memory if it is still showable.
    func foundMemory(from record: FoundForYouRecord, now: Date) -> FoundMemory? {
        guard let moment = story.moment(id: record.momentID), isVisible(moment),
              !userState(for: moment.id).isExcludedFromSurfacing,
              moment.assetIDs.contains(record.assetID), isAvailable(record.assetID) else { return nil }
        let date = assets[record.assetID]?.creationDate ?? moment.startDate
        return FoundMemory(
            momentID: moment.id,
            assetID: record.assetID,
            captureDate: date,
            ageDescription: date.map { RelativeAgeDescriber(calendar: calendar).describe($0, now: now) } ?? "",
            place: moment.place
        )
    }

    // MARK: - Importing

    /// Adds the given library items to the selection.
    @discardableResult
    func importSelection(identifiers: [AssetID]) async -> SelectionChange {
        let fetched = await photoLibrary.assets(withIdentifiers: identifiers)
        return merge(fetched, replacingSelection: false)
    }

    /// Makes the selection match exactly what Relive can see (used with limited access, where the
    /// user's system-level selection *is* the selection).
    @discardableResult
    func syncWithAccessibleAssets() async -> SelectionChange {
        let fetched = await photoLibrary.allAccessibleAssets()
        return merge(fetched, replacingSelection: true)
    }

    private func merge(_ fetched: [MemoryAsset], replacingSelection: Bool) -> SelectionChange {
        accessStatus = photoLibrary.accessStatus()
        var updated = replacingSelection ? [:] : assets
        var added = 0
        // A collage or story card Relive saved is not a memory, even when it becomes visible.
        for var asset in fetched where !createdAssetIDs.contains(asset.id) {
            if let existing = assets[asset.id] {
                // Keep cached analysis; refresh metadata that may have changed (e.g. favorite).
                asset.analysis = existing.analysis
            } else {
                added += 1
            }
            updated[asset.id] = asset
        }
        let removed = assets.keys.filter { updated[$0] == nil }.count
        assets = updated
        repository.saveAssets(Array(updated.values))
        return SelectionChange(added: added, removed: removed)
    }

    // MARK: - Creations

    /// A snapshot of the story for making collages, story cards and recaps.
    var creationLibrary: CreationLibrary {
        CreationLibrary(
            story: story,
            assets: assets,
            userStates: userStates,
            unavailableAssetIDs: unavailableAssetIDs,
            calendar: calendar
        )
    }

    /// Remembers images Relive saved to the photo library, so they are never imported as memories.
    func recordCreatedAssets(_ ids: [AssetID]) {
        guard !ids.isEmpty else { return }
        createdAssetIDs.formUnion(ids)
        repository.recordCreatedAssets(ids)
    }

    // MARK: - Memory Books

    func book(id: UUID) -> MemoryBook? {
        books.first { $0.id == id }
    }

    /// Saves a new or changed book and keeps the list in most-recent order.
    func saveBook(_ book: MemoryBook, now: Date = Date()) {
        var book = book
        book.updatedAt = now
        books.removeAll { $0.id == book.id }
        books.insert(book, at: 0)
        repository.saveBook(book)
    }

    func deleteBook(id: UUID) {
        books.removeAll { $0.id == id }
        repository.deleteBook(id: id)
    }

    // MARK: - Processing

    /// Runs the Memory Engine over the whole selection and returns how it ended. Cached analysis
    /// is reused, so adding a few memories later only analyzes the new ones.
    ///
    /// Only one run happens at a time: a caller arriving during a run waits for that run and gets
    /// the same outcome. A run isn't tied to any view's lifetime; only `resetAll()` cancels it.
    @discardableResult
    func process() async -> ProcessingOutcome {
        if let activeRun {
            return await activeRun.value
        }
        let runID = UUID()
        let run = Task { () -> ProcessingOutcome in
            let outcome = await self.runPipeline(runID: runID)
            if self.activeRunID == runID {
                self.activeRun = nil
                self.activeRunID = nil
            }
            return outcome
        }
        activeRun = run
        activeRunID = runID
        return await run.value
    }

    private func runPipeline(runID: UUID) async -> ProcessingOutcome {
        // Started over before the run got going.
        guard !Task.isCancelled, activeRunID == runID else {
            return conclude(runID, .cancelled)
        }
        guard !assets.isEmpty else {
            return conclude(runID, .failed("Choose a few photos first."))
        }

        let started = Date()
        processing = .running(MemoryEngineProgress(stage: .readingMetadata))
        // Ask for a little time to finish if the user switches apps mid-way.
        let backgroundActivity = BackgroundActivity(name: "relive.processing")
        defer { backgroundActivity.end() }
        await placeResolver.resetFailures()

        // Leave at least one core to the interface.
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let engine = MemoryEngine(
            configuration: MemoryEngineConfiguration(
                calendar: calendar,
                analysisConcurrency: max(1, min(4, cores - 1)),
                analysisPriority: .utility
            ),
            analyzer: analyzer,
            placeResolver: placeResolver,
            namingService: LocalMomentNamingService(calendar: calendar, locale: .current)
        )
        let input = Array(assets.values)
        let (updates, continuation) = AsyncStream.makeStream(of: MemoryEngineProgress.self, bufferingPolicy: .bufferingNewest(1))
        // Progress can only move the current, still-running pipeline forward. It can never
        // overwrite an outcome or another run's state.
        let progressWriter = Task { @MainActor [weak self] in
            for await progress in updates {
                guard let self, self.activeRunID == runID, self.processing.isRunning else { continue }
                self.processing = .running(progress)
            }
        }

        let result: MemoryEngineResult
        do {
            result = try await engine.buildStory(from: input, now: Date()) { progress in
                continuation.yield(progress)
            }
        } catch {
            continuation.finish()
            await progressWriter.value
            if error is CancellationError || Task.isCancelled {
                return conclude(runID, .cancelled)
            }
            Self.logger.error("Processing failed: \(error.localizedDescription, privacy: .public)")
            return conclude(runID, .failed("Something went wrong while organizing your photos."))
        }
        // Deliver every pending progress update before the outcome, so none can follow it.
        continuation.finish()
        await progressWriter.value

        // Started over while the engine was finishing: discard the result.
        guard !Task.isCancelled, activeRunID == runID else {
            return conclude(runID, .cancelled)
        }

        let reconciled = MomentReconciler().reconcile(new: result.story, previous: story)
        story = reconciled
        assets = Dictionary(result.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        repository.saveAssets(result.assets)
        repository.saveStory(reconciled)
        recomputeDerived()

        #if DEBUG
        logDuplicateDetails(result)
        #endif
        let diagnostics = result.diagnostics
        Self.logger.notice("Story built: \(diagnostics.inputCount) assets, \(diagnostics.momentCount) moments, \(diagnostics.chapterCount) chapters, \(diagnostics.duplicateCount) duplicates, \(diagnostics.similarCount) similar, \(diagnostics.analysisFailureCount) analysis failures, \(diagnostics.namedPlaceCount) places in \(Int(Date().timeIntervalSince(started)))s\(diagnostics.embeddingsIgnored ? " (image embeddings were uniform and ignored)" : "")")
        analytics.track(.memoryProcessingCompleted, [
            "assets": String(diagnostics.inputCount),
            "moments": String(diagnostics.momentCount),
            "chapters": String(diagnostics.chapterCount),
            "duplicates": String(diagnostics.duplicateCount),
            "analysis_failures": String(diagnostics.analysisFailureCount),
            "seconds": String(Int(Date().timeIntervalSince(started))),
        ])
        return conclude(runID, .finished(diagnostics))
    }

    /// Writes a run's outcome — the one place a run ends. The outcome of a run that is no longer
    /// current (cancelled by Start Over) is returned to its callers but never shown.
    private func conclude(_ runID: UUID, _ outcome: ProcessingOutcome) -> ProcessingOutcome {
        guard activeRunID == runID else { return outcome }
        switch outcome {
        case .finished(let diagnostics): processing = .finished(diagnostics)
        case .failed(let message): processing = .failed(message)
        case .cancelled: processing = .idle
        }
        return outcome
    }

    #if DEBUG
    /// Development aid for tuning `SimilarityConfiguration` on real libraries: one line per
    /// copy that was attached to an original, with the signals that decided it.
    private func logDuplicateDetails(_ result: MemoryEngineResult) {
        let byID = Dictionary(result.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for group in result.duplicateGroups {
            guard let primary = byID[group.primary] else { continue }
            for copyID in group.copies {
                guard let copy = byID[copyID] else { continue }
                let lhs = primary.analysis?.fingerprint
                let rhs = copy.analysis?.fingerprint
                let feature = lhs.flatMap { left in rhs.flatMap { left.featureDistance(to: $0) } }
                let hash = lhs.flatMap { left in rhs.flatMap { left.hashDistance(to: $0) } }
                Self.logger.notice("Duplicate: copy \(copy.pixelWidth)x\(copy.pixelHeight) \(copy.creationDate?.formatted() ?? "undated") → kept \(primary.pixelWidth)x\(primary.pixelHeight) \(primary.creationDate?.formatted() ?? "undated"); feature \(feature.map { String(format: "%.3f", $0) } ?? "–"), hash \(hash.map(String.init) ?? "–")")
            }
        }
    }
    #endif

    func acknowledgeProcessingResult() {
        if !processing.isRunning {
            processing = .idle
        }
    }

    // MARK: - Availability

    /// Re-checks which photos still exist and whether access changed. Cheap; called when the app
    /// becomes active.
    func refreshAvailability() async {
        accessStatus = photoLibrary.accessStatus()
        let identifiers = Array(assets.keys)
        guard !identifiers.isEmpty else {
            unavailableAssetIDs = []
            return
        }
        let available = accessStatus.canReadSelection ? await photoLibrary.availableIdentifiers(among: identifiers) : []
        let missing = Set(identifiers).subtracting(available)
        if missing != unavailableAssetIDs {
            unavailableAssetIDs = missing
            recomputeDerived()
        }
    }

    // MARK: - User decisions

    func setNote(_ text: String, for id: MomentID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateState(for: id) { state in
            state.note = trimmed.isEmpty ? nil : trimmed
            state.noteUpdatedAt = Date()
        }
        if !trimmed.isEmpty {
            analytics.track(.noteAdded, ["length": String(trimmed.count)])
        }
    }

    func setHidden(_ hidden: Bool, for id: MomentID) {
        updateState(for: id) { $0.isHidden = hidden }
        recomputeDerived()
        if hidden {
            analytics.track(.memoryHidden, ["scope": "story"])
        }
    }

    /// "Don't show this again" for Found for You. The moment stays in the timeline.
    func excludeFromSurfacing(_ id: MomentID) {
        updateState(for: id) { $0.isExcludedFromSurfacing = true }
        analytics.track(.memoryHidden, ["scope": "found_for_you"])
    }

    func setCover(_ assetID: AssetID?, for id: MomentID) {
        updateState(for: id) { $0.heroOverrideAssetID = assetID }
    }

    func markOpened(_ id: MomentID) {
        updateState(for: id) { $0.lastOpenedAt = Date() }
    }

    func markSurfaced(_ id: MomentID, at date: Date) {
        updateState(for: id) { state in
            state.lastSurfacedAt = date
            state.surfacedCount += 1
        }
    }

    private func updateState(for id: MomentID, _ change: (inout MomentUserState) -> Void) {
        var state = userState(for: id)
        change(&state)
        userStates[id] = state
        repository.saveMomentState(state, for: id)
    }

    // MARK: - Reset

    func resetAll() {
        activeRun?.cancel()
        activeRun = nil
        activeRunID = nil
        repository.deleteAll()
        story = .empty
        assets = [:]
        userStates = [:]
        unavailableAssetIDs = []
        books = []
        processing = .idle
        recomputeDerived()
        Task { await placeResolver.clearCache() }
    }

    // MARK: - Derived values

    private func recomputeDerived() {
        sections = TimelineBuilder(calendar: calendar).sections(for: story, isVisible: isVisible)
        statistics = StoryStatistics.compute(story: story, assets: assets, userStates: userStates, isAvailable: isAvailable)
    }
}
