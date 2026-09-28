import Foundation
import Testing
@testable import ReliveCore

@Suite("HeroSelector")
struct HeroSelectorTests {
    let selector = HeroSelector()
    let when = date(2025, 8, 7, 19, 0)

    @Test("A clear photo of two faces beats a blurry landscape")
    func facesWin() {
        let landscape = makeAsset("landscape", at: when, analysis: analysis(faces: 0, sharpness: 0.3, aesthetics: 0.6))
        let couple = makeAsset("couple", at: when.addingTimeInterval(60), analysis: analysis(faces: 2, faceQuality: 0.8, sharpness: 0.7, aesthetics: 0.6))
        #expect(selector.selectHero(among: [landscape, couple]) == "couple")
    }

    @Test("A favorite is a strong signal")
    func favoriteWins() {
        let great = makeAsset("great", at: when, analysis: analysis(faces: 2, faceQuality: 0.9, sharpness: 0.9, aesthetics: 0.9))
        let loved = makeAsset("loved", at: when.addingTimeInterval(60), favorite: true, analysis: analysis(faces: 1, faceQuality: 0.5, sharpness: 0.5, aesthetics: 0.5))
        #expect(selector.selectHero(among: [great, loved]) == "loved")
    }

    @Test("Receipts and screenshots are never preferred")
    func utilityPenalized() {
        let receipt = makeAsset("receipt", at: when, analysis: analysis(sharpness: 1, aesthetics: 1, utility: true))
        let screenshot = makeAsset("screenshot", at: when, traits: .screenshot, analysis: analysis(sharpness: 1, aesthetics: 1))
        let photo = makeAsset("photo", at: when.addingTimeInterval(60), analysis: analysis(sharpness: 0.4, aesthetics: 0.4))
        #expect(selector.selectHero(among: [receipt, screenshot, photo]) == "photo")
    }

    @Test("Weights are configurable")
    func weightsConfigurable() {
        let sharpOnly = HeroScoringWeights(
            faceQuality: 0, faceCount: 0, sharpness: 1, aesthetics: 0, resolution: 0, orientation: 0, uniqueness: 0
        )
        let custom = HeroSelector(scorer: AssetScorer(weights: sharpOnly))
        let faces = makeAsset("faces", at: when, analysis: analysis(faces: 2, faceQuality: 1, sharpness: 0.2))
        let sharp = makeAsset("sharp", at: when.addingTimeInterval(1), analysis: analysis(faces: 0, sharpness: 0.9))
        #expect(custom.selectHero(among: [faces, sharp]) == "sharp")
    }

    @Test("Missing analysis still produces a hero")
    func missingAnalysis() {
        let assets = [makeAsset("a", at: when), makeAsset("b", at: when.addingTimeInterval(5))]
        #expect(selector.selectHero(among: assets) == "a")
    }

    @Test("The user's cover choice wins while the photo exists")
    func userOverride() {
        let moment = Moment(
            id: UUID(), kind: .event, assetIDs: ["a", "b", "c"], featuredAssetIDs: ["a", "b", "c"],
            heroAssetID: "a", startDate: when, endDate: when
        )
        let state = MomentUserState(heroOverrideAssetID: "c")
        #expect(HeroSelector.resolvedHero(for: moment, userState: state) { _ in true } == "c")
        #expect(HeroSelector.resolvedHero(for: moment, userState: state) { $0 != "c" } == "a")
        #expect(HeroSelector.resolvedHero(for: moment, userState: nil) { $0 == "b" } == "b")
    }
}
