import Foundation

/// How a story card is composed. Every style draws every layout in its own way.
public enum StoryLayout: String, CaseIterable, Codable, Hashable, Sendable {
    /// Opening: the lead photo large, with the story's title.
    case cover
    /// Opening: the title leads, the photo framed smaller.
    case coverFramed
    /// One photo filling the card.
    case fullBleed
    /// One photo in its own shape, with room around it.
    case framed
    /// One photo with the place (or date) set large beside it.
    case postcard
    /// Two photos, evenly.
    case duo
    /// Two photos, one large and one smaller, offset.
    case duoOffset
    /// Three photos in an editorial arrangement.
    case trio
    /// Three photos as a strip (film frames, a contact sheet).
    case trioStrip
    /// Text only: a place or a date.
    case caption
    /// Text only, last.
    case closing

    /// How many photos the layout shows.
    public var photoCount: Int {
        switch self {
        case .cover, .coverFramed, .fullBleed, .framed, .postcard: 1
        case .duo, .duoOffset: 2
        case .trio, .trioStrip: 3
        case .caption, .closing: 0
        }
    }
}

public enum StoryCardRole: String, Codable, Hashable, Sendable {
    case opening
    case photo
    /// A place (or day) begins.
    case place
    case closing
}

/// One card of a designed story. Everything printed on it comes from its own photos (or, for
/// the opening and closing, from the whole story).
public struct StoryCard: Identifiable, Hashable, Sendable, Codable {
    public var id: Int
    public var role: StoryCardRole
    public var layout: StoryLayout
    public var photos: [AssetID]
    /// For a place card: the photos it introduces (its facts are theirs).
    public var describes: [AssetID]
    public var title: CreationTitle?
    public var dateSpan: DateSpan?
    public var place: PlaceName?
    public var coordinate: GeoCoordinate?
    /// "And that's our 2026." — only on the closing card of a year that really is one.
    public var closingYear: Int?
    public var showsDate: Bool
    public var showsPlace: Bool
    public var showsCoordinates: Bool

    public init(
        id: Int,
        role: StoryCardRole,
        layout: StoryLayout,
        photos: [AssetID],
        title: CreationTitle? = nil,
        dateSpan: DateSpan? = nil,
        place: PlaceName? = nil,
        coordinate: GeoCoordinate? = nil,
        closingYear: Int? = nil,
        showsDate: Bool = true,
        showsPlace: Bool = true,
        showsCoordinates: Bool = false,
        describes: [AssetID] = []
    ) {
        self.id = id
        self.role = role
        self.layout = layout
        self.photos = photos
        self.describes = describes
        self.title = title
        self.dateSpan = dateSpan
        self.place = place
        self.coordinate = coordinate
        self.closingYear = closingYear
        self.showsDate = showsDate
        self.showsPlace = showsPlace
        self.showsCoordinates = showsCoordinates
    }

    public var hasDate: Bool { dateSpan != nil }
    public var hasPlace: Bool { place != nil }
    public var hasCoordinates: Bool { coordinate != nil }
}

/// A story Relive designed: a style and a sequence of cards.
public struct StoryDesign: Hashable, Sendable, Codable {
    public var style: StoryStyle
    public var cards: [StoryCard]
    public var facts: CreationFacts
    /// Which "Make it for me" variation this is.
    public var variation: Int
    /// What the story was made from — a hint for its title, used only when every photo still
    /// belongs to it.
    public var source: CreationSource?

    /// Every photo used, in card order.
    public var photoIDs: [AssetID] {
        var seen = Set<AssetID>()
        return cards.flatMap(\.photos).filter { seen.insert($0).inserted }
    }
}

/// Designs a story from real memories: an opening, a sequence of photo cards that varies with the
/// photos (heroes, pairs, trios, a place card where the place really changes) and a quiet,
/// factual close. Deterministic: the same photos, style and variation give the same story.
public struct StoryDesigner: Sendable {
    public static let cardRange = 3...7
    /// Photos a story draws from.
    public static let maximumPhotos = 10

