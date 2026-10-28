import CloudKit
import ReliveCore
import SwiftData
import XCTest
@testable import Relive

// Phase B — the partner connection through the real PartnerConnectionModel with a scripted
// iCloud (FakePartnerCloudService). Nothing here talks to CloudKit; two-iPhone behaviour is in
// docs/COUPLES_DEVICE_TEST_PLAN.md.

@MainActor
final class PartnerConnectionAppTests: XCTestCase {
    private var fake: FakePartnerCloudService!
    private var cache: InMemoryPartnerConnectionCache!
    private var analytics: InMemoryAnalyticsTracker!
    private var registrations = 0
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        fake = FakePartnerCloudService()
        cache = InMemoryPartnerConnectionCache()
        analytics = InMemoryAnalyticsTracker()
        registrations = 0
    }

    private func model() -> PartnerConnectionModel {
        PartnerConnectionModel(cache: cache, analytics: analytics, now: { [now] in now }, onRelationship: { [weak self] in self?.registrations += 1 }) { [fake] in fake! }
    }

    private func remembered(_ status: PartnerConnectionRecord.Status, role: PartnerRole = .owner) -> PartnerConnectionRecord {
        PartnerConnectionRecord(relationshipID: "R0", role: role, zoneName: "Relationship-R0", zoneOwnerName: role == .owner ? "__defaultOwner__" : "owner", status: status, createdAt: now, lastConfirmedAt: now)
    }

    private var eventNames: [AnalyticsEventName] { analytics.events.map(\.name) }

    // MARK: Solo

    func testSoloUsersNeverReachICloud() async {
        let partner = model()
        XCTAssertEqual(partner.state, .notConnected)
        await partner.refresh()
        await partner.cloudDidChange()
        await partner.disconnect()
        XCTAssertFalse(partner.hasUsedICloud, "a solo user must never create the iCloud service")
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertEqual(registrations, 0, "no silent-update registration without a partner")
        XCTAssertEqual(partner.state, .notConnected)
    }

    // MARK: Inviting

    func testConnectCreatesTheRelationshipAndWaits() async {
        let partner = model()
        await partner.connect()
        XCTAssertEqual(fake.calls.prefix(2), ["accountStatus", "createRelationship"])
        XCTAssertTrue(fake.calls.contains("sharingPresentation"), "Apple's invitation screen is offered")
        XCTAssertEqual(partner.state, .waitingForPartner(isOffline: false))
        XCTAssertEqual(cache.record?.status, .waitingForPartner)
        XCTAssertEqual(cache.record?.role, .owner)
        XCTAssertEqual(fake.subscribed.count, 1, "silent change updates are requested")
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(Array(eventNames.prefix(2)), [.partnerConnectStarted, .partnerInvitationCreated])
    }

    func testConnectingAgainReusesTheWaitingRelationship() async {
        let partner = model()
        await partner.connect()
        await partner.connect()
        XCTAssertEqual(fake.created.count, 1, "the waiting relationship is reused, not duplicated")
        XCTAssertEqual(fake.calls.filter { $0 == "sharingPresentation" }.count, 2)
    }

    func testEveryICloudAccountStateHasAWayBackToSolo() async {
        for (account, message) in [(CloudAccountAvailability.noAccount, PartnerMessage.signInToICloud),
                                   (.restricted, .iCloudRestricted),
                                   (.couldNotDetermine, .iCloudUnknown),
                                   (.temporarilyUnavailable, .temporarilyUnavailable)] {
            fake = FakePartnerCloudService(account: account)
            cache = InMemoryPartnerConnectionCache()
            let partner = model()
            await partner.connect()
            XCTAssertEqual(partner.state, .iCloudUnavailable(message), "\(account)")
            XCTAssertFalse(fake.calls.contains("createRelationship"), "nothing is created without iCloud (\(account))")
            XCTAssertNil(cache.record)
            partner.acknowledge()
            XCTAssertEqual(partner.state, .notConnected, "solo Relive carries on (\(account))")
        }
    }

    func testAFailedCreateShowsACalmMessage() async {
        fake.createFailure = .networkUnavailable
        let partner = model()
        await partner.connect()
        XCTAssertEqual(partner.state, .failed(.couldNotReachICloud))
        XCTAssertEqual(PartnerMessage.couldNotReachICloud.text, "Relive couldn’t reach iCloud. Try again.")
        XCTAssertNil(cache.record)
        XCTAssertEqual(analytics.events.last?.name, .partnerConnectFailed)
        XCTAssertEqual(analytics.events.last?.properties["reason"], "network")
    }

    func testTheInvitationIsNotOfferedOncePaired() async {
        cache.record = remembered(.waitingForPartner)
        fake.occupancyResult = .success(.paired)
        let partner = model()
        await partner.presentInvitation()
        XCTAssertFalse(fake.calls.contains("sharingPresentation"), "a full relationship can't invite anyone else")
        XCTAssertEqual(partner.state, .connected(role: .owner, isOffline: false))
        XCTAssertEqual(cache.record?.status, .connected)
    }

    // MARK: Memory and offline

    func testTheConnectionIsRememberedWithoutAskingICloud() {
        cache.record = remembered(.connected)
        let partner = model()
        XCTAssertEqual(partner.state, .connected(role: .owner, isOffline: false))
        XCTAssertFalse(partner.hasUsedICloud)
        XCTAssertEqual(registrations, 1, "a remembered relationship keeps receiving silent updates")
    }

    func testOfflineStaysConnected() async {
        cache.record = remembered(.connected, role: .partner)
        fake.occupancyResult = .failure(.networkUnavailable)
        let partner = model()
        await partner.refresh()
        XCTAssertEqual(partner.state, .connected(role: .partner, isOffline: true))
        XCTAssertEqual(cache.record?.status, .connected, "offline never forgets the connection")
        fake.occupancyResult = .success(.paired)
        await partner.refresh()
        XCTAssertEqual(partner.state, .connected(role: .partner, isOffline: false))
    }

    func testRefreshConfirmsAndStampsTheLastSync() async {
        let earlier = now.addingTimeInterval(-3600)
        var record = remembered(.waitingForPartner)
        record.lastConfirmedAt = earlier
        cache.record = record
        fake.occupancyResult = .success(.paired)
        let partner = model()
        await partner.refresh()
        XCTAssertEqual(partner.state, .connected(role: .owner, isOffline: false), "the partner accepted")
        XCTAssertEqual(partner.lastSyncedAt, now)
    }

    func testTheFileMemorySurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "partner-\(UUID().uuidString)").appending(path: "PartnerConnection.json")
        let file = FilePartnerConnectionCache(url: url)
        XCTAssertNil(file.load())
        file.save(remembered(.connected))
        XCTAssertEqual(FilePartnerConnectionCache(url: url).load(), remembered(.connected))
        let json = try String(contentsOf: url, encoding: .utf8)
        for word in ["localIdentifier", "latitude", "longitude", "fingerprint", "face", "hidden", "Kübra", "Arda"] {
            XCTAssertFalse(json.contains(word), "the connection memory holds identifiers only (\(word))")
        }
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        file.save(nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Ending

    func testTheOwnerEndingItShowsOnThePartnersIPhone() async {
        cache.record = remembered(.connected, role: .partner)
        fake.occupancyResult = .failure(.notFound)
        let partner = model()
        await partner.refresh()
        XCTAssertEqual(partner.state, .ended(.connectionEnded(byPartner: true)))
        XCTAssertNil(cache.record)
        XCTAssertTrue(fake.ended.isEmpty, "the partner never deletes the owner's relationship")
        partner.acknowledge()
        XCTAssertEqual(partner.state, .notConnected)
    }

    func testThePartnerLeavingEndsItForTheOwner() async {
        cache.record = remembered(.connected)
        fake.occupancyResult = .success(.ownerOnly)
        let partner = model()
        await partner.refresh()
        XCTAssertEqual(partner.state, .ended(.connectionEnded(byPartner: true)))
        XCTAssertEqual(fake.ended.map(\.relationshipID), ["R0"], "the owner's leftover relationship is removed")
        XCTAssertNil(cache.record)
    }

    func testStoppingSharingFromApplesScreenIsNotBlamedOnThePartner() async {
        cache.record = remembered(.waitingForPartner)
        let presentation = RecordingPresentation()
        fake.presentation = presentation
        let partner = model()
        await partner.presentInvitation()
        XCTAssertEqual(presentation.presented, 1)
        fake.occupancyResult = .failure(.notFound)
        presentation.change()
        try? await PremiumTestKit.wait { partner.record == nil }
        XCTAssertEqual(partner.state, .ended(.connectionEnded(byPartner: false)))
        XCTAssertEqual(fake.ended.count, 1, "the leftover space is removed")
    }

    func testDisconnectAsOwnerAndAsPartner() async {
        for role in [PartnerRole.owner, .partner] {
            fake = FakePartnerCloudService()
            cache = InMemoryPartnerConnectionCache(remembered(.connected, role: role))
            let partner = model()
            await partner.disconnect()
            XCTAssertEqual(partner.state, .notConnected)
            XCTAssertNil(cache.record)
            XCTAssertEqual(fake.ended.map(\.role), [role])
            XCTAssertEqual(analytics.events.last?.properties["role"], role.rawValue)
        }
    }

    func testAFailedDisconnectKeepsTheConnection() async {
        cache.record = remembered(.connected)
        fake.endFailure = .networkUnavailable
        let partner = model()
        await partner.disconnect()
        XCTAssertEqual(partner.state, .connected(role: .owner, isOffline: false))
        XCTAssertNotNil(cache.record, "nothing is forgotten when iCloud couldn't be reached")
        XCTAssertEqual(partner.notice, .couldNotReachICloud)
    }

    func testSignedOutIsNotDisconnected() async {
        cache.record = remembered(.connected)
        fake.occupancyResult = .failure(.notSignedIn)
        let partner = model()
        await partner.refresh()
        XCTAssertEqual(partner.state, .iCloudUnavailable(.signInToICloud))
        XCTAssertNotNil(cache.record, "signing back in restores the connection")
        partner.acknowledge()
        XCTAssertEqual(partner.state, .connected(role: .owner, isOffline: false))
    }

    // MARK: Accepting

    func testAcceptingAnInvitation() async {
        let partner = model()
        await partner.accept(FakePartnerCloudService.invitation())
        XCTAssertEqual(partner.state, .connected(role: .partner, isOffline: false))
        XCTAssertEqual(cache.record?.role, .partner)
        XCTAssertEqual(partner.notice, .joined)
        XCTAssertEqual(fake.subscribed.count, 1)
        XCTAssertEqual(eventNames.last, .partnerJoined)
    }

    func testAThirdPersonIsRefused() async {
        let partner = model()
        let full = FakePartnerCloudService.invitation(participants: [
            ParticipantSummary(isOwner: true, isCurrentUser: false, acceptance: .accepted),
            ParticipantSummary(isOwner: false, isCurrentUser: false, acceptance: .accepted),
            ParticipantSummary(isOwner: false, isCurrentUser: true, acceptance: .pending),
        ])
        await partner.accept(full)
        XCTAssertFalse(fake.calls.contains("accept"), "a full relationship is never joined")
        XCTAssertEqual(partner.notice, .relationshipFull)
        XCTAssertEqual(PartnerMessage.relationshipFull.text, "This Relive relationship already has two people.")
        XCTAssertEqual(partner.state, .notConnected)
    }

    func testAnotherInvitationWhileConnectedIsRefused() async {
        cache.record = remembered(.connected)
        let partner = model()
        await partner.accept(FakePartnerCloudService.invitation(zoneName: "Relationship-other"))
        XCTAssertEqual(partner.notice, .alreadyConnected)
        XCTAssertFalse(fake.calls.contains("accept"))
        XCTAssertEqual(cache.record?.relationshipID, "R0")
    }

    func testOpeningYourOwnInvitationJustRefreshes() async {
        cache.record = remembered(.waitingForPartner)
        let partner = model()
        await partner.accept(FakePartnerCloudService.invitation(zoneName: "Relationship-R0", fromCurrentUser: true))
        XCTAssertFalse(fake.calls.contains("accept"))
        XCTAssertEqual(fake.calls, ["occupancy"])
    }

    func testJoiningReplacesYourOwnUnansweredInvitation() async {
        cache.record = remembered(.waitingForPartner)
        let partner = model()
        await partner.accept(FakePartnerCloudService.invitation())
        XCTAssertEqual(fake.ended.map(\.relationshipID), ["R0"], "the empty invitation is removed")
        XCTAssertEqual(cache.record?.role, .partner)
    }

    func testAFailedAcceptLeavesYouAsYouWere() async {
        fake.acceptFailure = .notFound
        let partner = model()
        await partner.accept(FakePartnerCloudService.invitation())
        XCTAssertEqual(partner.state, .notConnected)
        XCTAssertEqual(partner.notice, .invitationEnded)
        XCTAssertNil(cache.record)
    }

    func testInvitationsArrivingBeforeTheModelAreKept() async throws {
        let inbox = PartnerInbox()
        inbox.deliver(FakePartnerCloudService.invitation())
        let partner = model()
        inbox.attach(partner)
        try await PremiumTestKit.wait { partner.record != nil }
        XCTAssertEqual(partner.state, .connected(role: .partner, isOffline: false))
    }

    // MARK: Errors and words

    func testCloudKitErrorsBecomeRelivesOwn() {
        let cases: [(CKError.Code, CloudFailure)] = [
            (.networkUnavailable, .networkUnavailable),
            (.networkFailure, .networkUnavailable),
            (.serviceUnavailable, .serviceUnavailable),
            (.requestRateLimited, .serviceUnavailable),
            (.zoneBusy, .serviceUnavailable),
            (.notAuthenticated, .notSignedIn),
            (.quotaExceeded, .quotaExceeded),
            (.zoneNotFound, .notFound),
            (.unknownItem, .notFound),
            (.userDeletedZone, .notFound),
            (.tooManyParticipants, .relationshipFull),
            (.permissionFailure, .permissionDenied),
            (.internalError, .unknown),
        ]
        for (code, expected) in cases {
            XCTAssertEqual(CloudKitPartnerService.failure(from: CKError(code)), expected, "\(code)")
        }
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["zone": CKError(.quotaExceeded)]])
        XCTAssertEqual(CloudKitPartnerService.failure(from: partial), .quotaExceeded)
        XCTAssertEqual(CloudKitPartnerService.failure(from: URLError(.notConnectedToInternet)), .networkUnavailable)
    }

    /// An all-or-nothing save reports the real cause on one item and "batch failed" on the rest
    /// (seen when TestFlight saved a record type missing from the Production schema). The real
    /// cause must win, whatever order the dictionary returns.
    func testTheRealCauseWinsOverBatchFailed() {
        let real = CKError(.quotaExceeded)
        let batch = CKError(.batchRequestFailed)
        XCTAssertEqual((CloudKitPartnerService.mostInformative([batch, real]) as? CKError)?.code, .quotaExceeded)
        XCTAssertEqual((CloudKitPartnerService.mostInformative([real, batch]) as? CKError)?.code, .quotaExceeded)
        XCTAssertEqual((CloudKitPartnerService.mostInformative([batch]) as? CKError)?.code, .batchRequestFailed)
        XCTAssertNil(CloudKitPartnerService.mostInformative([]))
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["share": batch, "relationship": real]])
        XCTAssertEqual(CloudKitPartnerService.failure(from: partial), .quotaExceeded)
        // A record type missing from the schema is not something the user can fix: calm, generic.
        XCTAssertEqual(CloudKitPartnerService.failure(from: CKError(.serverRejectedRequest)), .unknown)
    }

    /// Diagnostics carry error codes only — never record names, zones or anything personal.
    func testDiagnosticsAreCodesOnly() {
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["Relationship-ABC": CKError(.serverRejectedRequest), "share": CKError(.batchRequestFailed)]])
        XCTAssertEqual(CloudKitPartnerService.diagnosticCodes(partial), "CKError 2 (partial: 15, 22)")
        XCTAssertEqual(CloudKitPartnerService.diagnosticCodes(CKError(.notAuthenticated)), "CKError 9")
        XCTAssertFalse(CloudKitPartnerService.diagnosticCodes(partial).contains("Relationship"))
    }

    func testNoMessageShowsTechnicalWords() {
        let messages: [PartnerMessage] = [.signInToICloud, .iCloudRestricted, .iCloudUnknown, .couldNotReachICloud, .temporarilyUnavailable, .relationshipFull, .alreadyConnected, .iCloudFull, .invitationEnded, .connectionEnded(byPartner: true), .connectionEnded(byPartner: false), .accountChanged, .somethingWentWrong, .joined]
        for message in messages {
            for word in ["CloudKit", "CKShare", "zone", "container", "subscription", "CKError", "record"] {
                XCTAssertFalse(message.text.localizedCaseInsensitiveContains(word), message.text)
            }
        }
    }

    // MARK: Names and privacy

    func testCoupleNamesStayLocalAndAuthoritative() async {
        let couple = CoupleName(userName: "Arda", partnerName: "Kübra")
        let partner = model()
        await partner.connect()
        await partner.accept(FakePartnerCloudService.invitation(zoneName: "Relationship-other"))
        XCTAssertEqual(couple.display(), "Arda \u{2665} Kübra", "the couple name is unchanged by connecting")
        // The connection memory has no name of anyone.
        let labels = Mirror(reflecting: cache.record!).children.compactMap(\.label)
        XCTAssertEqual(Set(labels), ["relationshipID", "role", "zoneName", "zoneOwnerName", "status", "createdAt", "lastConfirmedAt"])
    }

    /// The app has an iCloud entitlement now; the local story store must still never be mirrored
    /// to iCloud (SwiftData's default with that entitlement).
    func testTheStoryStoreNeverSyncsToICloud() {
        let schema = Schema(PersistenceSchema.models)
        for inMemory in [true, false] {
            let configuration = SwiftDataStoryRepository.storeConfiguration(schema: schema, inMemory: inMemory)
            XCTAssertNil(configuration.cloudKitContainerIdentifier, "the story store is local only")
        }
        let container = SwiftDataStoryRepository.makeContainer(inMemory: true)
        XCTAssertTrue(container.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    }

    func testOnlyTheAllowlistReachesICloud() {
        let fields = RelationshipCloudFields(relationshipID: "R1", createdAt: now)
        XCTAssertEqual(Set(fields.values.keys), ["relationshipID", "createdAt", "schemaVersion"])
    }
}

/// Stands in for Apple's sharing screen.
@MainActor
private final class RecordingPresentation: PartnerSharingPresentation {
    private(set) var presented = 0
    private var onChange: (@MainActor () -> Void)?

    func present(onChange: @escaping @MainActor () -> Void) {
        presented += 1
        self.onChange = onChange
    }

    func change() {
        onChange?()
    }
}
