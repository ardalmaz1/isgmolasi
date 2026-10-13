import Foundation

/// A headline built only from facts: a name the story already uses (a moment, a trip, a place)
/// and the period the memories actually cover.
public struct FactualTitle: Hashable, Sendable, Codable {
    /// What the title is based on — the reason it is true.
    public enum Basis: String, Hashable, Sendable, Codable {
        /// The user's own words.
        case user
        /// The name of the one moment every memory belongs to.
        case moment
        /// The name of the one trip every memory belongs to.
        case trip
        /// The one place every memory was taken.
        case place
        /// The period every memory falls in.
        case period
        /// Nothing more specific is true of all of them.
        case neutral
    }

    public var primary: String
    public var secondary: String?
    public var basis: Basis

    /// "Bergama · August 2025".
    public var combined: String {
        guard let secondary, !secondary.isEmpty else { return primary }
        return "\(primary) · \(secondary)"
    }
}

/// Builds `FactualTitle`s. Prefers omission over invention: when nothing more specific is true
/// of every memory, the title is the neutral "Our Memories" and the dates say the rest.
///
/// Templates are factual by construction ("Our 2026", "Moments from August", "Our Memories ·
/// 2025 – 2026"); names come from the story itself. Words that claim feelings or rank memories
/// ("happiest", "best", "unforgettable") never appear — see `FactualTextPolicy`.
public struct FactualTitleBuilder: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar, locale: Locale = Locale(identifier: "en_US")) {
        self.calendar = calendar
        self.locale = locale
    }

    public static let neutralTitle = "Our Memories"

    public func title(for candidates: [MemoryCandidate], period: PeriodDescriptor, story: Story, userTitle: String? = nil) -> FactualTitle {
        let periodLabel = period.isComplete ? period.label(locale: locale, calendar: calendar) : nil

        if let userTitle = userTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !userTitle.isEmpty {
            return FactualTitle(primary: userTitle, secondary: periodLabel, basis: .user)
        }
        guard !candidates.isEmpty else {
            return FactualTitle(primary: Self.neutralTitle, secondary: nil, basis: .neutral)
        }

        if let id = candidates.first?.momentID, candidates.allSatisfy({ $0.momentID == id }),
           let moment = story.moment(id: id) {
            let name = moment.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return FactualTitle(primary: name, secondary: periodLabel, basis: .moment)
            }
        }
        if let id = candidates.first?.tripID, candidates.allSatisfy({ $0.tripID == id }),
           let trip = story.chapter(id: id) {
            let name = trip.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return FactualTitle(primary: name, secondary: periodLabel, basis: .trip)
            }
        }
        if let place = period.commonPlace {
            // "Bergama · August 2025": the place, dated by the memories themselves.
            return FactualTitle(primary: place.name, secondary: periodLabel, basis: .place)
        }

        // Only a period that covers every memory may become the title.
        guard period.isComplete else {
            return FactualTitle(primary: Self.neutralTitle, secondary: nil, basis: .neutral)
        }
        let names = MonthNames(locale: locale, calendar: calendar)
        switch period.kind {
        case .month(let month):
            return FactualTitle(primary: "Moments from \(names.full(month.month))", secondary: periodLabel, basis: .period)
        case .days(let first, _):
            return FactualTitle(primary: "Moments from \(names.full(first.month))", secondary: periodLabel, basis: .period)
        case .months(let first, _):
            return FactualTitle(primary: "Our \(first.year)", secondary: periodLabel, basis: .period)
        case .years:
            return FactualTitle(primary: Self.neutralTitle, secondary: periodLabel, basis: .period)
        case .day:
            return FactualTitle(primary: periodLabel ?? Self.neutralTitle, secondary: nil, basis: .period)
        case .unknown:
            return FactualTitle(primary: Self.neutralTitle, secondary: nil, basis: .neutral)
        }
    }
}

/// The rule every generated word must follow — and the seam a future AI captioner must pass
/// through: no claims about feelings, and no ranking of a couple's memories.
public enum FactualTextPolicy {
    /// Words and phrases Relive never generates. User-written text is the user's and is never
    /// checked against this.
    public static let claims: [String] = [
        "happiest", "happy", "best", "favorite", "favourite", "greatest", "perfect", "unforgettable",
        "never forget", "magical", "dream", "love of", "true love", "most beautiful", "special",
        "amazing", "incredible", "meant the most", "of our lives", "forever",
    ]

    /// The claims `text` makes, if any (case- and diacritic-insensitive, whole words).
    public static func violations(in text: String) -> [String] {
        let folded = " " + text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
        return claims.filter { folded.contains(" \($0) ") }
    }

    public static func isFactual(_ text: String) -> Bool { violations(in: text).isEmpty }
}