    public var library: CreationLibrary

    public init(library: CreationLibrary) {
        self.library = library
    }

    // MARK: - Photos

    /// The photos a story from `source` uses, in the order they were taken.
    public func photos(for source: CreationSource, excluding: Set<AssetID> = []) -> [AssetID] {
        let pool: [AssetID]
        switch source {
        case .photos(let ids):
            pool = library.initialPhotos(for: .photos(ids.filter { !excluding.contains($0) }), limit: Self.maximumPhotos)
        default:
            let available = library.availablePhotos(for: source).filter { !excluding.contains($0) }
            if case .moment(let id) = source, let moment = library.story.moment(id: id) {
                let lead = library.lead(of: moment).flatMap { excluding.contains($0) ? nil : $0 }
                pool = library.spreadPick(available, count: Self.maximumPhotos, include: lead)
            } else {
                let highlights = library.initialPhotos(for: source, limit: Self.maximumPhotos).filter { !excluding.contains($0) }
                pool = highlights.count >= CreationLimits.story.lowerBound ? highlights : library.spreadPick(available, count: Self.maximumPhotos)
            }
        }
        return pool.sorted(by: library.chronologicalOrder)
    }

    // MARK: - Design

    public func design(
        source: CreationSource,
        style: StoryStyle,
        variation: Int = 0,
        excluding: Set<AssetID> = []
    ) -> Result<StoryDesign, CreationShortfall> {
        let pool = photos(for: source, excluding: excluding)
        guard pool.count >= CreationLimits.story.lowerBound else {
            return .failure(.notEnoughPhotos(available: pool.count, required: CreationLimits.story.lowerBound))
        }
        let facts = library.facts(for: source, photos: pool)
        return .success(arrange(pool, facts: facts, source: source, style: style, variation: variation))
    }

    /// "Make it for me": picks the style that suits these photos (each further variation tries
    /// the next one, with a different lead photo), and designs the story in it.
    public func makeItForMe(source: CreationSource, variation: Int, excluding: Set<AssetID> = []) -> Result<StoryDesign, CreationShortfall> {
        let pool = photos(for: source, excluding: excluding)
        guard pool.count >= CreationLimits.story.lowerBound else {
            return .failure(.notEnoughPhotos(available: pool.count, required: CreationLimits.story.lowerBound))
        }
        let facts = library.facts(for: source, photos: pool)
        let styles = rankedStyles(for: pool, facts: facts)
        let style = styles[variation % styles.count]
        return .success(arrange(pool, facts: facts, source: source, style: style, variation: variation))
    }

    /// Styles in the order they suit these photos, from what is known about them: a real place
    /// suits Travel, many dates suit Film's contact sheets, a strong portrait suits Editorial,
    /// a few portraits suit Romantic, and Minimal suits anything. Never from guesses about
    /// feelings.
    public func rankedStyles(for photos: [AssetID], facts: CreationFacts) -> [StoryStyle] {
        let assets = photos.compactMap(library.creationAsset)
        let portraits = assets.filter { $0.orientation?.isPortrait == true }.count
        let landscapes = assets.filter { $0.orientation?.isLandscape == true }.count
        let days = Set(assets.compactMap { $0.creationDate.map { library.calendar.startOfDay(for: $0) } }).count
        let leadQuality = library.best(photos).map(library.quality) ?? 0

        var scores: [StoryStyle: Double] = [.minimal: 1.0, .film: 0.5, .travel: 0.3, .romantic: 0.4, .editorial: 0.6]
        if facts.place != nil { scores[.travel, default: 0] += 1.4 }
        if facts.coordinate != nil { scores[.travel, default: 0] += 0.3 }
        if landscapes > portraits { scores[.travel, default: 0] += 0.4; scores[.film, default: 0] += 0.3 }
        if days >= 3 { scores[.film, default: 0] += 0.9 }
        if photos.count >= 6 { scores[.editorial, default: 0] += 0.5 }
        if leadQuality >= 0.6 { scores[.editorial, default: 0] += 0.4 }
        if portraits >= max(2, landscapes * 2) { scores[.romantic, default: 0] += 0.7; scores[.editorial, default: 0] += 0.3 }
        if photos.count <= 4 { scores[.minimal, default: 0] += 0.6 }

        return StoryStyle.allCases.sorted { lhs, rhs in
            let left = scores[lhs] ?? 0, right = scores[rhs] ?? 0
            if abs(left - right) > 1e-9 { return left > right }
            return StoryStyle.allCases.firstIndex(of: lhs)! < StoryStyle.allCases.firstIndex(of: rhs)!
        }
    }

