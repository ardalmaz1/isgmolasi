import Foundation
import Observation
import ReliveCore

/// The partner connection as Us shows it. Drives `PartnerCloudService` and remembers the result
/// in `PartnerConnectionCaching`, so the state survives relaunches and "offline" is never
/// mistaken for "disconnected".
///
/// Solo users never reach iCloud: the service is created on first use, and nothing calls it until
/// the user taps Connect or a relationship is remembered.
@Observable
@MainActor
final class PartnerConnectionModel {
    private(set) var state: PartnerConnectionState
    private(set) var record: PartnerConnectionRecord?
    /// A one-off message to show over whatever is on screen (accepting an invitation can happen
    /// anywhere in the app).
    var notice: PartnerMessage?

    @ObservationIgnored private let cache: any PartnerConnectionCaching
    @ObservationIgnored private let analytics: any AnalyticsTracking
    @ObservationIgnored private let makeService: @MainActor () -> any PartnerCloudService
    @ObservationIgnored private var _service: (any PartnerCloudService)?
    @ObservationIgnored private let now: () -> Date
    /// Called whenever this iPhone has a relationship, so it can receive silent updates.
    @ObservationIgnored private let onRelationship: @MainActor () -> Void

    init(
        cache: any PartnerConnectionCaching,
        analytics: any AnalyticsTracking,
        now: @escaping () -> Date = Date.init,
        onRelationship: @escaping @MainActor () -> Void = {},
        makeService: @escaping @MainActor () -> any PartnerCloudService
    ) {
        self.cache = cache
        self.analytics = analytics
        self.now = now
        self.onRelationship = onRelationship
        self.makeService = makeService
        let remembered = cache.load()
        self.record = remembered
        self.state = .fromMemory(remembered)
        if remembered != nil { onRelationship() }
    }

    /// Whether iCloud has been asked anything in this run (tests check solo users never do).
    var hasUsedICloud: Bool { _service != nil }

    private var service: any PartnerCloudService {
        if let _service { return _service }
        let made = makeService()
        _service = made
        return made
    }

    /// When iCloud last confirmed the connection.
    var lastSyncedAt: Date? { record?.lastConfirmedAt }

    // MARK: Connecting (owner)

    /// After the explanation: checks iCloud, makes the relationship (or reuses the waiting one)
    /// and shows Apple's invitation screen.
    func connect() async {
        guard !state.isBusy else { return }
        if let record {
            if record.role == .owner, record.status == .waitingForPartner { await presentInvitation() }
            return
        }
        analytics.track(.partnerConnectStarted)
        state = .checkingICloud
        if let message = PartnerMessage.forAccount(await service.accountStatus()) {
            state = .iCloudUnavailable(message)
            analytics.track(.partnerConnectFailed, ["reason": "account"])
            return
        }
        state = .creatingRelationship
        do {
            let created = try await service.createRelationship(now: now())
            remember(created)
            analytics.track(.partnerInvitationCreated)
            onRelationship()
            await service.ensureChangeSubscription(for: created)
            await presentInvitation()
        } catch {
            let failure = error as? CloudFailure ?? .unknown
            state = .failed(.forFailure(failure))
            analytics.track(.partnerConnectFailed, ["reason": Self.code(failure)])
        }
    }

    /// Shows the invitation again (to send it another way, or to stop it).
    func presentInvitation() async {
        guard let record, record.role == .owner else { return }
        do {
            let occupancy = try await service.occupancy(of: record)
            apply(occupancy, to: record)
            guard self.record?.status == .waitingForPartner else { return }
            let presentation = try await service.sharingPresentation(for: record)
            presentation?.present { [weak self] in
                Task { await self?.refresh(afterOwnChange: true) }
            }
        } catch {
            await handleRefreshFailure(error as? CloudFailure ?? .unknown, record: record, ownChange: false)
        }
    }

    // MARK: Joining (partner)

    /// An invitation opened on this iPhone — at cold launch, while running, or on return.
    func accept(_ invitation: PartnerInvitation) async {
        if invitation.isFromCurrentUser || invitation.zoneName == record?.zoneName {
            // Your own invitation, or one already accepted: nothing new to join.
            await refresh()
            return
        }
        if record?.status == .connected {
            notice = .alreadyConnected
            return
        }
        guard TwoPersonRule.mayAccept(invitation.participants) else {
            notice = .relationshipFull
            analytics.track(.partnerConnectFailed, ["reason": "full"])
            return
        }
        guard !state.isBusy else { return }
        let previous = record
        state = .joining
        do {
            let joined = try await service.accept(invitation, now: now())
            // A waiting invitation of your own that nobody accepted gives way to the one you joined.
            if let previous, previous.role == .owner {
                try? await service.endRelationship(previous)
            }
            remember(joined)
            notice = .joined
            analytics.track(.partnerJoined)
            onRelationship()
            await service.ensureChangeSubscription(for: joined)
        } catch {
            let failure = error as? CloudFailure ?? .unknown
            state = .fromMemory(record)
            notice = .forFailure(failure)
            analytics.track(.partnerConnectFailed, ["reason": Self.code(failure)])
        }
    }

