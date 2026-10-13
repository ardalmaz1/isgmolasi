import Foundation

/// An ordered photo sequence for stories, books and (later) Movie and Wrapped slides.
public struct MemorySequence: Hashable, Sendable, Codable {
    /// What changes when a section begins.
    public enum Transition: String, Hashable, Sendable, Codable {
        /// The first section.
        case start
        case newYear
        case newMonth
        case newDay
        case newPlace
        case newMoment
        /// The rest (photos outside the story, without dates).
        case none
    }

    /// Consecutive photos of one moment (or, outside the story, one day).
    public struct Section: Hashable, Sendable, Codable {
        public var assetIDs: [AssetID]
        public var transition: Transition
        public var momentID: MomentID?
        public var day: DayKey?
        /// The place every photo in the section shares, if any.
        public var place: PlaceName?
        /// The section's own period (its photos' dates only).
        public var period: PeriodDescriptor
    }

    /// The opener: the photo that leads (a cover, the first card).
    public var lead: AssetID?
    /// Lead first, then everything else in the order it was taken.
    public var ordered: [AssetID]
    /// The body (everything but the lead), chronological, in sections.
    public var sections: [Section]
    /// The last photo — the end of the story in time, never moved there for effect.
    public var closer: AssetID?
}

/// Orders memories: the lead opens, the rest follow in the order they were taken. Time is never
/// scrambled for looks; sections and transitions say where a new moment, day, month, year or
/// place begins.
public struct MemorySequencePlanner: Sendable {
    public init() {}

    public func sequence(_ candidates: [MemoryCandidate], lead: AssetID?) -> MemorySequence {
        let chronological = candidates.sorted { ($0.captureIndex, $0.assetID) < ($1.captureIndex, $1.assetID) }
        let body = chronological.filter { $0.assetID != lead }

        var sections: [MemorySequence.Section] = []
        var current: [MemoryCandidate] = []
        var previous: MemoryCandidate?
        func close() {
            guard let first = current.first else { return }
            sections.append(MemorySequence.Section(
                assetIDs: current.map(\.assetID),
                transition: sections.isEmpty ? .start : Self.transition(from: previous, to: first),
                momentID: first.momentID,
                day: current.allSatisfy({ $0.day == first.day }) ? first.day : nil,
                place: PeriodDescriptor(candidates: current).commonPlace,
                period: PeriodDescriptor(candidates: current)
            ))
            previous = current.last
            current = []
        }
        for candidate in body {
            if let last = current.last, Self.sectionKey(last) != Self.sectionKey(candidate) {
                close()
            }
            current.append(candidate)
        }
        close()

        let ordered = (lead.map { [$0] } ?? []) + body.map(\.assetID)
        return MemorySequence(lead: lead, ordered: ordered, sections: sections, closer: body.last?.assetID ?? lead)
    }

    /// Photos of one moment stay together; outside the story, photos of one day do.
    static func sectionKey(_ candidate: MemoryCandidate) -> String {
        if let moment = candidate.momentID { return "m:\(moment.uuidString)" }
        if let day = candidate.day { return "d:\(day.year)-\(day.month)-\(day.day)" }
        return "none"
    }

    /// The largest change between two consecutive photos, from their own data only.
    static func transition(from previous: MemoryCandidate?, to next: MemoryCandidate) -> MemorySequence.Transition {
        guard let previous else { return .start }
        if let a = previous.day, let b = next.day {
            if a.year != b.year { return .newYear }
            if a.month != b.month { return .newMonth }
            if a.day != b.day { return .newDay }
        }
        if let a = previous.place?.comparisonKey, let b = next.place?.comparisonKey, a != b { return .newPlace }
        if previous.momentID != next.momentID, next.momentID != nil { return .newMoment }
        return .none
    }
}

/// A kind of creation the memories suit.
public enum CreationKind: String, Hashable, Sendable, Codable, CaseIterable {
    case collage
    case story
    case book
    case monthlyRecap
    case yearInReview
    /// Not built yet: listed so the plan can say when a set would suit a Memory Movie.
    case movieFuture
}

/// A suggestion, never a requirement: the user can always make something else.
public struct CreationRecommendation: Hashable, Sendable, Codable {
    public enum Reason: String, Hashable, Sendable, Codable {
        /// A few strong photos.
        case fewStrongPhotos
        /// Photos with a clear order in time.
        case clearSequence
        /// Many photos across several moments.
        case manyMoments
        /// A month with enough in it for a recap.
        case fullMonth
        /// A year with memories from several months.
        case spreadAcrossYear
        /// A large, varied trip.
        case largeTrip
    }

    public var kind: CreationKind
    public var reason: Reason
    /// False for kinds Relive can't make yet (`movieFuture`).
    public var isAvailable: Bool
}

/// Which creations a set of memories suits. Thresholds follow the existing creation limits and
/// recap rules, so a recommendation is never something the builders would then refuse.
public enum CreationRecommender {
    public static func recommendations(
        distinct: [MemoryCandidate],
        period: PeriodDescriptor,
        monthlyMinimum: Int = 4,
        yearMinimumMemories: Int = 8,
        yearMinimumMoments: Int = 2,
        yearMinimumMonths: Int = 2
    ) -> [CreationRecommendation] {
        let count = distinct.count
        let moments = Set(distinct.compactMap(\.momentID)).count
        let days = Set(distinct.compactMap(\.day)).count
        let months = Set(distinct.compactMap(\.month)).count
        let trip = distinct.first?.tripID.flatMap { id in distinct.allSatisfy { $0.tripID == id } ? id : nil }
        var result: [CreationRecommendation] = []

        if count >= BookLimits.minimumPhotos, moments >= 2 || days >= 2 {
            result.append(.init(kind: .book, reason: .manyMoments, isAvailable: true))
        }
        if count >= CreationLimits.story.lowerBound, days >= 2 || moments >= 2 || count >= 5 {
            result.append(.init(kind: .story, reason: .clearSequence, isAvailable: true))
        }
        if period.isComplete, period.singleMonth != nil, count >= monthlyMinimum {
            result.append(.init(kind: .monthlyRecap, reason: .fullMonth, isAvailable: true))
        }
        if period.isComplete, period.singleYear != nil, months >= yearMinimumMonths,
           count >= yearMinimumMemories, moments >= yearMinimumMoments {
            result.append(.init(kind: .yearInReview, reason: .spreadAcrossYear, isAvailable: true))
        }
        if count >= CreationLimits.collage.lowerBound {
            // A collage suits a handful best; with many photos it's still possible, just later.
            let reason: CreationRecommendation.Reason = count <= 6 ? .fewStrongPhotos : .clearSequence
            let collage = CreationRecommendation(kind: .collage, reason: reason, isAvailable: true)
            if count <= 6 { result.insert(collage, at: 0) } else { result.append(collage) }
        }
        if trip != nil, count >= 15, days >= 3 {
            result.append(.init(kind: .movieFuture, reason: .largeTrip, isAvailable: false))
        }
        if count >= CreationLimits.story.lowerBound, count < 5, days < 2, moments < 2,
           !result.contains(where: { $0.kind == .story }) {
            // Three or four photos of one sitting still make a short story.
            result.append(.init(kind: .story, reason: .clearSequence, isAvailable: true))
        }
        return result
    }
}