    // MARK: - Arrangement

    private struct Segment {
        var key: String
        var photos: [AssetID]
    }

    func arrange(_ pool: [AssetID], facts: CreationFacts, source: CreationSource, style: StoryStyle, variation: Int) -> StoryDesign {
        let lead = leadPhoto(pool, variation: variation)
        var body = pool.filter { $0 != lead }
        let closing = closingCard(facts: facts, source: source)
        let reserved = 1 + (closing == nil ? 0 : 1)

        var placeStarts: [AssetID: Segment] = [:]
        var chunks: [[AssetID]] = []
        var hero: AssetID?
        func tooMany() -> Bool { reserved + placeStarts.count + chunks.count > Self.cardRange.upperBound }
        func plan() {
            let segments = self.segments(body)
            placeStarts = placeSegments(segments, facts: facts)
            hero = library.best(body)
            chunks = chunk(body, hero: hero, segments: segments, variation: variation)
            while tooMany(), let merged = merge(chunks, sameSegmentOnly: true, keeping: hero) { chunks = merged }
        }
        plan()
        // Too many cards: leave out the weakest extra photo (never the hero, never a photo that
        // opens a place) rather than a place card; then, if still needed, fewer place cards and
        // fuller cards across moments.
        while tooMany(), let weakest = weakestRemovable(body, keeping: Set(placeStarts.keys).union(hero.map { [$0] } ?? [])) {
            body.removeAll { $0 == weakest }
            plan()
        }
        while tooMany(), let first = placeStarts.keys.sorted(by: library.chronologicalOrder).last { placeStarts.removeValue(forKey: first) }
        while tooMany(), let merged = merge(chunks, sameSegmentOnly: false, keeping: hero) ?? merge(chunks, sameSegmentOnly: false, keeping: nil) {
            chunks = merged
        }
        // And never fewer than three cards.
        while reserved + placeStarts.count + chunks.count < Self.cardRange.lowerBound, let split = split(chunks) {
            chunks = split
        }

        var cards: [StoryCard] = []
        func append(_ card: StoryCard) {
            var card = card
            card.id = cards.count
            cards.append(card)
        }

        let opening = StoryCard(
            id: 0, role: .opening, layout: style == .minimal && variation % 2 == 1 ? .coverFramed : .cover,
            photos: [lead], title: facts.title, dateSpan: facts.dateSpan, place: facts.place, coordinate: facts.coordinate,
            showsCoordinates: style == .travel && facts.coordinate != nil
        )
        append(opening)

        for photos in chunks {
            if let segment = photos.first.flatMap({ placeStarts[$0] }) {
                let summary = library.metadata(of: segment.photos)
                append(StoryCard(
                    id: 0, role: .place, layout: .caption,
                    photos: [], title: summary.place.map { .named($0.name) }, dateSpan: summary.dateSpan,
                    place: summary.place, coordinate: summary.coordinate, showsCoordinates: style == .travel && summary.coordinate != nil,
                    describes: segment.photos
                ))
            }
            append(photoCard(photos, style: style))
        }
        if let closing { append(closing) }

        return StoryDesign(style: style, cards: cards, facts: facts, variation: variation, source: source)
    }

