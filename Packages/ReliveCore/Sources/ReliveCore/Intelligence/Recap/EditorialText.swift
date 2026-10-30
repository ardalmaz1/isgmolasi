import Foundation

/// The words of one recap chapter.
public struct EditorialText: Hashable, Sendable, Codable {
    public var eyebrow: String?
    public var title: String
    public var detail: String?

    public init(eyebrow: String? = nil, title: String, detail: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var all: [String] { [eyebrow, title, detail].compactMap { $0 } }
}

/// Everything a chapter may say, as structured facts — the only input a text provider gets.
/// No photos, coordinates, notes or identifiers: names Relive already shows, dates and counts.
public enum EditorialFacts: Hashable, Sendable, Codable {
    case monthOpening(monthName: String, year: Int, memories: Int, moments: Int, places: Int)
    case yearOpening(year: Int, memories: Int, moments: Int, months: Int)
    /// The earliest memory of the period.
    case firstMemory(periodName: String, isYear: Bool, dateLabel: String, place: String?)
    case trip(name: String, days: Int, memories: Int, dateLabel: String?)
    case repeatedPlace(place: String, moments: Int, days: Int, isYear: Bool)
    case busyDay(dateLabel: String, memories: Int, places: Int)
    /// Photos where on-device analysis found two or more faces. Never who.
    case people(count: Int)
    case favorites(count: Int)
    case frames(periodName: String, count: Int)
    case places(count: Int, isYear: Bool)
    case timeline(periodName: String, entries: Int)
    case numbers(year: Int)
    case monthByMonth(year: Int, months: Int)
    case compact(periodName: String, isYear: Bool, memories: Int, moments: Int)
    case closing(periodName: String, isYear: Bool, memories: Int, moments: Int, places: Int)

    /// Numbers a text may mention (anything else is a made-up number).
    var allowedNumbers: Set<Int> {
        switch self {
        case .monthOpening(_, let year, let memories, let moments, let places): [year, memories, moments, places]
        case .yearOpening(let year, let memories, let moments, let months): [year, memories, moments, months]
        case .firstMemory(let name, _, let label, _): Self.numbers(in: label).union(Self.numbers(in: name))
        case .trip(_, let days, let memories, let label): Set([days, memories]).union(label.map(Self.numbers) ?? [])
        case .repeatedPlace(_, let moments, let days, _): [moments, days]
        case .busyDay(let label, let memories, let places): Self.numbers(in: label).union([memories, places])
        // People photos are, by definition, photos with two or more faces ("Two in the frame").
        case .people(let count): [count, 2]
        case .favorites(let count): [count]
        case .frames(let name, let count): Self.numbers(in: name).union([count])
        case .places(let count, _): [count]
        case .timeline(let name, let entries): Self.numbers(in: name).union([entries])
        case .numbers(let year): [year]
        case .monthByMonth(let year, let months): [year, months]
        case .compact(let name, _, let memories, let moments): Self.numbers(in: name).union([memories, moments])
        case .closing(let name, _, let memories, let moments, let places): Self.numbers(in: name).union([memories, moments, places])
        }
    }

    static func numbers(in text: String) -> Set<Int> {
        Set(text.split { !$0.isNumber }.compactMap { Int($0) })
    }
}

/// Turns facts into words. The default is deterministic; a future AI provider would implement
/// the same protocol and be wrapped in `ValidatedEditorialTextProvider`, so it can only ever
/// rephrase facts — never add any.
public protocol EditorialTextProviding: Sendable {
    func text(for facts: EditorialFacts) -> EditorialText
}

/// Relive's own words: warm where it's safe, plain where it isn't, always true.
public struct DeterministicEditorialTextProvider: EditorialTextProviding {
    public init() {}

