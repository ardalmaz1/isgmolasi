import Foundation

/// How the two people are named together, everywhere in Relive: "Arda ♥ Kübra".
///
/// One place for the rule, so no screen builds the pair by hand:
/// - `display` — "Arda ♥ Kübra": the names joined by a quiet typographic heart (U+2665, drawn as
///   text — not the red emoji). Never "Arda + Kübra".
/// - `spoken` — "Arda and Kübra": what VoiceOver reads, so the heart isn't read aloud.
/// - `plain` — "Arda & Kübra": where a symbol doesn't belong (plain text, film credits).
///
/// Without the user's own name, the user is "You" ("You ♥ Kübra"). Names are trimmed; an empty
/// partner name leaves just the lead. Locale-specific joining words are a localization concern
/// (`spokenJoiner`).
public struct CoupleName: Hashable, Sendable {
    /// The user's own name, or nil (shown as `you`).
    public var userName: String?
    public var partnerName: String

    /// The quiet heart between the names.
    public static let heart = "\u{2665}"

    public init(userName: String?, partnerName: String) {
        let user = userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.userName = user.isEmpty ? nil : user
        self.partnerName = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first name: the user's own, or "You".
    public func lead(you: String = CoreWords().pick("You", "Sen")) -> String {
        userName ?? you
    }

    /// Both names are known (the user gave their own).
    public var hasBothNames: Bool { userName != nil && !partnerName.isEmpty }

    /// "Arda ♥ Kübra", "You ♥ Kübra", or just the lead when there is no partner name.
    public func display(you: String = CoreWords().pick("You", "Sen")) -> String {
        partnerName.isEmpty ? lead(you: you) : "\(lead(you: you)) \(Self.heart) \(partnerName)"
    }

    /// "Arda and Kübra" — for VoiceOver.
    public func spoken(you: String = CoreWords().pick("You", "Sen"), spokenJoiner: String = CoreWords().pick("and", "ve")) -> String {
        partnerName.isEmpty ? lead(you: you) : "\(lead(you: you)) \(spokenJoiner) \(partnerName)"
    }

    /// "Arda & Kübra" — where a symbol doesn't belong.
    public func plain(you: String = CoreWords().pick("You", "Sen")) -> String {
        partnerName.isEmpty ? lead(you: you) : "\(lead(you: you)) & \(partnerName)"
    }
}

extension RelationshipProfile {
    /// The couple's names, presented the one Relive way.
    public var coupleName: CoupleName {
        CoupleName(userName: userName, partnerName: partnerName)
    }
}