    /// Segments where a real place begins (keyed by their first photo) — never more than two.
    private func placeSegments(_ segments: [Segment], facts: CreationFacts) -> [AssetID: Segment] {
        guard segments.count > 1 else { return [:] }
        var starts: [AssetID: Segment] = [:]
        var previousPlace = facts.place?.comparisonKey
        for segment in segments {
            let place = library.metadata(of: segment.photos).place
            if let place, place.comparisonKey != previousPlace, starts.count < 2, let first = segment.photos.first {
                starts[first] = segment
            }
            previousPlace = place?.comparisonKey ?? previousPlace
        }
        return starts
    }

    /// The lowest-quality photo that may be left out (latest on ties). Nil when the story is
    /// already down to three photos besides its lead.
    private func weakestRemovable(_ body: [AssetID], keeping kept: Set<AssetID>) -> AssetID? {
        guard body.count > 3 else { return nil }
        return body.filter { !kept.contains($0) }.min { lhs, rhs in
            let left = library.quality(lhs), right = library.quality(rhs)
            if abs(left - right) > 1e-9 { return left < right }
            return !library.chronologicalOrder(lhs, rhs)
        }
    }

    /// The opening photo: a strong one that suits a tall card. Variations take the next best.
    private func leadPhoto(_ pool: [AssetID], variation: Int) -> AssetID {
        let ranked = pool.sorted { lhs, rhs in
            let left = leadScore(lhs), right = leadScore(rhs)
            if abs(left - right) > 1e-9 { return left > right }
            return library.chronologicalOrder(lhs, rhs)
        }
        return ranked[variation % min(3, ranked.count)]
    }

    private func leadScore(_ id: AssetID) -> Double {
        let shape = library.creationAsset(id)?.orientation
        return library.quality(id) + (shape?.isLandscape == true ? 0 : 0.15)
    }

    /// Consecutive photos of one moment (or, outside the story, one day).
    private func segments(_ photos: [AssetID]) -> [Segment] {
        var segments: [Segment] = []
        for id in photos {
            let asset = library.creationAsset(id)
            let key: String
            if let moment = asset?.momentID {
                key = "moment-\(moment.uuidString)"
            } else if let date = asset?.creationDate {
                let day = library.calendar.dateComponents([.year, .month, .day], from: date)
                key = "day-\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
            } else {
                key = "undated"
            }
            if segments.last?.key == key {
                segments[segments.count - 1].photos.append(id)
            } else {
                segments.append(Segment(key: key, photos: [id]))
            }
        }
        return segments
    }

    /// Groups the body into cards: the strongest photo alone, neighbours of one segment in
    /// pairs (two landscapes stack, two portraits sit side by side), the rest alone.
    /// Odd variations keep landscapes on their own.
    private func chunk(_ body: [AssetID], hero: AssetID?, segments: [Segment], variation: Int) -> [[AssetID]] {
        guard !body.isEmpty else { return [] }
        var chunks: [[AssetID]] = []
        for segment in segments {
            var index = 0
            let photos = segment.photos
            while index < photos.count {
                let id = photos[index]
                if id != hero, index + 1 < photos.count, photos[index + 1] != hero,
                   !(variation % 2 == 1 && isLandscape(id) && isLandscape(photos[index + 1])) {
                    chunks.append([id, photos[index + 1]])
                    index += 2
                } else {
                    chunks.append([id])
                    index += 1
                }
            }
        }
        return chunks
    }

    /// Merges two neighbouring cards into one of at most three photos (optionally only within
    /// one moment, and leaving the hero's own card alone). Nil when nothing can merge.
    private func merge(_ chunks: [[AssetID]], sameSegmentOnly: Bool, keeping hero: AssetID?) -> [[AssetID]]? {
        let segmentKey: (AssetID) -> String = { id in
            self.library.creationAsset(id)?.momentID?.uuidString ?? "-"
        }
        for index in chunks.indices.dropLast() {
            let combined = chunks[index] + chunks[index + 1]
            guard combined.count <= 3 else { continue }
            if let hero, combined.contains(hero) { continue }
            if sameSegmentOnly, Set(combined.map(segmentKey)).count > 1 { continue }
            var merged = chunks
            merged.replaceSubrange(index...(index + 1), with: [combined])
            return merged
        }
        return nil
    }

