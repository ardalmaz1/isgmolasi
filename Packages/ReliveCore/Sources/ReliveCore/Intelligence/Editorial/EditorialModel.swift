import Foundation

// Editorial intelligence: one shared way for every Relive surface to put real facts into words.
//
// Memory Intelligence (and the recap and movie planners) decide WHAT happened. Editorial
// intelligence only decides HOW a supported fact is phrased. A provider (deterministic today,
// an on-device model where one is available) proposes candidates; `EditorialValidator` accepts
// only candidates every word of which is supported by the context; anything else falls back to
// Relive's deterministic wording. See docs/EDITORIAL_INTELLIGENCE.md.

/// Where words appear. Each surface has its own limits (a movie needs very few words).
public enum EditorialSurface: String, CaseIterable, Codable, Hashable, Sendable {
    case madeForYou
    case recap
    case ourYear
    case movie
    case book
    case story
    case collage
}

/// What kind of words are asked for. Always short: Relive is a photo product.
public enum EditorialRequestKind: String, CaseIterable, Codable, Hashable, Sendable {
    case title
    case subtitle
    case transition
    case chapterTitle
    case closingLine
    case shortCaption
    case shareCardLine
}

/// The language words are written in. Facts are language-independent; only rendering changes.
public enum EditorialLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case english = "en"
    case turkish = "tr"
}

/// How sure Relive is of a piece of information.
public enum EditorialFactClass: String, Codable, Hashable, Sendable {
    /// Read straight from the library: a capture date, a place name, a count, a favorite, the
    /// user's own words.
    case verified
    /// A deterministic conclusion from verified facts ("four days in Kaş").
    case derived
    /// A feeling or judgement ("romantic", "the best day"). Never stated by Relive.
    case interpretation
}

/// Who wrote a piece of text. A user's words are theirs and are never checked or rewritten.
public enum EditorialAuthorship: String, Codable, Hashable, Sendable {
    case user
    case relive
}

/// One fact a context carries, labelled with how it is known.
public struct EditorialFact: Hashable, Codable, Sendable {
    public var factClass: EditorialFactClass
    public var key: String
    public var value: String
}

/// Everything a provider may use — structured facts only. No photos, identifiers, coordinates,
/// notes or captions (unless the user's own title, which is marked as theirs).
public struct EditorialContext: Hashable, Codable, Sendable {
    public struct Counts: Hashable, Codable, Sendable {
        public var memories: Int?
        public var moments: Int?
        public var places: Int?
        public var favorites: Int?
        public var months: Int?
        public var frames: Int?

        public init(memories: Int? = nil, moments: Int? = nil, places: Int? = nil, favorites: Int? = nil, months: Int? = nil, frames: Int? = nil) {
            self.memories = memories
            self.moments = moments
            self.places = places
            self.favorites = favorites
            self.months = months
            self.frames = frames
        }

        var all: [Int] { [memories, moments, places, favorites, months, frames].compactMap { $0 } }
    }

    public var surface: EditorialSurface
    public var language: EditorialLanguage
    /// The first and last capture day, only when every memory is dated.
    public var firstDay: DayKey?
    public var lastDay: DayKey?
    /// Months the memories fall in (ordered).
    public var months: [MonthKey]
    /// Place names Relive already shows for these memories (none when unknown).
    public var places: [String]
    /// The trip's name, only when the story knows a trip.
    public var tripName: String?
    /// The moment's name, only when every memory is one moment.
    public var momentName: String?
    public var counts: Counts
    /// "Summer 2026", only when the season is known (never assumed).
    public var season: String?
    /// Relive's canonical label for the period ("August 6–9, 2026"), when every memory is dated.
    public var periodLabel: String?
    /// The factual title Relive already uses here ("Kaş & Kekova · August 2025").
    public var factualTitle: String?
    /// Other wording Relive already shows that a candidate may repeat (labels, dates).
    public var knownPhrases: [String]
    /// Numbers Relive already shows that aren't counts (e.g. inside a date label).
    public var extraNumbers: Set<Int>
    /// The user's own words (a title they typed). Never generated, never checked.
    public var userText: String?

    public init(
        surface: EditorialSurface,
        language: EditorialLanguage = .english,
        firstDay: DayKey? = nil,
        lastDay: DayKey? = nil,
        months: [MonthKey] = [],
        places: [String] = [],
        tripName: String? = nil,
        momentName: String? = nil,
        counts: Counts = Counts(),
        season: String? = nil,
        periodLabel: String? = nil,
        factualTitle: String? = nil,
        knownPhrases: [String] = [],
        extraNumbers: Set<Int> = [],
        userText: String? = nil
    ) {
        self.surface = surface
        self.language = language
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.months = months
        self.places = places
        self.tripName = tripName
        self.momentName = momentName
        self.counts = counts
        self.season = season
        self.periodLabel = periodLabel
        self.factualTitle = factualTitle
        self.knownPhrases = knownPhrases
        self.extraNumbers = extraNumbers
        self.userText = userText
    }

