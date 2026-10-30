import CloudKit
import os
import ReliveCore
import UIKit

/// The real partner connection, on Apple's CloudKit. One custom zone per relationship in the
/// owner's private database holds a single `Relationship` record (see `RelationshipCloudFields` —
/// the allowlist is the privacy boundary), shared with the partner as a zone-wide `CKShare`.
///
/// The container is created on first use only, so a solo user who never taps Connect never
/// talks to iCloud.
@MainActor
final class CloudKitPartnerService: PartnerCloudService {
    static let containerIdentifier = "iCloud.com.ardaalmaz.reliveapp"
    private static let subscriptionID = "relive-relationship-changes"
    nonisolated private static let logger = Logger(subsystem: "app.relive", category: "partner")

    private var _container: CKContainer?
    private var container: CKContainer {
        if let _container { return _container }
        let made = CKContainer(identifier: Self.containerIdentifier)
        _container = made
        return made
    }

    /// Kept alive while Apple's sharing screen is up.
    private var activePresentation: CloudSharingPresentation?

    // MARK: Account

    func accountStatus() async -> CloudAccountAvailability {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .couldNotDetermine
            @unknown default: return .couldNotDetermine
            }
        } catch {
            Self.logDiagnostics(error, step: "accountStatus")
            return .couldNotDetermine
        }
    }

    // MARK: Owner

    func createRelationship(now: Date) async throws -> PartnerConnectionRecord {
        let relationshipID = UUID().uuidString
        let zone = CKRecordZone(zoneName: RelationshipCloudFields.zoneName(for: relationshipID))
        let database = container.privateCloudDatabase
        do {
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

            let fields = RelationshipCloudFields(relationshipID: relationshipID, createdAt: now)
            let record = CKRecord(recordType: RelationshipCloudFields.recordType, recordID: CKRecord.ID(recordName: relationshipID, zoneID: zone.zoneID))
            for (key, value) in fields.values {
                switch value {
                case .string(let string): record[key] = string as NSString
                case .date(let date): record[key] = date as NSDate
                case .int(let int): record[key] = NSNumber(value: int)
                }
            }

            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = String(localized: "Yuvi") as NSString
            share.publicPermission = .none

            let result = try await database.modifyRecords(saving: [record, share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            if let error = Self.mostInformative(result.saveResults.values.compactMap(\.failureValue)) { throw error }
        } catch {
            Self.logDiagnostics(error, step: "createRelationship")
            // Don't leave a half-made space behind.
            _ = try? await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            throw Self.failure(from: error)
        }
        return PartnerConnectionRecord(
            relationshipID: relationshipID,
            role: .owner,
            zoneName: zone.zoneID.zoneName,
            zoneOwnerName: zone.zoneID.ownerName,
            status: .waitingForPartner,
            createdAt: now,
            lastConfirmedAt: now
        )
    }

    func occupancy(of record: PartnerConnectionRecord) async throws -> TwoPersonRule.Occupancy {
        let share = try await fetchShare(for: record)
        return TwoPersonRule.occupancy(Self.participants(of: share))
    }

    func sharingPresentation(for record: PartnerConnectionRecord) async throws -> (any PartnerSharingPresentation)? {
        guard record.role == .owner else { return nil }
        let share = try await fetchShare(for: record)
        let presentation = CloudSharingPresentation(share: share, container: container) { [weak self] in
            self?.activePresentation = nil
        }
        activePresentation = presentation
        return presentation
    }

    // MARK: Partner

    func accept(_ invitation: PartnerInvitation, now: Date) async throws -> PartnerConnectionRecord {
        guard invitation.containerIdentifier == Self.containerIdentifier,
              let metadata = invitation.systemMetadata as? CKShare.Metadata else {
            throw CloudFailure.notFound
        }
        guard TwoPersonRule.mayAccept(invitation.participants) else { throw CloudFailure.relationshipFull }
        let share: CKShare
        do {
            share = try await container.accept(metadata)
        } catch {
            Self.logDiagnostics(error, step: "accept")
            throw Self.failure(from: error)
        }
        let zoneID = share.recordID.zoneID
        let prefix = RelationshipCloudFields.zoneName(for: "")
        let relationshipID = zoneID.zoneName.hasPrefix(prefix) ? String(zoneID.zoneName.dropFirst(prefix.count)) : zoneID.zoneName
        return PartnerConnectionRecord(
            relationshipID: relationshipID,
            role: .partner,
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            status: .connected,
            createdAt: now,
            lastConfirmedAt: now
        )
    }

    // MARK: Ending

    func endRelationship(_ record: PartnerConnectionRecord) async throws {
        do {
            switch record.role {
            case .owner:
                // Deleting the zone deletes its share too: the partner loses access.
                let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [Self.zoneID(for: record)])
                if let error = Self.mostInformative(result.deleteResults.values.compactMap(\.failureValue)) { throw error }
            case .partner:
                // A participant leaves by deleting the share from their shared database; the
                // owner's zone and record stay in the owner's iCloud.
                let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: Self.zoneID(for: record))
                let result = try await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
                if let error = Self.mostInformative(result.deleteResults.values.compactMap(\.failureValue)) { throw error }
            }
        } catch {
            Self.logDiagnostics(error, step: "endRelationship")
            let failure = Self.failure(from: error)
            // Already gone is what we wanted.
            if failure != .notFound { throw failure }
        }
    }

    // MARK: Silent updates

    func ensureChangeSubscription(for record: PartnerConnectionRecord) async {
        let database = record.role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // Silent: wakes Relive to refresh, never shows anything.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        } catch {
            // Not fatal: Relive also refreshes whenever it comes to the foreground.
            Self.logDiagnostics(error, step: "subscription")
        }
    }

    // MARK: Helpers

    private func fetchShare(for record: PartnerConnectionRecord) async throws -> CKShare {
        let database = record.role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: Self.zoneID(for: record))
        do {
            guard let share = try await database.record(for: shareID) as? CKShare else { throw CloudFailure.notFound }
            return share
        } catch let failure as CloudFailure {
            throw failure
        } catch {
            Self.logDiagnostics(error, step: "fetchShare")
            throw Self.failure(from: error)
        }
    }

    private static func zoneID(for record: PartnerConnectionRecord) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: record.zoneName, ownerName: record.role == .owner ? CKCurrentUserDefaultName : record.zoneOwnerName)
    }

    static func participants(of share: CKShare) -> [ParticipantSummary] {
        let me = share.currentUserParticipant
        return share.participants.map { participant in
            let acceptance: ParticipantSummary.Acceptance = switch participant.acceptanceStatus {
            case .pending: .pending
            case .accepted: .accepted
            case .removed: .removed
            default: .unknown
            }
            return ParticipantSummary(
                isOwner: participant.role == .owner,
                isCurrentUser: me.map { $0 === participant || $0.isEqual(participant) } ?? false,
                acceptance: acceptance
            )
        }
    }

    /// An invitation the system handed to Relive (from a tapped link).
    static func invitation(from metadata: CKShare.Metadata) -> PartnerInvitation {
        PartnerInvitation(
            participants: participants(of: metadata.share),
            containerIdentifier: metadata.containerIdentifier,
            zoneName: metadata.share.recordID.zoneID.zoneName,
            isFromCurrentUser: metadata.participantRole == .owner,
            systemMetadata: metadata
        )
    }

    /// In an all-or-nothing batch, one item carries the real error and the others only say
    /// "the batch failed". Returns the real one.
    nonisolated static func mostInformative(_ errors: [Error]) -> Error? {
        errors.first { ($0 as? CKError)?.code != .batchRequestFailed } ?? errors.first
    }

    /// The step and CloudKit's error codes, for Console on a Mac connected to the iPhone
    /// (subsystem `app.relive`, category `partner`). Codes only are public; CloudKit's own
    /// description (which can name records and zones) stays private. Users only ever see the
    /// calm `PartnerMessage`.
    nonisolated static func logDiagnostics(_ error: Error, step: String) {
        logger.error("Partner iCloud step \(step, privacy: .public) failed: \(diagnosticCodes(error), privacy: .public) — \(String(describing: error), privacy: .private)")
    }

    /// "CKError 2 (partial: 15, 22)" — numbers only, so they can be logged publicly.
    nonisolated static func diagnosticCodes(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
        var text = "CKError \(ckError.code.rawValue)"
        if let partial = ckError.partialErrorsByItemID?.values, !partial.isEmpty {
            let codes = partial.compactMap { ($0 as? CKError)?.code.rawValue }.sorted().map(String.init)
            text += " (partial: \(codes.joined(separator: ", ")))"
        }
        return text
    }

    /// CloudKit's errors in Relive's terms. Views only ever see the calm `PartnerMessage`.
    nonisolated static func failure(from error: Error) -> CloudFailure {
        if let failure = error as? CloudFailure { return failure }
        guard let ckError = error as? CKError else {
            return (error as NSError).domain == NSURLErrorDomain ? .networkUnavailable : .unknown
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable:
            return .serviceUnavailable
        case .notAuthenticated:
            return .notSignedIn
        case .quotaExceeded:
            return .quotaExceeded
        case .zoneNotFound, .unknownItem, .userDeletedZone:
            return .notFound
        case .tooManyParticipants:
            return .relationshipFull
        case .permissionFailure:
            return .permissionDenied
        case .partialFailure:
            if let cause = mostInformative(ckError.partialErrorsByItemID.map { Array($0.values) } ?? []) {
                return failure(from: cause)
            }
            return .unknown
        default:
            return .unknown
        }
    }
}

/// Apple's own screen for the relationship's invitation: add people, copy the link, stop sharing.
@MainActor
private final class CloudSharingPresentation: NSObject, PartnerSharingPresentation, UICloudSharingControllerDelegate {
    private let share: CKShare
    private let container: CKContainer
    private let onFinish: @MainActor () -> Void
    private var onChange: (@MainActor () -> Void)?

    init(share: CKShare, container: CKContainer, onFinish: @escaping @MainActor () -> Void) {
        self.share = share
        self.container = container
        self.onFinish = onFinish
    }

    func present(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard let presenter = SystemPresenter.topViewController() else {
            onFinish()
            return
        }
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = self
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    nonisolated func itemTitle(for csc: UICloudSharingController) -> String? {
        String(localized: "Yuvi")
    }

    nonisolated func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        Task { @MainActor in self.finish() }
    }

    private func finish() {
        onChange?()
        onChange = nil
        onFinish()
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
