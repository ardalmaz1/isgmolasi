import Foundation

// Phase B — partner connection foundation. Pure value types and rules, no CloudKit: the app's
// CloudKit service maps Apple's types onto these, so the rules are testable anywhere and no view
// ever sees a CloudKit error. See docs/COUPLES_ARCHITECTURE.md.

/// Which side of the relationship this iPhone is on. CloudKit treats the two differently: the
/// owner's iCloud holds the shared space; the partner joins it.
public enum PartnerRole: String, Codable, Sendable {
    /// Created the relationship and sent the invitation.
    case owner
    /// Accepted the invitation.
    case partner
}

/// The iCloud account state, as far as connecting a partner is concerned.
public enum CloudAccountAvailability: String, Codable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

/// What went wrong, in Relive's terms. The CloudKit service maps `CKError`s onto these.
public enum CloudFailure: Error, Equatable, Sendable {
    /// No network, or iCloud couldn't be reached.
    case networkUnavailable
    /// iCloud is busy or rate-limited; try later.
    case serviceUnavailable
    /// Not signed in to iCloud (or signed out meanwhile).
    case notSignedIn
    /// The iCloud account changed since the relationship was made on this iPhone.
    case accountChanged
    /// The owner's iCloud storage is full.
    case quotaExceeded
    /// The relationship or invitation no longer exists (ended, or deleted elsewhere).
    case notFound
    /// The invitation is for a relationship that already has two people.
    case relationshipFull
    /// This iPhone is already connected to someone.
    case alreadyConnected
    /// iCloud refused the operation for this account.
    case permissionDenied
    /// Anything else.
    case unknown

    /// Worth retrying without the user doing anything.
    public var isTemporary: Bool {
        switch self {
        case .networkUnavailable, .serviceUnavailable: true
        default: false
        }
    }
}

/// Calm, plain words for every situation. Never a CloudKit term or an error code.
public enum PartnerMessage: Equatable, Sendable {
    case signInToICloud
    case iCloudRestricted
    case iCloudUnknown
    case couldNotReachICloud
    case temporarilyUnavailable
    case relationshipFull
    case alreadyConnected
    case iCloudFull
    case invitationEnded
    case connectionEnded(byPartner: Bool)
    case accountChanged
    case somethingWentWrong
    /// Shown once after accepting an invitation.
    case joined

    public var text: String {
        switch self {
        case .signInToICloud:
            "Sign in to iCloud in Settings to connect your partner. Relive works as usual without it."
        case .iCloudRestricted:
            "iCloud isn’t available on this iPhone, so a partner can’t be connected. Relive works as usual without it."
        case .iCloudUnknown:
            "Relive couldn’t check iCloud right now. Try again in a moment."
        case .couldNotReachICloud:
            "Relive couldn’t reach iCloud. Try again."
        case .temporarilyUnavailable:
            "Your partner connection is temporarily unavailable. Relive will try again."
        case .relationshipFull:
            "This Relive relationship already has two people."
        case .alreadyConnected:
            "You’re already connected with a partner. Disconnect first to accept another invitation."
        case .iCloudFull:
            "There isn’t enough iCloud storage to connect. Free up space in Settings and try again."
        case .invitationEnded:
            "This invitation is no longer active. Ask for a new one."
        case .connectionEnded(let byPartner):
            byPartner
                ? "Your partner ended the connection. Your own memories are unchanged."
                : "The connection ended. Your own memories are unchanged."
        case .accountChanged:
            "The iCloud account on this iPhone changed, so the partner connection was paused."
        case .somethingWentWrong:
            "Something went wrong. Try again."
        case .joined:
            "You’re connected. Each of you keeps your own memories on your own iPhone; only what you choose to share later is shared."
        }
    }

    public static func forAccount(_ availability: CloudAccountAvailability) -> PartnerMessage? {
        switch availability {
        case .available: nil
        case .noAccount: .signInToICloud
        case .restricted: .iCloudRestricted
        case .couldNotDetermine: .iCloudUnknown
        case .temporarilyUnavailable: .temporarilyUnavailable
        }
    }

    public static func forFailure(_ failure: CloudFailure) -> PartnerMessage {
        switch failure {
        case .networkUnavailable: .couldNotReachICloud
        case .serviceUnavailable: .temporarilyUnavailable
        case .notSignedIn: .signInToICloud
        case .accountChanged: .accountChanged
        case .quotaExceeded: .iCloudFull
        case .notFound: .invitationEnded
        case .relationshipFull: .relationshipFull
        case .alreadyConnected: .alreadyConnected
        case .permissionDenied, .unknown: .somethingWentWrong
        }
    }
}

// MARK: - Two people

/// One person on a share, as far as Relive's two-person rule cares.
public struct ParticipantSummary: Equatable, Sendable {
    public enum Acceptance: String, Sendable {
        case pending
        case accepted
        case removed
        case unknown
    }

    public var isOwner: Bool
    public var isCurrentUser: Bool
    public var acceptance: Acceptance

    public init(isOwner: Bool, isCurrentUser: Bool, acceptance: Acceptance) {
        self.isOwner = isOwner
        self.isCurrentUser = isCurrentUser
        self.acceptance = acceptance
    }
}

/// A Relive relationship is two people. CloudKit allows more; Relive doesn't.
public enum TwoPersonRule {
    public enum Occupancy: Equatable, Sendable {
        /// Only the owner.
        case ownerOnly
        /// Invited, not accepted yet.
        case invited
        /// Owner and one accepted partner.
        case paired
        /// More than one accepted partner (should never happen through Relive; possible if the
        /// share was changed outside it).
        case overfull
    }

