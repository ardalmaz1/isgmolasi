import Foundation

/// When the story began. Users often only remember the month or year, so precision is explicit
/// and everything derived from it (e.g. day counts) can be phrased honestly.
public struct RelationshipStart: Codable, Hashable, Sendable {
    public enum Precision: String, Codable, Hashable, Sendable, CaseIterable {
        case day
        case month
        case year
    }

    public var date: Date
    public var precision: Precision

    public init(date: Date, precision: Precision) {
        self.date = date
        self.precision = precision
    }

    public var isApproximate: Bool { precision != .day }

    /// Whole calendar days from the start until `now` (never negative).
    public func daysTogether(until now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }
}

/// What the user told us during onboarding. Relationship labels are intentionally absent.
public struct RelationshipProfile: Codable, Hashable, Sendable {
    public var partnerName: String
    /// Optional; we never ask for it during onboarding.
    public var userName: String?
    public var start: RelationshipStart?

    public init(partnerName: String, userName: String? = nil, start: RelationshipStart? = nil) {
        self.partnerName = partnerName
        self.userName = userName
        self.start = start
    }

    /// "You + Emma", or "Jake + Emma" when the user added their own name.
    public var coupleDisplayName: String {
        let partner = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lead = user.isEmpty ? "You" : user
        return partner.isEmpty ? lead : "\(lead) + \(partner)"
    }
}
