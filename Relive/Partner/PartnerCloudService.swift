import Foundation
import ReliveCore

/// An invitation this iPhone was asked to accept: who is already on it (for the two-person rule),
/// and the system's own invitation object, which only the CloudKit service understands.
struct PartnerInvitation {
    var participants: [ParticipantSummary]
    /// The container the invitation belongs to. Invitations for another app are refused.
    var containerIdentifier: String
    /// The relationship's space, so opening your own (or an already accepted) invitation is
    /// recognised instead of treated as a new one.
    var zoneName: String
    /// True when this iPhone's iCloud account made the invitation.
    var isFromCurrentUser: Bool
    /// `CKShare.Metadata` from the system (nil in tests and previews).
    var systemMetadata: Any?
}

/// Something that can show Apple's own sharing screen for the relationship ("Add people",
/// "Copy link", "Stop sharing"). Opaque to views: they only ask the model to present it.
@MainActor
protocol PartnerSharingPresentation: AnyObject {
    /// Shows the screen over whatever is on screen. `onChange` is called when the user changed
    /// or stopped sharing there.
    func present(onChange: @escaping @MainActor () -> Void)
}

/// The only place Relive talks to iCloud about a partner. Views never touch CloudKit; the
/// `PartnerConnectionModel` drives this boundary, and tests replace it with a fake.
///
/// Every method throws `CloudFailure` (never a CloudKit error).
@MainActor
protocol PartnerCloudService: AnyObject {
    /// Whether iCloud can be used for a partner connection right now.
    func accountStatus() async -> CloudAccountAvailability

    /// Owner: makes the relationship's private iCloud space, its relationship record and the
    /// invitation (shared with nobody yet). Nothing about photos or the library is written.
    func createRelationship(now: Date) async throws -> PartnerConnectionRecord

    /// How many people are on the relationship right now (owner side), or whether it still
    /// exists (partner side). Throws `.notFound` when it ended.
    func occupancy(of record: PartnerConnectionRecord) async throws -> TwoPersonRule.Occupancy

    /// Apple's sharing screen for the owner's relationship. Nil where there is no system UI
    /// (tests, previews).
    func sharingPresentation(for record: PartnerConnectionRecord) async throws -> (any PartnerSharingPresentation)?

    /// Accepts an invitation and returns the relationship as this iPhone now remembers it.
    func accept(_ invitation: PartnerInvitation, now: Date) async throws -> PartnerConnectionRecord

    /// Owner: deletes the relationship's space (and with it the invitation) — the partner loses
    /// access. Partner: leaves the relationship; the owner's space stays theirs.
    func endRelationship(_ record: PartnerConnectionRecord) async throws

    /// Asks iCloud to wake Relive silently when the relationship changes (no visible
    /// notification). Safe to call repeatedly.
    func ensureChangeSubscription(for record: PartnerConnectionRecord) async
}