    public static func occupancy(_ participants: [ParticipantSummary]) -> Occupancy {
        let others = participants.filter { !$0.isOwner && $0.acceptance != .removed }
        let accepted = others.filter { $0.acceptance == .accepted }.count
        if accepted > 1 { return .overfull }
        if accepted == 1 { return .paired }
        return others.isEmpty ? .ownerOnly : .invited
    }

    /// May the owner invite someone now? Only while nobody has joined.
    public static func mayInvite(_ participants: [ParticipantSummary]) -> Bool {
        switch occupancy(participants) {
        case .ownerOnly, .invited: true
        case .paired, .overfull: false
        }
    }

    /// May this person accept the invitation? Not if someone other than them already joined.
    public static func mayAccept(_ participants: [ParticipantSummary]) -> Bool {
        let otherAccepted = participants.filter { !$0.isOwner && !$0.isCurrentUser && $0.acceptance == .accepted }
        return otherAccepted.isEmpty
    }
}

// MARK: - Local memory of the connection

/// What this iPhone remembers about its partner connection, so Us shows the right state without
/// asking iCloud first, and offline isn't mistaken for disconnected. Identifiers only — no names
/// from iCloud, no photos, no library data.
public struct PartnerConnectionRecord: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The owner made the relationship; nobody has joined yet.
        case waitingForPartner
        /// Two people.
        case connected
    }

    /// The shared relationship's identifier (also the name of its space in iCloud).
    public var relationshipID: String
    public var role: PartnerRole
    /// The iCloud space ("zone") that holds the relationship, and its owner — enough for either
    /// side to find it again after a relaunch.
    public var zoneName: String
    public var zoneOwnerName: String
    public var status: Status
    public var createdAt: Date
    /// When iCloud last confirmed the status.
    public var lastConfirmedAt: Date?

    public init(relationshipID: String, role: PartnerRole, zoneName: String, zoneOwnerName: String, status: Status, createdAt: Date, lastConfirmedAt: Date? = nil) {
        self.relationshipID = relationshipID
        self.role = role
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.status = status
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt
    }
}

/// What Us shows about the partner connection.
public enum PartnerConnectionState: Equatable, Sendable {
    /// Solo Relive (the default, and the state after a disconnect).
    case notConnected
    case checkingICloud
    case iCloudUnavailable(PartnerMessage)
    case creatingRelationship
    /// The owner's relationship exists and nobody has joined. `isOffline`: shown from memory.
    case waitingForPartner(isOffline: Bool)
    /// Accepting an invitation on this iPhone.
    case joining
    /// Two people. `isOffline`: iCloud couldn't confirm just now; still connected.
    case connected(role: PartnerRole, isOffline: Bool)
    case disconnecting
    /// Shown once after the connection ended (from either side), then solo.
    case ended(PartnerMessage)
    case failed(PartnerMessage)

    /// Connected or waiting, even while offline.
    public var hasRelationship: Bool {
        switch self {
        case .waitingForPartner, .connected: true
        default: false
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checkingICloud, .creatingRelationship, .joining, .disconnecting: true
        default: false
        }
    }

    /// The state to show from memory alone, before (or without) asking iCloud.
    public static func fromMemory(_ record: PartnerConnectionRecord?) -> PartnerConnectionState {
        guard let record else { return .notConnected }
        switch record.status {
        case .waitingForPartner: return .waitingForPartner(isOffline: false)
        case .connected: return .connected(role: record.role, isOffline: false)
        }
    }

    /// The state after a refresh failed: what we remember, marked offline — or a clear message
    /// if the failure means the relationship is gone or the account changed.
    public static func afterRefreshFailure(_ failure: CloudFailure, record: PartnerConnectionRecord?) -> PartnerConnectionState {
        guard let record else { return .notConnected }
        switch failure {
        case .networkUnavailable, .serviceUnavailable, .unknown, .permissionDenied:
            switch record.status {
            case .waitingForPartner: return .waitingForPartner(isOffline: true)
            case .connected: return .connected(role: record.role, isOffline: true)
            }
        case .notFound:
            return .ended(.connectionEnded(byPartner: record.status == .connected))
        case .notSignedIn:
            return .iCloudUnavailable(.signInToICloud)
        case .accountChanged:
            return .ended(.accountChanged)
        case .quotaExceeded, .relationshipFull, .alreadyConnected:
            return fromMemory(record)
        }
    }
}

// MARK: - What goes to iCloud

/// The one record Phase B writes to iCloud: that a relationship exists. Nothing about photos,
/// places, people or the library — the allowlist below is the privacy boundary, and tests check
/// it. Later phases add their own record types with their own allowlists.
public struct RelationshipCloudFields: Equatable, Sendable {
    public static let recordType = "Relationship"
    public static let currentSchemaVersion = 1
    /// Every field this record may carry.
    public static let allowedKeys: Set<String> = ["relationshipID", "createdAt", "schemaVersion"]

    public var relationshipID: String
    public var createdAt: Date
    public var schemaVersion: Int

    public init(relationshipID: String, createdAt: Date, schemaVersion: Int = RelationshipCloudFields.currentSchemaVersion) {
        self.relationshipID = relationshipID
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }

    /// The values to store, by key.
    public enum Value: Equatable, Sendable {
        case string(String)
        case date(Date)
        case int(Int)
    }

    public var values: [String: Value] {
        [
            "relationshipID": .string(relationshipID),
            "createdAt": .date(createdAt),
            "schemaVersion": .int(schemaVersion),
        ]
    }

    /// The iCloud space for a relationship. One per relationship, named after it.
    public static func zoneName(for relationshipID: String) -> String {
        "Relationship-\(relationshipID)"
    }
}