    /// Splits the fullest card in two. Nil when every card holds one photo.
    private func split(_ chunks: [[AssetID]]) -> [[AssetID]]? {
        guard let index = chunks.indices.max(by: { chunks[$0].count < chunks[$1].count }), chunks[index].count > 1 else { return nil }
        var result = chunks
        let chunk = chunks[index]
        result.replaceSubrange(index...index, with: [[chunk[0]], Array(chunk.dropFirst())])
        return result
    }

    private func isLandscape(_ id: AssetID) -> Bool {
        library.creationAsset(id)?.orientation?.isLandscape == true
    }

    private func photoCard(_ photos: [AssetID], style: StoryStyle) -> StoryCard {
        let summary = library.metadata(of: photos)
        let layout: StoryLayout
        switch photos.count {
        case 1:
            let landscape = isLandscape(photos[0])
            switch style {
            case .travel, .editorial: layout = landscape ? .framed : .fullBleed
            case .minimal, .film, .romantic: layout = .framed
            }
        case 2:
            layout = style == .editorial || style == .romantic ? .duoOffset : .duo
        default:
            layout = style == .film ? .trioStrip : .trio
        }
        return StoryCard(
            id: 0, role: .photo, layout: layout, photos: photos,
            dateSpan: summary.dateSpan, place: summary.place, coordinate: summary.coordinate
        )
    }

    /// A quiet close with the story's own facts: "And that's our 2026." for a year that really
    /// is one; otherwise its place and dates. None when there is nothing true to say.
    func closingCard(facts: CreationFacts, source: CreationSource) -> StoryCard? {
        if case .year(let year) = source, facts.title == .year(year),
           YearInReviewBuilder(library: library).review(for: year).isSufficient {
            return StoryCard(id: 0, role: .closing, layout: .closing, photos: [], dateSpan: facts.dateSpan, closingYear: year)
        }
        guard facts.dateSpan != nil || facts.place != nil else { return nil }
        return StoryCard(id: 0, role: .closing, layout: .closing, photos: [], dateSpan: facts.dateSpan, place: facts.place)
    }

    // MARK: - Editing

    /// The layouts a card can switch to: those that show the same number of photos, in the same
    /// role.
    public static func alternatives(for card: StoryCard) -> [StoryLayout] {
        switch card.role {
        case .opening: return [.cover, .coverFramed]
        case .closing: return [.closing]
        case .place: return [.caption]
        case .photo:
            switch card.photos.count {
            case 1: return card.hasPlace || card.hasDate ? [.fullBleed, .framed, .postcard] : [.fullBleed, .framed]
            case 2: return [.duo, .duoOffset]
            default: return [.trio, .trioStrip]
            }
        }
    }
}

// MARK: - Light editing

