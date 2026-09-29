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

    /// A place-name cache file that belongs to one test and is never shared.
    static func temporaryPlaceCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "relive-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "place-names.json")
    }
}