    // MARK: - Derived facts

    /// Calendar days from the first to the last memory, when both are known.
    public var dayCount: Int? {
        guard let first = firstDay, let last = lastDay else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let a = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day)),
              let b = calendar.date(from: DateComponents(year: last.year, month: last.month, day: last.day)),
              let days = calendar.dateComponents([.day], from: a, to: b).day else { return nil }
        return days + 1
    }

    /// The one place every memory shares, if there is exactly one.
    public var singlePlace: String? { places.count == 1 ? places[0] : nil }

    public var years: [Int] {
        var seen = Set<Int>()
        return months.map(\.year).filter { seen.insert($0).inserted }
    }

    /// Every number a generated text may contain as digits ("August 6–9").
    public var allowedNumbers: Set<Int> {
        var numbers = allowedNumberWords
        if let firstDay { numbers.insert(firstDay.day) }
        if let lastDay { numbers.insert(lastDay.day) }
        for phrase in knownPhrases + [factualTitle, tripName, momentName, season, periodLabel].compactMap({ $0 }) {
            numbers.formUnion(EditorialFacts.numbers(in: phrase))
        }
        return numbers
    }

    /// Numbers a generated text may spell out ("four days"): counts and lengths, never a
    /// day of the month — "Six days" is not supported by a trip that began on the 6th.
    public var allowedNumberWords: Set<Int> {
        var numbers = Set(counts.all).union(extraNumbers).union(years)
        if let dayCount { numbers.insert(dayCount) }
        if months.count > 1 { numbers.insert(months.count) }
        return numbers
    }

    /// Names and phrases a generated text may repeat verbatim.
    public var allowedPhrases: [String] {
        let phrases = places + [tripName, momentName, season, periodLabel, factualTitle].compactMap { $0 } + knownPhrases
        var seen = Set<String>()
        return phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// The facts, each labelled with how it is known (for diagnostics, documentation and tests).
    public var facts: [EditorialFact] {
        var result: [EditorialFact] = []
        func verified(_ key: String, _ value: String?) {
            if let value { result.append(EditorialFact(factClass: .verified, key: key, value: value)) }
        }
        verified("firstDay", firstDay.map { "\($0.year)-\($0.month)-\($0.day)" })
        verified("lastDay", lastDay.map { "\($0.year)-\($0.month)-\($0.day)" })
        for month in months { verified("month", "\(month.year)-\(month.month)") }
        for place in places { verified("place", place) }
        verified("trip", tripName)
        verified("moment", momentName)
        verified("memories", counts.memories.map(String.init))
        verified("moments", counts.moments.map(String.init))
        verified("places", counts.places.map(String.init))
        verified("favorites", counts.favorites.map(String.init))
        verified("season", season)
        verified("userText", userText)
        if let dayCount { result.append(EditorialFact(factClass: .derived, key: "dayCount", value: String(dayCount))) }
        if let place = singlePlace { result.append(EditorialFact(factClass: .derived, key: "singlePlace", value: place)) }
        return result
    }
}

/// One request for words.
public struct EditorialRequest: Hashable, Codable, Sendable {
    public var context: EditorialContext
    public var kind: EditorialRequestKind

    public init(context: EditorialContext, kind: EditorialRequestKind) {
        self.context = context
        self.kind = kind
    }

    /// The longest acceptable text for this surface and kind (characters).
    public var maxCharacters: Int {
        switch (context.surface, kind) {
        case (.movie, _): 34
        case (.collage, _): 36
        case (_, .title), (_, .chapterTitle): 44
        case (_, .subtitle), (_, .shareCardLine): 60
        case (_, .transition), (_, .closingLine): 48
        case (_, .shortCaption): 70
        }
    }
}

/// A proposed text and who proposed it.
public struct EditorialCandidate: Hashable, Codable, Sendable {
    public var text: String
    public var provider: String
    public var authorship: EditorialAuthorship

    public init(text: String, provider: String, authorship: EditorialAuthorship = .relive) {
        self.text = text
        self.provider = provider
        self.authorship = authorship
    }
}

/// Why a candidate was refused. Codes only (never the text) are logged.
public enum EditorialRejection: String, CaseIterable, Codable, Hashable, Sendable {
    case empty
    case tooLong
    case unsupportedNumber
    case unsupportedDate
    case unsupportedPlace
    case unsupportedName
    case identityClaim
    case emotionalClaim
    case ranking
    case relationshipEvent
    case visualClaim
    case unsupportedSeason
    /// Called a trip when the story knows no trip.
    case unsupportedTrip
}

/// The words to show, the safe alternatives ("Try another"), and how they were reached.
public struct EditorialResult: Hashable, Codable, Sendable {
    /// What to show (the first safe variant).
    public var text: String
    /// Safe variants, the shown text first (at most three).
    public var variants: [String]
    /// "deterministic", or the model provider's name.
    public var provider: String
    /// A provider's candidates were refused or unavailable, and Relive's own words are shown.
    public var usedFallback: Bool
    public var rejections: [EditorialRejection]
}
