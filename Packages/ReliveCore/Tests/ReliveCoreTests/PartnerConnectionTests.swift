import Foundation
import Testing
@testable import ReliveCore

@Suite("Partner connection: rules and states")
struct PartnerConnectionTests {
    static func record(_ status: PartnerConnectionRecord.Status, role: PartnerRole = .owner) -> PartnerConnectionRecord {
        PartnerConnectionRecord(relationshipID: "R1", role: role, zoneName: RelationshipCloudFields.zoneName(for: "R1"), zoneOwnerName: "owner", status: status, createdAt: date(2026, 10, 22))
    }

    // MARK: Two people

    @Test func aRelationshipIsTwoPeople() {
        let owner = ParticipantSummary(isOwner: true, isCurrentUser: true, acceptance: .accepted)
        let invited = ParticipantSummary(isOwner: false, isCurrentUser: false, acceptance: .pending)
        let partner = ParticipantSummary(isOwner: false, isCurrentUser: false, acceptance: .accepted)
        let third = ParticipantSummary(isOwner: false, isCurrentUser: false, acceptance: .accepted)
        #expect(TwoPersonRule.occupancy([owner]) == .ownerOnly)
        #expect(TwoPersonRule.occupancy([owner, invited]) == .invited)
        #expect(TwoPersonRule.occupancy([owner, partner]) == .paired)
        #expect(TwoPersonRule.occupancy([owner, partner, third]) == .overfull)
        #expect(TwoPersonRule.mayInvite([owner]))
        #expect(TwoPersonRule.mayInvite([owner, invited]))
        #expect(!TwoPersonRule.mayInvite([owner, partner]), "a full relationship can't invite anyone else")
        #expect(TwoPersonRule.occupancy([owner, ParticipantSummary(isOwner: false, isCurrentUser: false, acceptance: .removed)]) == .ownerOnly)
    }

    @Test func aThirdPersonCantJoin() {
        let owner = ParticipantSummary(isOwner: true, isCurrentUser: false, acceptance: .accepted)
        let me = ParticipantSummary(isOwner: false, isCurrentUser: true, acceptance: .pending)
        let partner = ParticipantSummary(isOwner: false, isCurrentUser: false, acceptance: .accepted)
        #expect(TwoPersonRule.mayAccept([owner, me]))
        #expect(!TwoPersonRule.mayAccept([owner, partner, me]), "someone else already joined")
        // Opening the invitation again after joining is fine.
        #expect(TwoPersonRule.mayAccept([owner, ParticipantSummary(isOwner: false, isCurrentUser: true, acceptance: .accepted)]))
    }

    // MARK: States

    @Test func soloIsTheDefault() {
        #expect(PartnerConnectionState.fromMemory(nil) == .notConnected)
        #expect(!PartnerConnectionState.notConnected.hasRelationship)
    }

    @Test func memoryShowsTheStateWithoutAskingICloud() {
        #expect(PartnerConnectionState.fromMemory(Self.record(.waitingForPartner)) == .waitingForPartner(isOffline: false))
        #expect(PartnerConnectionState.fromMemory(Self.record(.connected, role: .partner)) == .connected(role: .partner, isOffline: false))
    }

    @Test func offlineIsStillConnected() {
        let connected = Self.record(.connected)
        let offline = PartnerConnectionState.afterRefreshFailure(.networkUnavailable, record: connected)
        #expect(offline == .connected(role: .owner, isOffline: true))
        #expect(offline.hasRelationship, "connected but offline is not disconnected")
        #expect(PartnerConnectionState.afterRefreshFailure(.serviceUnavailable, record: Self.record(.waitingForPartner)) == .waitingForPartner(isOffline: true))
    }