    // MARK: Staying in step

    /// Asks iCloud whether the connection is still there. Does nothing for solo users.
    func refresh() async {
        await refresh(afterOwnChange: false)
    }

    private func refresh(afterOwnChange: Bool) async {
        guard let record, !state.isBusy else { return }
        do {
            let occupancy = try await service.occupancy(of: record)
            if record.role == .owner, record.status == .connected, occupancy == .ownerOnly || occupancy == .invited {
                // The partner left. A Relive relationship is two people, so it ends here too.
                try? await service.endRelationship(record)
                end(with: .connectionEnded(byPartner: true))
                return
            }
            apply(occupancy, to: record)
        } catch {
            await handleRefreshFailure(error as? CloudFailure ?? .unknown, record: record, ownChange: afterOwnChange)
        }
    }

    /// iCloud reported a change to the relationship (silent push).
    func cloudDidChange() async {
        await refresh()
    }

    // MARK: Disconnecting

    /// Owner: ends the relationship for both. Partner: leaves it.
    func disconnect() async {
        guard let record, !state.isBusy else { return }
        state = .disconnecting
        do {
            try await service.endRelationship(record)
            forget()
            state = .notConnected
            analytics.track(.partnerDisconnected, ["role": record.role.rawValue])
        } catch {
            // Nothing changed: still connected (or waiting), and the user can try again.
            state = .fromMemory(record)
            notice = .forFailure(error as? CloudFailure ?? .unknown)
        }
    }

    /// Back to solo after a message was read.
    func acknowledge() {
        switch state {
        case .ended, .failed, .iCloudUnavailable:
            state = .fromMemory(record)
        default:
            break
        }
    }

    // MARK: Private

    private func apply(_ occupancy: TwoPersonRule.Occupancy, to record: PartnerConnectionRecord) {
        var updated = record
        switch (record.role, occupancy) {
        case (.partner, _), (.owner, .paired), (.owner, .overfull):
            updated.status = .connected
        case (.owner, .ownerOnly), (.owner, .invited):
            updated.status = .waitingForPartner
        }
        updated.lastConfirmedAt = now()
        remember(updated)
    }

    private func handleRefreshFailure(_ failure: CloudFailure, record: PartnerConnectionRecord, ownChange: Bool) async {
        let next = PartnerConnectionState.afterRefreshFailure(failure, record: record)
        guard case .ended(let message) = next else {
            state = next
            return
        }
        if record.role == .owner, failure == .notFound {
            // Sharing was stopped (perhaps from Apple's screen): remove the leftover space.
            try? await service.endRelationship(record)
        }
        end(with: ownChange ? .connectionEnded(byPartner: false) : message)
    }

    private func end(with message: PartnerMessage) {
        let role = record?.role.rawValue ?? ""
        forget()
        state = .ended(message)
        analytics.track(.partnerConnectionEnded, ["role": role])
    }

    private func remember(_ record: PartnerConnectionRecord) {
        self.record = record
        cache.save(record)
        state = .fromMemory(record)
    }

    private func forget() {
        record = nil
        cache.save(nil)
    }

    private static func code(_ failure: CloudFailure) -> String {
        switch failure {
        case .networkUnavailable: "network"
        case .serviceUnavailable: "service"
        case .notSignedIn: "signed_out"
        case .accountChanged: "account_changed"
        case .quotaExceeded: "quota"
        case .notFound: "not_found"
        case .relationshipFull: "full"
        case .alreadyConnected: "already_connected"
        case .permissionDenied: "permission"
        case .unknown: "unknown"
        }
    }
}

/// Where the system hands over invitations and change notices before (or while) the model
/// exists: the scene delegate can receive an invitation during a cold launch.
@MainActor
final class PartnerInbox {
    static let shared = PartnerInbox()

    private var pending: [PartnerInvitation] = []
    private var pendingChange = false
    private weak var model: PartnerConnectionModel?

    func attach(_ model: PartnerConnectionModel) {
        self.model = model
        let invitations = pending
        pending = []
        let changed = pendingChange
        pendingChange = false
        Task {
            for invitation in invitations { await model.accept(invitation) }
            if changed { await model.cloudDidChange() }
        }
    }

    func deliver(_ invitation: PartnerInvitation) {
        guard let model else {
            pending.append(invitation)
            return
        }
        Task { await model.accept(invitation) }
    }

    func cloudDidChange() async {
        guard let model else {
            pendingChange = true
            return
        }
        await model.cloudDidChange()
    }
}