    public func text(for facts: EditorialFacts) -> EditorialText {
        switch facts {
        case .monthOpening(let month, let year, let memories, let moments, let places):
            return EditorialText(
                eyebrow: "\(month) \(year)",
                title: "\(month), together.",
                detail: Self.counts(memories: memories, moments: moments, places: places)
            )
        case .yearOpening(let year, let memories, let moments, let months):
            return EditorialText(
                eyebrow: "Our \(year)",
                title: "\(year), together.",
                detail: "\(Self.count(memories, "memory", "memories")) · \(Self.count(moments, "moment", "moments")) · \(Self.count(months, "month", "months"))"
            )
        case .firstMemory(let period, let isYear, let date, let place):
            return EditorialText(
                eyebrow: isYear ? "The first memory of \(period)" : "The beginning",
                title: isYear ? "The year began here." : "The month began here.",
                detail: [date, place].compactMap { $0 }.joined(separator: " · ")
            )
        case .trip(let name, let days, let memories, let date):
            let title = days >= 2 ? "\(Self.word(days).capitalizedFirst) days in \(name)." : "A day in \(name)."
            return EditorialText(
                eyebrow: "A trip",
                title: title,
                detail: [date, Self.count(memories, "memory", "memories")].compactMap { $0 }.joined(separator: " · ")
            )
        case .repeatedPlace(let place, let moments, let days, let isYear):
            return EditorialText(
                eyebrow: isYear ? "A place that kept appearing" : "A place, again",
                title: "\(place), again.",
                detail: "\(Self.count(moments, "moment", "moments")) on \(Self.count(days, "day", "different days"))"
            )
        case .busyDay(let date, let memories, let places):
            return EditorialText(
                eyebrow: "A day with more to remember",
                title: date,
                detail: places > 1
                    ? "\(Self.count(memories, "memory", "memories")) · \(Self.count(places, "place", "places"))"
                    : Self.count(memories, "memory", "memories")
            )
        case .people(let count):
            return EditorialText(eyebrow: "In the frame", title: "Two in the frame.", detail: Self.count(count, "photo", "photos"))
        case .favorites(let count):
            return EditorialText(eyebrow: "Marked as favorites", title: "The ones you kept close.", detail: Self.count(count, "favorite", "favorites"))
        case .frames(let period, let count):
            return EditorialText(eyebrow: "In frames", title: "\(period) in \(count) frames.")
        case .places(let count, let isYear):
            return EditorialText(eyebrow: "Places", title: "\(Self.word(count).capitalizedFirst) places this \(isYear ? "year" : "month").")
        case .timeline(let period, _):
            return EditorialText(eyebrow: "Chronology", title: "The shape of \(period).")
        case .numbers(let year):
            return EditorialText(eyebrow: "The year in numbers", title: "\(year), counted.")
        case .monthByMonth(_, _):
            return EditorialText(eyebrow: "Month by month", title: "Your year, month by month.")
        case .compact(let period, let isYear, let memories, let moments):
            return EditorialText(
                eyebrow: period,
                title: isYear ? "Your \(period) is just getting started." : "\(period) was a quiet one in Yuvi.",
                detail: "\(Self.count(memories, "memory", "memories")) · \(Self.count(moments, "moment", "moments"))"
            )
        case .closing(let period, _, let memories, let moments, let places):
            // No Relive branding: the recap is the couple's.
            return EditorialText(
                title: "That was your \(period).",
                detail: Self.counts(memories: memories, moments: moments, places: places)
            )
        }
    }

    static func counts(memories: Int, moments: Int, places: Int) -> String {
        var parts = [count(memories, "memory", "memories"), count(moments, "moment", "moments")]
        if places > 0 { parts.append(count(places, "place", "places")) }
        return parts.joined(separator: " · ")
    }

    static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }

    /// "four" for small numbers (titles read better), digits otherwise.
    static func word(_ value: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(value) ? words[value] : String(value)
    }
}

/// The factual contract for any non-deterministic provider (an on-device model): its text is used
/// only if the shared `EditorialValidator` accepts every part and it isn't empty — otherwise the
/// deterministic text is used instead.
public struct ValidatedEditorialTextProvider: EditorialTextProviding {
    public var candidate: any EditorialTextProviding
    public var fallback: any EditorialTextProviding

    public init(candidate: any EditorialTextProviding, fallback: any EditorialTextProviding = DeterministicEditorialTextProvider()) {
        self.candidate = candidate
        self.fallback = fallback
    }

    public func text(for facts: EditorialFacts) -> EditorialText {
        let proposed = candidate.text(for: facts)
        return Self.isAcceptable(proposed, for: facts) ? proposed : fallback.text(for: facts)
    }

    /// The shared editorial validator (`EditorialValidator`) on every part: no feelings or
    /// rankings, no number, date, place or name the facts don't hold.
    public static func isAcceptable(_ text: EditorialText, for facts: EditorialFacts) -> Bool {
        guard !text.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let context = facts.editorialContext()
        for part in text.all {
            if !EditorialValidator.rejections(in: part, context: context).isEmpty { return false }
        }
        return true
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
