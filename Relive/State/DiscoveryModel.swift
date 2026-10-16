import Foundation
import Observation
import os
import ReliveCore

/// "Let Relive find them": with full Photos access, Relive suggests possible moments from the
/// library's metadata and a few small local thumbnails, and the couple keeps the ones that are
/// theirs. Only kept moments are imported into the story.
///
/// Privacy, by construction:
/// - The scan reads metadata (dates, places, favourites, kinds); no images.
/// - At most `DiscoveryConfiguration.maximumAnalysedThumbnails` small thumbnails are analysed,
///   on this iPhone, never downloaded from iCloud. Faces are counted, never identified.
/// - Candidates live only in memory, in this model. Nothing about a moment the couple didn't
///   keep is saved; everything is discarded on Continue, on cancel, and when onboarding ends.
/// - It runs only while the couple watches the progress screen, and can be cancelled.
@Observable
@MainActor
final class DiscoveryModel {
    enum Phase: Equatable {
        case idle
        case requestingAccess
        /// Reading the library's metadata.
        case scanning
        /// Looking at a few photos of each possible moment.
        case lookingAtPhotos(done: Int, total: Int)
        /// Possible moments to keep or skip.
        case ready
        /// Nothing that looks like a moment was found.
        case nothingFound
        /// The user chose specific photos in Apple's dialog instead of full access.
        case limitedAccess
        case denied
        case cancelled
    }

    enum Decision: Equatable {
        case keep
        case notOurs
    }

    private(set) var phase: Phase = .idle
    /// Possible moments, newest first. Temporary: cleared on Continue, cancel and reset.
    private(set) var candidates: [DiscoveryCandidate] = []
    private(set) var decisions: [String: Decision] = [:]
    private(set) var diagnostics: DiscoveryDiagnostics?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private let configuration: DiscoveryConfiguration
    @ObservationIgnored var analytics: any AnalyticsTracking
    @ObservationIgnored private var startedAt = Date()

    init(configuration: DiscoveryConfiguration = .standard, analytics: any AnalyticsTracking = InMemoryAnalyticsTracker()) {
        self.configuration = configuration
        self.analytics = analytics
    }

    var keptCount: Int { decisions.values.filter { $0 == .keep }.count }
    var isWorking: Bool {
        switch phase {
        case .requestingAccess, .scanning, .lookingAtPhotos: true
        default: false
        }
    }

    // MARK: - Running

    /// Asks for access (if not yet decided) and, with full access, looks for possible moments.
    func start(store: StoryStore, relationshipStart: Date?) {
        guard task == nil else { return }
        reset()
        startedAt = Date()
        analytics.track(.discoveryStarted)
        let id = UUID()
        runID = id
        task = Task { [weak self] in
            await self?.run(store: store, relationshipStart: relationshipStart)
            // Only the current run may clear its handle (a cancelled run ending later must not).
            if self?.runID == id { self?.task = nil }
        }
    }

