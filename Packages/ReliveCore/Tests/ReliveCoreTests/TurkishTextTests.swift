import Foundation
import Testing
@testable import ReliveCore

@Suite("Turkish generated text")
struct TurkishTextTests {
    let tr = DeterministicEditorialTextProvider(language: .turkish)

    @Test("Recap chapters suffix places and keep nouns singular after numbers")
    func recap() {
        #expect(tr.text(for: .trip(name: "Kaş", days: 4, memories: 12, dateLabel: nil)).title == "Kaş'ta dört gün.")
        #expect(tr.text(for: .trip(name: "Bodrum", days: 1, memories: 3, dateLabel: nil)).title == "Bodrum'da bir gün.")
        #expect(tr.text(for: .monthOpening(monthName: "Ağustos", year: 2025, memories: 12, moments: 3, places: 1)).detail == "12 anı · 3 an · 1 yer")
        #expect(tr.text(for: .places(count: 5, isYear: true)).title == "Bu yıl beş yer.")
    }

    @Test("Turkish recap words make no claims")
    func factual() {
        let facts: [EditorialFacts] = [
            .favorites(count: 4), .people(count: 9), .closing(periodName: "Ağustos", isYear: false, memories: 9, moments: 2, places: 1),
            .busyDay(dateLabel: "8 Ağustos", memories: 20, places: 3), .yearOpening(year: 2025, memories: 80, moments: 20, months: 9),
        ]
        for fact in facts {
            for part in tr.text(for: fact).all {
                #expect(FactualTextPolicy.isFactual(part), "\(part)")
            }
        }
    }

    @Test("Counts and surprise ages in Turkish")
    func counts() {
        let words = CoreWords(language: .turkish)
        #expect(words.count(3, "memory", "memories") == "3 anı")
        #expect(words.count(1, "photo", "photos") == "1 fotoğraf")
        let surprise = SurpriseMemory(momentID: MomentID(), assetID: AssetID("a"), captureDate: Date(), anchor: .years(2), isSameDay: true, place: nil)
        #expect(surprise.ageDescription(in: .turkish) == "2 yıl önce bugün")
        #expect(surprise.ageDescription(in: .english) == "2 years ago today")
    }
}
