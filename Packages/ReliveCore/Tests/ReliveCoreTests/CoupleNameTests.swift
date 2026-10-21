import Foundation
import Testing
@testable import ReliveCore

/// "Arda ♥ Kübra" everywhere, read aloud as "Arda and Kübra"; never "Arda + Kübra".
@Suite("Couple name presentation")
struct CoupleNameTests {
    @Test func bothNamesAreJoinedByAQuietHeart() {
        let name = CoupleName(userName: "Arda", partnerName: "Kübra")
        #expect(name.display() == "Arda \u{2665} Kübra")
        #expect(name.spoken() == "Arda and Kübra")
        #expect(name.plain() == "Arda & Kübra")
        #expect(name.hasBothNames)
        #expect(!name.display().contains("+"))
        #expect(!name.display().contains("\u{2764}"), "the typographic heart, not the red emoji")
    }

    @Test func withoutTheUsersNameTheUserIsYou() {
        let name = CoupleName(userName: nil, partnerName: "Kübra")
        #expect(name.display() == "You \u{2665} Kübra")
        #expect(name.spoken() == "You and Kübra")
        #expect(!name.hasBothNames)
        #expect(CoupleName(userName: "   ", partnerName: "Kübra").userName == nil)
    }

    @Test func namesAreTrimmedAndAnEmptyPartnerLeavesTheLead() {
        #expect(CoupleName(userName: " Arda ", partnerName: " Kübra\n").display() == "Arda \u{2665} Kübra")
        #expect(CoupleName(userName: "Arda", partnerName: "  ").display() == "Arda")
        #expect(CoupleName(userName: "Arda", partnerName: "").spoken() == "Arda")
    }

    @Test func anyNamesWork() {
        for (a, b) in [("Jake", "Emma"), ("Şule", "İlkay"), ("María José", "Ølsen"), ("李", "王")] {
            let name = CoupleName(userName: a, partnerName: b)
            #expect(name.display() == "\(a) \u{2665} \(b)")
            #expect(name.spoken() == "\(a) and \(b)")
        }
    }

    @Test func theProfileUsesTheSameRule() {
        #expect(RelationshipProfile(partnerName: "Kübra", userName: "Arda").coupleDisplayName == "Arda \u{2665} Kübra")
        #expect(RelationshipProfile(partnerName: "Kübra", userName: "Arda").coupleName.spoken() == "Arda and Kübra")
    }

    @Test func localizedWordsCanBeSupplied() {
        let name = CoupleName(userName: nil, partnerName: "Kübra")
        #expect(name.display(you: "Sen") == "Sen \u{2665} Kübra")
        #expect(name.spoken(you: "Sen", spokenJoiner: "ve") == "Sen ve Kübra")
    }
}