    private func run(store: StoryStore, relationshipStart: Date?) async {
        var status = store.photoLibrary.accessStatus()
        if status == .notDetermined {
            phase = .requestingAccess
            status = await store.photoLibrary.requestAccess()
            guard !Task.isCancelled else { return }
        }
        switch status {
        case .full:
            break
        case .limited:
            phase = .limitedAccess
            return
        case .denied, .restricted, .notDetermined:
            phase = .denied
            return
        }

        phase = .scanning
        let timing = ContinuousClock()
        let scanStart = timing.now
        let library = store.photoLibrary
        let limit = configuration.maximumLibraryAssets
        var scan = await Task.detached(priority: .utility) { await library.discoveryAssets(limit: limit) }.value
        guard !Task.isCancelled else { return }
        // Collages, story cards and movies Relive saved to Photos are not memories.
        let madeByRelive = store.createdAssetIDs
        if !madeByRelive.isEmpty {
            scan.assets.removeAll { madeByRelive.contains($0.id) }
        }
        let scanned = timing.now - scanStart

        let discovery = MemoryDiscovery(configuration: configuration, calendar: store.calendar)
        let shortlistStart = timing.now
        let shortlist = await Task.detached(priority: .utility) {
            discovery.shortlist(from: scan.assets, relationshipStart: relationshipStart, now: Date())
        }.value
        guard !Task.isCancelled else { return }
        let shortlisted = timing.now - shortlistStart
        var diagnostics = shortlist.diagnostics
        diagnostics.libraryAssets = scan.libraryCount
        self.diagnostics = diagnostics

        // A few small local thumbnails per shortlisted moment — bounded, never from iCloud.
        let representatives = Array(shortlist.representativeIDs.prefix(configuration.maximumAnalysedThumbnails))
        let byID = Dictionary(scan.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let analyzer = store.thumbnailAnalyzer
        phase = .lookingAtPhotos(done: 0, total: representatives.count)
        let thumbnailsStart = timing.now
        let assets = representatives.compactMap { byID[$0] }
        let total = representatives.count
        let analyses = await Self.analyse(assets, with: analyzer) { [weak self] done in
            await MainActor.run {
                guard let self, !Task.isCancelled, case .lookingAtPhotos = self.phase else { return }
                self.phase = .lookingAtPhotos(done: done, total: total)
            }
        }
        guard !Task.isCancelled else { return }
        let analysed = timing.now - thumbnailsStart

        candidates = discovery.refine(shortlist, analyses: analyses)
        phase = candidates.isEmpty ? .nothingFound : .ready
        let unavailable = analyses.values.filter { !$0.isAvailable }.count
        analytics.track(.discoveryCompleted, [
            "library": AnalyticsBucket.count(scan.libraryCount),
            "candidates": AnalyticsBucket.count(candidates.count),
            "duration": AnalyticsBucket.seconds(Date().timeIntervalSince(startedAt)),
        ])
        #if DEBUG
        let log = Logger(subsystem: "app.relive", category: "discovery")
        log.notice("\(diagnostics.line, privacy: .public)")
        log.notice("discovery_timing scan=\(Self.milliseconds(scanned), privacy: .public)ms shortlist=\(Self.milliseconds(shortlisted), privacy: .public)ms thumbnails=\(Self.milliseconds(analysed), privacy: .public)ms analysed=\(representatives.count, privacy: .public) unavailable=\(unavailable, privacy: .public) candidates=\(self.candidates.count, privacy: .public)")
        #endif
    }

    /// Stops looking. Nothing found so far is kept.
    func cancel() {
        let wasWorking = isWorking || phase == .ready
        task?.cancel()
        task = nil
        runID = nil
        clear()
        phase = .cancelled
        if wasWorking {
            analytics.track(.discoveryCancelled, ["duration": AnalyticsBucket.seconds(Date().timeIntervalSince(startedAt))])
        }
    }

    // MARK: - Deciding

    func decide(_ candidate: DiscoveryCandidate, _ decision: Decision) {
        guard decisions[candidate.id] != decision else { return }
        decisions[candidate.id] = decision
        analytics.track(decision == .keep ? .candidateMomentKept : .candidateMomentRejected, [
            "trip": candidate.isTrip ? "true" : "false",
            "photos": AnalyticsBucket.count(candidate.assetCount),
        ])
    }

    func decision(for candidate: DiscoveryCandidate) -> Decision? {
        decisions[candidate.id]
    }

    /// Imports the kept moments' photos — nothing from any other moment — and forgets the rest.
    @discardableResult
    func importKept(into store: StoryStore) async -> Int {
        let kept = candidates.filter { decisions[$0.id] == .keep }
        let identifiers = MemoryDiscovery(configuration: configuration, calendar: store.calendar).importIdentifiers(for: kept)
        clear()
        guard !identifiers.isEmpty else { return 0 }
        await store.importSelection(identifiers: identifiers)
        #if DEBUG
        Logger(subsystem: "app.relive", category: "discovery").notice("discovery_import kept=\(kept.count, privacy: .public) imported=\(identifiers.count, privacy: .public)")
        #endif
        return identifiers.count
    }

    // MARK: - Temporary data

    private func clear() {
        candidates = []
        decisions = [:]
    }

    func reset() {
        task?.cancel()
        task = nil
        runID = nil
        clear()
        diagnostics = nil
        phase = .idle
    }

    // MARK: - Helpers

    /// Analyses the representatives off the main actor, two at a time at utility priority (like
    /// the story pipeline), so the interface stays responsive. Stops early when cancelled.
    nonisolated static func analyse(
        _ assets: [MemoryAsset],
        with analyzer: any AssetAnalyzing,
        progress: @escaping @Sendable (Int) async -> Void
    ) async -> [AssetID: RepresentativeAnalysis] {
        var analyses: [AssetID: RepresentativeAnalysis] = [:]
        var done = 0
        for start in stride(from: 0, to: assets.count, by: 2) {
            if Task.isCancelled { break }
            let chunk = Array(assets[start..<min(start + 2, assets.count)])
            await withTaskGroup(of: (AssetID, RepresentativeAnalysis).self) { group in
                for asset in chunk {
                    group.addTask(priority: .utility) {
                        (asset.id, signals(from: await analyzer.analyze(asset)))
                    }
                }
                for await (id, analysis) in group {
                    analyses[id] = analysis
                }
            }
            done += chunk.count
            await progress(done)
        }
        return analyses
    }

    /// Only what discovery ranks with: a face count (never who), utility and aesthetics.
    nonisolated static func signals(from analysis: AssetAnalysis) -> RepresentativeAnalysis {
        guard !analysis.failures.contains(.thumbnailUnavailable) else { return .unavailable }
        return RepresentativeAnalysis(
            faceCount: analysis.failures.contains(.faceDetection) ? nil : analysis.faceCount,
            isUtility: analysis.isUtility,
            aesthetic: analysis.aestheticScore
        )
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