extension StoryDesign {
    /// The next layout for a card (Change Layout). False when it has no other.
    @discardableResult
    public mutating func cycleLayout(of cardID: Int) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return false }
        let options = StoryDesigner.alternatives(for: cards[index])
        guard options.count > 1 else { return false }
        let current = options.firstIndex(of: cards[index].layout) ?? -1
        cards[index].layout = options[(current + 1) % options.count]
        return true
    }

    /// Puts `newID` in a card's slot. Every card's facts follow the story's new photos.
    @discardableResult
    public mutating func replacePhoto(cardID: Int, slot: Int, with newID: AssetID, library: CreationLibrary) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }), cards[index].photos.indices.contains(slot),
              library.isUsable(newID), !photoIDs.contains(newID) else { return false }
        let oldID = cards[index].photos[slot]
        cards[index].photos[slot] = newID
        for other in cards.indices {
            cards[other].describes = cards[other].describes.map { $0 == oldID ? newID : $0 }
        }
        if !StoryDesigner.alternatives(for: cards[index]).contains(cards[index].layout) {
            cards[index].layout = StoryDesigner.alternatives(for: cards[index])[0]
        }
        refreshFacts(library: library)
        return true
    }

    /// Removes a card. The opening stays, and a story keeps at least two cards. With a library,
    /// the remaining cards' facts follow the story's remaining photos.
    @discardableResult
    public mutating func removeCard(_ cardID: Int, library: CreationLibrary? = nil) -> Bool {
        guard cards.count > 2, let index = cards.firstIndex(where: { $0.id == cardID }), cards[index].role != .opening else { return false }
        cards.remove(at: index)
        if let library { refreshFacts(library: library) }
        return true
    }

    /// Recomputes what every card says from the photos it now shows — the one rule for creation
    /// metadata. The opening and closing describe the whole story; a photo card its photos; a
    /// place card the photos it introduces. The user's show/hide choices stay.
    public mutating func refreshFacts(library: CreationLibrary) {
        let all = photoIDs
        let storyFacts = source.map { library.facts(for: $0, photos: all) } ?? library.facts(forPhotos: all)
        facts = storyFacts
        let closing = StoryDesigner(library: library).closingCard(facts: storyFacts, source: source ?? .photos(all))
        var removeClosing = false
        for index in cards.indices {
            switch cards[index].role {
            case .opening:
                cards[index].title = storyFacts.title
                cards[index].dateSpan = storyFacts.dateSpan
                cards[index].place = storyFacts.place
                cards[index].coordinate = storyFacts.coordinate
            case .photo:
                let summary = library.metadata(of: cards[index].photos)
                cards[index].dateSpan = summary.dateSpan
                cards[index].place = summary.place
                cards[index].coordinate = summary.coordinate
            case .place:
                let subjects = cards[index].describes.filter(all.contains)
                let summary = library.metadata(of: subjects)
                cards[index].title = summary.place.map { .named($0.name) }
                cards[index].dateSpan = summary.dateSpan
                cards[index].place = summary.place
                cards[index].coordinate = summary.coordinate
            case .closing:
                if let closing {
                    cards[index].dateSpan = closing.dateSpan
                    cards[index].place = closing.place
                    cards[index].closingYear = closing.closingYear
                } else {
                    removeClosing = true
                }
            }
        }
        // Nothing true left to close with: no closing card.
        if removeClosing, cards.count > 2 { cards.removeAll { $0.role == .closing } }
    }

    /// The story without photos that are gone: they leave their cards, a card left empty goes,
    /// and a missing opening photo gives way to the strongest remaining one. Nothing is replaced
    /// with an unrelated photo.
    public mutating func removingPhotos(_ missing: Set<AssetID>, library: CreationLibrary) {
        guard !missing.isEmpty else { return }
        for index in cards.indices where cards[index].role == .photo {
            cards[index].photos.removeAll(where: missing.contains)
            if !cards[index].photos.isEmpty, !StoryDesigner.alternatives(for: cards[index]).contains(cards[index].layout) {
                cards[index].layout = StoryDesigner.alternatives(for: cards[index])[0]
            }
        }
        cards.removeAll { $0.role == .photo && $0.photos.isEmpty }
        if let opening = cards.firstIndex(where: { $0.role == .opening }), cards[opening].photos.contains(where: missing.contains) {
            let remaining = photoIDs.filter { !missing.contains($0) }
            if let lead = library.best(remaining) {
                cards[opening].photos = [lead]
                // The lead now opens the story; it doesn't also need its own card.
                if let solo = cards.firstIndex(where: { $0.role == .photo && $0.photos == [lead] }), cards.count > 3 {
                    cards.remove(at: solo)
                } else if let shared = cards.firstIndex(where: { $0.role == .photo && $0.photos.contains(lead) && $0.photos.count > 1 }) {
                    cards[shared].photos.removeAll { $0 == lead }
                    cards[shared].layout = StoryDesigner.alternatives(for: cards[shared])[0]
                }
            }
        }
        refreshFacts(library: library)
    }
}
