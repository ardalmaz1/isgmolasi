import Foundation
import Testing
@testable import ReliveCore

@Suite("Performance")
struct PerformanceTests {
    /// 500 analyzed assets over three years, with 768-dimensional embeddings like Vision's.
    static func largeLibrary(count: Int = 500) -> [MemoryAsset] {
        var generator = SplitMix(seed: 7)
        let start = date(2023, 1, 1, 10)
        var time = start
        return (0..<count).map { index in
            // Bursts of photos with occasional multi-day gaps.
            time = time.addingTimeInterval(index.isMultiple(of: 12) ? Double(generator.next() % 9 + 1) * 86_400 : Double(generator.next() % 900))
            let vector = (0..<768).map { _ in Float(generator.next() % 1000) / 1000 }
            let location = index % 3 == 0 ? nil : GeoCoordinate(
                latitude: 40.9 + Double(generator.next() % 100) / 1000,
                longitude: 29.0 + Double(generator.next() % 100) / 1000
            )
            return makeAsset(
                String(format: "perf-%04d", index), at: time, location: location, favorite: index % 50 == 0,
                analysis: analysis(hash: generator.next(), vector: vector, faces: Int(generator.next() % 3), faceQuality: 0.6)
            )
        }
    }

    @Test("500 analyzed assets become a story quickly")
    func fiveHundredAssets() async throws {
        let assets = Self.largeLibrary()
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await makeEngine().buildStory(from: assets, now: date(2026, 9, 28))
        let elapsed = clock.now - started
        #expect(result.story.moments.count > 10)
        #expect(result.story.moments.reduce(0) { $0 + $1.assetIDs.count } == assets.count)
        // Generous bound for unoptimized debug builds on CI; release is far faster.
        #expect(elapsed < .seconds(10), "Took \(elapsed)")
    }
}

/// Small deterministic PRNG for fixtures.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
