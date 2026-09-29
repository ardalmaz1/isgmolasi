import Foundation
import ReliveCore
@testable import Relive

/// Keeps everything in memory; nothing touches SwiftData or the disk.
@MainActor
final class InMemoryStoryRepository: StoryRepository {
    var profile = AppProfile.empty
    var assets: [MemoryAsset]
    var story: Story?
    var states: [MomentID: MomentUserState] = [:]

    init(assets: [MemoryAsset] = []) {
        self.assets = assets
    }

    func loadProfile() -> AppProfile { profile }
    func saveProfile(_ profile: AppProfile) { self.profile = profile }
    func loadAssets() -> [MemoryAsset] { assets }
    func saveAssets(_ assets: [MemoryAsset]) { self.assets = assets }
    func loadStory() -> Story? { story }
    func saveStory(_ story: Story) { self.story = story }
    func loadMomentStates() -> [MomentID: MomentUserState] { states }
    func saveMomentState(_ state: MomentUserState, for id: MomentID) { states[id] = state }

    func deleteAll() {
        profile = .empty
        assets = []
        story = nil
        states = [:]
    }
}

/// A library with full access that holds exactly the given assets.
struct FakePhotoLibrary: PhotoLibraryProviding {
    var assets: [MemoryAsset]

    func accessStatus() -> PhotoAccessStatus { .full }
    func requestAccess() async -> PhotoAccessStatus { .full }

    func assets(withIdentifiers identifiers: [AssetID]) async -> [MemoryAsset] {
        let wanted = Set(identifiers)
        return assets.filter { wanted.contains($0.id) }
    }

    func allAccessibleAssets() async -> [MemoryAsset] { assets }

    func availableIdentifiers(among identifiers: [AssetID]) async -> Set<AssetID> {
        Set(identifiers).intersection(assets.map(\.id))
    }
}

/// Analysis that returns immediately — a warm cache or a fast device, where the whole pipeline
/// finishes within a frame or two. This is the timing that exposed the stuck processing screen.
struct InstantAnalyzer: AssetAnalyzing {
    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        AssetAnalysis(sharpness: 0.5, aestheticScore: 0.5)
    }
}

/// Analysis that returns immediately and counts how often it ran.
final class CountingAnalyzer: AssetAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        lock.withLock { calls += 1 }
        return AssetAnalysis(sharpness: 0.5, aestheticScore: 0.5)
    }
}

/// Holds every analysis until `open()` is called, so a run can be observed while in flight.
final class GatedAnalyzer: AssetAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            calls += 1
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
        return AssetAnalysis(sharpness: 0.5, aestheticScore: 0.5)
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiting
        waiting = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// Never looks anything up (the test assets have no locations anyway).
struct NoPlaceLookups: ManagedPlaceNameResolving {
    func placeName(for coordinate: GeoCoordinate) async -> PlaceName? { nil }
    func resetFailures() async {}
    func clearCache() async {}
}

@MainActor
func makeTestStore(assets: [MemoryAsset], analyzer: any AssetAnalyzing = InstantAnalyzer()) -> StoryStore {
    StoryStore(
        repository: InMemoryStoryRepository(assets: assets),
        photoLibrary: FakePhotoLibrary(assets: assets),
        analyzer: analyzer,
        placeResolver: NoPlaceLookups(),
        analytics: InMemoryAnalyticsTracker()
    )
}

struct ConditionTimedOut: Error {}

/// Polls `condition` on the main actor until it holds; throws (failing the test) after `timeout`.
@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw ConditionTimedOut() }
        try await Task.sleep(for: .milliseconds(10))
    }
}

enum TestLibrary {
    /// `count` photos, a few minutes apart, spread over a handful of evenings. No locations, so
    /// no place lookups happen.
    static func assets(count: Int) -> [MemoryAsset] {
        let start = Date(timeIntervalSince1970: 1_720_000_000) // July 2024
        return (0..<count).map { index in
            let evening = Double(index / 25) * 86_400 * 9
            let minutes = Double(index % 25) * 4 * 60
            return MemoryAsset(
                localIdentifier: String(format: "test-asset-%04d", index),
                creationDate: start.addingTimeInterval(evening + minutes),
                pixelWidth: 3024,
                pixelHeight: 4032
            )
        }
    }
}
