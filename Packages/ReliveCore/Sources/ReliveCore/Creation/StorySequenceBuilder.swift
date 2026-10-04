import Foundation

/// The curated looks for 9:16 story cards.
public enum StoryStyle: String, CaseIterable, Codable, Hashable, Sendable {
    case minimal
    case film
    case travel
    case romantic
    case editorial

    public var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .film: "Film"
        case .travel: "Travel"
        case .romantic: "Romantic"
        case .editorial: "Editorial"
        }
    }
}

public enum StoryCardKind: String, Hashable, Sendable {
    /// Title card: the place or moment, and when.
    case opening
    /// A photo on its own.
    case photo
    /// A photo with the name of its moment (or its day, or month) — only where that changes.
    case memory
    /// Text only. Used to close a year.
    case closing
}

/// One card of a story, described by facts — the app decides how each style shows them.
public struct StoryCardPlan: Hashable, Sendable, Identifiable {
    public var id: Int
    public var kind: StoryCardKind
    public var assetID: AssetID?
    public var title: CreationTitle?
    public var dateSpan: DateSpan?
    public var place: PlaceName?
    public var coordinate: GeoCoordinate?
    /// When this card's photo was taken (for date-stamp styles).
    public var captureDate: Date?

    public init(
        id: Int,
        kind: StoryCardKind,
        assetID: AssetID?,
        title: CreationTitle? = nil,
        dateSpan: DateSpan? = nil,
        place: PlaceName? = nil,
        coordinate: GeoCoordinate? = nil,
        captureDate: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.assetID = assetID
        self.title = title
        self.dateSpan = dateSpan
        self.place = place
        self.coordinate = coordinate
        self.captureDate = captureDate
    }
}

public struct StorySequence: Hashable, Sendable {
    public var cards: [StoryCardPlan]
    public var facts: CreationFacts

    public var photoIDs: [AssetID] { cards.compactMap(\.assetID) }
}

/// Why something couldn't be made. Shown to the user as a gentle explanation.
public enum CreationShortfall: Error, Hashable, Sendable {
    case notEnoughPhotos(available: Int, required: Int)
}

/// Turns a moment, a set of photos, a month or a year into 3–6 story cards.
///
/// Deterministic, and factual: titles are names the story already has, dates are capture
/// dates, and a card says something only when the data does.
public struct StorySequenceBuilder: Sendable {
    public var library: CreationLibrary
    public var maximumCards: Int

    public init(library: CreationLibrary, maximumCards: Int = 6) {
        self.library = library
        self.maximumCards = maximumCards
    }

    /// - Parameter excluding: photos to leave out (e.g. ones that failed to load).
    public func sequence(for source: CreationSource, excluding: Set<AssetID> = []) -> Result<StorySequence, CreationShortfall> {
        let minimum = CreationLimits.story.lowerBound
        var pool = library.availablePhotos(for: source).filter { !excluding.contains($0) }
        switch source {
        case .photos: pool = Array(pool.prefix(CreationLimits.story.upperBound))
        case .favorites: pool = library.spreadPick(pool, count: CreationLimits.story.upperBound)
        default: break
        }
        guard pool.count >= minimum else {
            return .failure(.notEnoughPhotos(available: pool.count, required: minimum))
        }

        switch source {
        case .moment(let id):
            guard let moment = library.story.moment(id: id) else {
                return .failure(.notEnoughPhotos(available: 0, required: minimum))
            }
            var lead = library.lead(of: moment)
            if lead.map({ excluding.contains($0) }) ?? true { lead = library.best(pool) }
            return .success(byDay(pool: pool, lead: lead, facts: library.facts(for: moment)))

        case .photos, .favorites:
            let facts = library.facts(forPhotos: pool)
            let moments = Set(pool.compactMap { library.moment(containing: $0)?.id })
            if moments.count <= 1 {
                return .success(byDay(pool: pool, lead: library.best(pool), facts: facts))
            }
            return .success(byMoment(pool: pool, lead: library.best(pool), facts: facts, ordered: pool))

        case .trip:
            let ordered = library.initialPhotos(for: source, limit: .max).filter { !excluding.contains($0) }
            let facts = library.facts(for: source, photos: ordered)
            return .success(byMoment(pool: ordered, lead: library.best(ordered), facts: facts, ordered: ordered))

        case .month(let month):
            let recap = MonthlyRecapBuilder(library: library).recap(for: month)
            let ordered = recap.interleavedPhotos.filter { !excluding.contains($0) }
            let facts = library.facts(for: source, photos: ordered)
            return .success(byMoment(pool: ordered, lead: library.best(ordered), facts: facts, ordered: ordered))

        case .year(let year):
            let review = YearInReviewBuilder(library: library).review(for: year)
            let ordered = review.interleavedPhotos.filter { !excluding.contains($0) }
            let facts = library.facts(for: source, photos: ordered)
            guard let lead = library.best(ordered) else {
                return .failure(.notEnoughPhotos(available: 0, required: minimum))
            }
            let body = Array(ordered.filter { $0 != lead }.prefix(maximumCards - 2))
            return .success(assemble(lead: lead, facts: facts, body: body, closing: .year(year)) { id in
                guard let date = library.assets[id]?.creationDate else { return nil }
                let month = MonthKey(date: date, calendar: library.calendar)
                return Group(key: "\(month.year)-\(month.month)", title: .month(month), span: nil)
            })
        }
    }

