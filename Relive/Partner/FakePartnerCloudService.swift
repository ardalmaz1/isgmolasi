#if DEBUG
import Foundation
import ReliveCore

/// A scripted iCloud for hosted tests and UI tests. Never used in Release builds.
@MainActor
final class FakePartnerCloudService: PartnerCloudService {
    var account: CloudAccountAvailability = .available
    var createFailure: CloudFailure?
    var occupancyResult: Result<TwoPersonRule.Occupancy, CloudFailure> = .success(.ownerOnly)
    var acceptFailure: CloudFailure?
    var endFailure: CloudFailure?
    var presentation: (any PartnerSharingPresentation)?

    private(set) var calls: [String] = []
    private(set) var created: [PartnerConnectionRecord] = []
    private(set) var ended: [PartnerConnectionRecord] = []
    private(set) var subscribed: [PartnerConnectionRecord] = []

    init(account: CloudAccountAvailability = .available) {
        self.account = account
    }

    func accountStatus() async -> CloudAccountAvailability {
        calls.append("accountStatus")
        return account
    }

    func createRelationship(now: Date) async throws -> PartnerConnectionRecord {
        calls.append("createRelationship")
        if let createFailure { throw createFailure }
        let id = "R\(created.count + 1)"
        let record = PartnerConnectionRecord(relationshipID: id, role: .owner, zoneName: RelationshipCloudFields.zoneName(for: id), zoneOwnerName: "__defaultOwner__", status: .waitingForPartner, createdAt: now, lastConfirmedAt: now)
        created.append(record)
        return record
    }

    func occupancy(of record: PartnerConnectionRecord) async throws -> TwoPersonRule.Occupancy {
        calls.append("occupancy")
        return try occupancyResult.get()
    }

    func sharingPresentation(for record: PartnerConnectionRecord) async throws -> (any PartnerSharingPresentation)? {
        calls.append("sharingPresentation")
        return presentation
    }

    func accept(_ invitation: PartnerInvitation, now: Date) async throws -> PartnerConnectionRecord {
        calls.append("accept")
        if let acceptFailure { throw acceptFailure }
        guard TwoPersonRule.mayAccept(invitation.participants) else { throw CloudFailure.relationshipFull }
        return PartnerConnectionRecord(relationshipID: "joined", role: .partner, zoneName: invitation.zoneName, zoneOwnerName: "owner", status: .connected, createdAt: now, lastConfirmedAt: now)
    }

    func endRelationship(_ record: PartnerConnectionRecord) async throws {
        calls.append("endRelationship")
        if let endFailure { throw endFailure }
        ended.append(record)
    }

    func ensureChangeSubscription(for record: PartnerConnectionRecord) async {
        calls.append("ensureChangeSubscription")
        subscribed.append(record)
    }

    /// An invitation as the system would hand it over.
    static func invitation(zoneName: String = "Relationship-invite", participants: [ParticipantSummary]? = nil, fromCurrentUser: Bool = false) -> PartnerInvitation {
        PartnerInvitation(
            participants: participants ?? [
                ParticipantSummary(isOwner: true, isCurrentUser: false, acceptance: .accepted),
                ParticipantSummary(isOwner: false, isCurrentUser: true, acceptance: .pending),
            ],
            containerIdentifier: CloudKitPartnerService.containerIdentifier,
            zoneName: zoneName,
            isFromCurrentUser: fromCurrentUser,
            systemMetadata: nil
        )
    }
}

extension AppEnvironment {
    /// UI tests: `-RelivePartnerFake noAccount|available|waiting|connected|partner` replaces iCloud
    /// with `FakePartnerCloudService` and an in-memory connection memory.
    static func partnerForUITests(analytics: any AnalyticsTracking) -> PartnerConnectionModel? {
        guard let mode = UserDefaults.standard.string(forKey: "RelivePartnerFake") else { return nil }
        let fake = FakePartnerCloudService(account: mode == "noAccount" ? .noAccount : .available)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var memory: PartnerConnectionRecord?
        switch mode {
        case "waiting":
            memory = PartnerConnectionRecord(relationshipID: "R0", role: .owner, zoneName: "Relationship-R0", zoneOwnerName: "__defaultOwner__", status: .waitingForPartner, createdAt: start, lastConfirmedAt: start)
        case "connected":
            memory = PartnerConnectionRecord(relationshipID: "R0", role: .owner, zoneName: "Relationship-R0", zoneOwnerName: "__defaultOwner__", status: .connected, createdAt: start, lastConfirmedAt: start)
            fake.occupancyResult = .success(.paired)
        case "partner":
            memory = PartnerConnectionRecord(relationshipID: "R0", role: .partner, zoneName: "Relationship-R0", zoneOwnerName: "owner", status: .connected, createdAt: start, lastConfirmedAt: start)
            fake.occupancyResult = .success(.paired)
        default:
            break
        }
        return PartnerConnectionModel(cache: InMemoryPartnerConnectionCache(memory), analytics: analytics) { fake }
    }
}
#endif
