import Foundation
import Testing
@testable import ReliveCore

@Suite("DuplicateDetector")
struct DuplicateDetectorTests {
    let detector = DuplicateDetector()

    @Test("An original and its messaging-app copy are duplicates; the original is kept")
    func whatsappCopy() {
        let original = SyntheticImage.scene(width: 480, height: 640)
        let copy = SyntheticImage.recompressed(original, maxDimension: 200, noise: 4)
        let originalAsset = makeAsset(
            "original", at: date(2025, 8, 7, 19, 0), location: Places.kas, width: 3024, height: 4032,
            analysis: analysis(hash: original.differenceHash(), contrast: original.contrast())
        )
        let copyAsset = makeAsset(
            "copy", at: date(2025, 8, 12, 9, 0), width: 1200, height: 1600,
            analysis: analysis(hash: copy.differenceHash(), contrast: copy.contrast())
        )
        let groups = detector.duplicateGroups(in: [copyAsset, originalAsset])
        #expect(groups == [DuplicateDetector.DuplicateGroup(primary: "original", copies: ["copy"])])
    }

    @Test("Different photos are not duplicates")
    func differentPhotos() {
        let first = SyntheticImage.scene(width: 480, height: 640, variant: 0)
        let second = SyntheticImage.scene(width: 480, height: 640, variant: 1)
        let assets = [
            makeAsset("a", at: date(2025, 1, 1), analysis: analysis(hash: first.differenceHash(), contrast: first.contrast())),
            makeAsset("b", at: date(2025, 1, 1), analysis: analysis(hash: second.differenceHash(), contrast: second.contrast())),
        ]
        #expect(detector.duplicateGroups(in: assets).isEmpty)
    }

    @Test("Crops (different aspect ratio) are not duplicates")
    func cropsAreNotCopies() {
        let assets = [
            makeAsset("full", at: date(2025, 1, 1), width: 3000, height: 4000, analysis: analysis(hash: 0xABCD)),
            makeAsset("square", at: date(2025, 1, 1), width: 3000, height: 3000, analysis: analysis(hash: 0xABCD)),
        ]
        #expect(detector.duplicateGroups(in: assets).isEmpty)
    }

    @Test("Low-contrast images need embedding agreement")
    func lowContrastHashNotTrusted() {
        let assets = [
            makeAsset("night1", at: date(2025, 1, 1), analysis: analysis(hash: 0, contrast: 0.01)),
            makeAsset("night2", at: date(2025, 1, 2), analysis: analysis(hash: 0, contrast: 0.01)),
        ]
        #expect(detector.duplicateGroups(in: assets).isEmpty)
    }

    @Test("Embeddings decide when available")
    func embeddingsDecide() {
        let near = [
            makeAsset("x", at: date(2025, 1, 1), analysis: analysis(hash: 0xFF, vector: [1, 0, 0])),
            makeAsset("y", at: date(2025, 1, 5), width: 1512, height: 2016, analysis: analysis(hash: 0xFF, vector: [0.99, 0.05, 0])),
        ]
        #expect(detector.duplicateGroups(in: near).count == 1)

        let far = [
            makeAsset("x", at: date(2025, 1, 1), analysis: analysis(hash: 0xFF, vector: [1, 0, 0])),
            makeAsset("y", at: date(2025, 1, 5), analysis: analysis(hash: 0xFF, vector: [0, 1, 0])),
        ]
        #expect(detector.duplicateGroups(in: far).isEmpty)
    }

    @Test("Videos are never treated as duplicates")
    func videosIgnored() {
        let assets = [
            makeAsset("v1", at: date(2025, 1, 1), kind: .video, analysis: analysis(hash: 1)),
            makeAsset("v2", at: date(2025, 1, 1), kind: .video, analysis: analysis(hash: 1)),
        ]
        #expect(detector.duplicateGroups(in: assets).isEmpty)
    }

    @Test("A burst collapses to its best shot")
    func burstCollapses() {
        let start = date(2025, 8, 7, 19, 0)
        let assets = (0..<4).map { index in
            makeAsset(
                "burst-\(index)", at: start.addingTimeInterval(Double(index) * 2),
                analysis: analysis(hash: 0xF0F0 ^ UInt64(index), vector: [1, Float(index) * 0.05, 0], sharpness: index == 2 ? 0.95 : 0.3)
            )
        }
        let scorer = AssetScorer()
        let groups = detector.similarGroups(in: assets) { scorer.score($0) }
        #expect(groups.count == 1)
        #expect(groups.first?.representative == "burst-2")
        #expect(groups.first?.members.count == 4)
    }

    @Test("Similar-looking photos far apart in time stay separate")
    func similarButApart() {
        let assets = [
            makeAsset("sunset-1", at: date(2025, 8, 7, 19, 0), analysis: analysis(hash: 1, vector: [1, 0])),
            makeAsset("sunset-2", at: date(2025, 8, 7, 19, 30), analysis: analysis(hash: 1, vector: [1, 0])),
        ]
        #expect(detector.similarGroups(in: assets) { _ in 0 }.isEmpty)
    }

    @Test("Fingerprints round-trip through JSON")
    func fingerprintCoding() throws {
        let fingerprint = VisualFingerprint(differenceHash: 0xFEDC_BA98_7654_3210, contrast: 0.42, featureVector: [3, 4])
        let data = try JSONEncoder().encode(fingerprint)
        let decoded = try JSONDecoder().decode(VisualFingerprint.self, from: data)
        #expect(decoded == fingerprint)
        #expect(decoded.featureVector == [0.6, 0.8])
    }
}