    // MARK: - Arrangements

    /// For one moment or one day's photos: cards follow the days; a new day gets its date.
    private func byDay(pool: [AssetID], lead: AssetID?, facts: CreationFacts) -> StorySequence {
        let lead = lead ?? pool[0]
        let rest = pool.filter { $0 != lead }
        let body = library.spreadPick(rest, count: min(maximumCards - 1, rest.count))
        return assemble(lead: lead, facts: facts, body: body, closing: nil) { id in
            guard let date = library.assets[id]?.creationDate else { return nil }
            let day = library.calendar.dateComponents([.year, .month, .day], from: date)
            return Group(key: "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)", title: nil, span: DateSpan(start: date, end: date))
        }
    }

    /// For photos from several moments: each moment's first card names it.
    private func byMoment(pool: [AssetID], lead: AssetID?, facts: CreationFacts, ordered: [AssetID]) -> StorySequence {
        let lead = lead ?? pool[0]
        let candidates = ordered.filter { $0 != lead }
        let body = Array(interleaveByMoment(candidates).prefix(maximumCards - 1))
        return assemble(lead: lead, facts: facts, body: body, closing: nil) { id in
            guard let moment = library.moment(containing: id) else { return nil }
            let title = moment.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = library.assets[id]?.creationDate ?? moment.startDate
            return Group(
                key: moment.id.uuidString,
                title: title.isEmpty ? nil : .named(title),
                span: date.map { DateSpan(start: $0, end: $0) }
            )
        }
    }

    /// One photo per moment in turn, so the cards cover as many moments as possible.
    private func interleaveByMoment(_ ids: [AssetID]) -> [AssetID] {
        var groups: [MomentID?: [AssetID]] = [:]
        var order: [MomentID?] = []
        for id in ids {
            let key = library.moment(containing: id)?.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(id)
        }
        var result: [AssetID] = []
        var round = 0
        while result.count < ids.count {
            for key in order {
                if let group = groups[key], round < group.count {
                    result.append(group[round])
                }
            }
            round += 1
        }
        return result
    }

    struct Group {
        var key: String
        var title: CreationTitle?
        var span: DateSpan?
    }

    private func assemble(
        lead: AssetID,
        facts: CreationFacts,
        body: [AssetID],
        closing: CreationTitle?,
        group: (AssetID) -> Group?
    ) -> StorySequence {
        var cards = [StoryCardPlan(
            id: 0,
            kind: .opening,
            assetID: lead,
            title: facts.title,
            dateSpan: facts.dateSpan,
            place: facts.place,
            coordinate: facts.coordinate,
            captureDate: library.assets[lead]?.creationDate
        )]
        var previousKey = group(lead)?.key
        for id in body.sorted(by: library.chronologicalOrder) {
            let info = group(id)
            let date = library.assets[id]?.creationDate
            var card = StoryCardPlan(id: cards.count, kind: .photo, assetID: id, captureDate: date)
            if let info, info.key != previousKey {
                let title = info.title == facts.title ? nil : info.title
                if title != nil || info.span != nil {
                    card.kind = .memory
                    card.title = title
                    card.dateSpan = info.span
                }
            }
            previousKey = info?.key ?? previousKey
            cards.append(card)
        }
        if let closing {
            cards.append(StoryCardPlan(id: cards.count, kind: .closing, assetID: nil, title: closing))
        }
        return StorySequence(cards: cards, facts: facts)
    }
}
