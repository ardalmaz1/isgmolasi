import Foundation
import Testing
@testable import ReliveCore

@Suite("MomentReconciler")
struct MomentReconcilerTests {
    func moment(key: String, assets: [AssetID], chapter: UUID? = nil) -> Moment {
        Moment(
            id: StableIdentifier.uuid(namespace: "event", key: key),
            kind: .event,
            assetIDs: assets,
            featuredAssetIDs: assets,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 1, 1),
            chapterID: chapter
        )
    }

    @Test("Adding an earlier photo keeps the moment's identity")
    func keepsIdentity() {
        let previous = Story(generatedAt: date(2025, 1, 2), moments: [moment(key: "b", assets: ["b", "c", "d"])], chapters: [])
        let chapterID = UUID()
        let regenerated = Story(
            generatedAt: date(2025, 2, 1),
            moments: [moment(key: "a", assets: ["a", "b", "c", "d"], chapter: chapterID)],
            chapters: [Chapter(id: chapterID, momentIDs: [StableIdentifier.uuid(namespace: "event", key: "a")], startDate: date(2025, 1, 1), endDate: date(2025, 1, 1))]
        )
        let reconciled = MomentReconciler().reconcile(new: regenerated, previous: previous)
        #expect(reconciled.moments[0].id == previous.moments[0].id)
        #expect(reconciled.chapters[0].momentIDs == [previous.moments[0].id])
    }

    @Test("A split moment keeps its id on the larger part and never duplicates ids")
    func split() {
        let previous = Story(generatedAt: date(2025, 1, 2), moments: [moment(key: "a", assets: ["a", "b", "c", "d", "e", "f"])], chapters: [])
        let regenerated = Story(generatedAt: date(2025, 2, 1), moments: [
            moment(key: "a", assets: ["a", "b"]),
            moment(key: "c", assets: ["c", "d", "e", "f"]),
        ], chapters: [])
        let reconciled = MomentReconciler().reconcile(new: regenerated, previous: previous)
        #expect(reconciled.moments[1].id == previous.moments[0].id)
        #expect(Set(reconciled.moments.map(\.id)).count == 2)
    }

    @Test("Unrelated moments get their own ids")
    func unrelated() {
        let previous = Story(generatedAt: date(2025, 1, 2), moments: [moment(key: "a", assets: ["a"])], chapters: [])
        let regenerated = Story(generatedAt: date(2025, 2, 1), moments: [moment(key: "z", assets: ["z"])], chapters: [])
        let reconciled = MomentReconciler().reconcile(new: regenerated, previous: previous)
        #expect(reconciled.moments[0].id == regenerated.moments[0].id)
    }
}