    @Test func aMissingRelationshipEndsTheConnectionHonestly() {
        #expect(PartnerConnectionState.afterRefreshFailure(.notFound, record: Self.record(.connected, role: .partner)) == .ended(.connectionEnded(byPartner: true)))
        #expect(PartnerConnectionState.afterRefreshFailure(.notFound, record: Self.record(.waitingForPartner)) == .ended(.connectionEnded(byPartner: false)))
        #expect(PartnerConnectionState.afterRefreshFailure(.accountChanged, record: Self.record(.connected)) == .ended(.accountChanged))
        #expect(PartnerConnectionState.afterRefreshFailure(.notSignedIn, record: Self.record(.connected)) == .iCloudUnavailable(.signInToICloud))
        #expect(PartnerConnectionState.afterRefreshFailure(.networkUnavailable, record: nil) == .notConnected)
    }

    // MARK: Words

    @Test func everyAccountStateHasCalmWords() {
        #expect(PartnerMessage.forAccount(.available) == nil)
        #expect(PartnerMessage.forAccount(.noAccount) == .signInToICloud)
        #expect(PartnerMessage.forAccount(.restricted) == .iCloudRestricted)
        #expect(PartnerMessage.forAccount(.couldNotDetermine) == .iCloudUnknown)
        #expect(PartnerMessage.forAccount(.temporarilyUnavailable) == .temporarilyUnavailable)
    }

    @Test func noMessageMentionsCloudKitOrErrorCodes() {
        let failures: [CloudFailure] = [.networkUnavailable, .serviceUnavailable, .notSignedIn, .accountChanged, .quotaExceeded, .notFound, .relationshipFull, .alreadyConnected, .permissionDenied, .unknown]
        var messages = failures.map(PartnerMessage.forFailure)
        messages += [.iCloudRestricted, .iCloudUnknown, .connectionEnded(byPartner: true), .connectionEnded(byPartner: false), .joined]
        for message in messages {
            for word in ["CloudKit", "CKShare", "zone", "record", "container", "subscription", "error", "code"] {
                #expect(!message.text.localizedCaseInsensitiveContains(word), "\(message.text)")
            }
        }
        #expect(PartnerMessage.forFailure(.relationshipFull).text == "This Yuvi relationship already has two people.")
        #expect(PartnerMessage.forFailure(.networkUnavailable).text == "Yuvi couldn’t reach iCloud. Try again.")
        #expect(CloudFailure.networkUnavailable.isTemporary && CloudFailure.serviceUnavailable.isTemporary)
        #expect(!CloudFailure.notFound.isTemporary)
    }

    // MARK: Memory

    @Test func theConnectionMemoryRoundTrips() throws {
        let record = Self.record(.connected, role: .partner)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(PartnerConnectionRecord.self, from: data) == record)
        let json = String(decoding: data, as: UTF8.self)
        for word in ["localIdentifier", "latitude", "fingerprint", "face", "asset", "photo"] {
            #expect(!json.localizedCaseInsensitiveContains(word))
        }
    }
}

@Suite("Partner connection: what reaches iCloud")
struct RelationshipPrivacyBoundaryTests {
    @Test func theRelationshipRecordCarriesOnlyItsAllowlist() {
        let fields = RelationshipCloudFields(relationshipID: "R1", createdAt: date(2026, 10, 22))
        #expect(Set(fields.values.keys) == RelationshipCloudFields.allowedKeys)
        #expect(RelationshipCloudFields.allowedKeys == ["relationshipID", "createdAt", "schemaVersion"])
    }

    @Test func nothingFromTheLibraryCanBeAField() {
        let forbidden = ["localIdentifier", "assetID", "latitude", "longitude", "location", "place", "fingerprint", "faceCount", "hidden", "notSuggested", "analysis", "photo", "image", "name"]
        for key in RelationshipCloudFields.allowedKeys {
            for word in forbidden {
                #expect(!key.localizedCaseInsensitiveContains(word), "\(key) looks like \(word)")
            }
        }
    }

    @Test func eachRelationshipHasItsOwnSpace() {
        #expect(RelationshipCloudFields.zoneName(for: "R1") == "Relationship-R1")
        #expect(RelationshipCloudFields.zoneName(for: "R1") != RelationshipCloudFields.zoneName(for: "R2"))
    }
}
