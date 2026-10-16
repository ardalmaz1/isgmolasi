import Foundation

/// One entry in the timeline: a single moment, or a trip with its moments.
public enum TimelineItem: Identifiable, Hashable, Sendable {
    case moment(Moment)
    case chapter(Chapter, [Moment])

    public var id: String {
        switch self {
        case .moment(let moment): "moment-\(moment.id.uuidString)"
        case .chapter(let chapter, _): "chapter-\(chapter.id.uuidString)"
        }
    }

    public var moments: [Moment] {
        switch self {
        case .moment(let moment): [moment]
        case .chapter(_, let moments): moments
        }
    }
}

/// A year of the story (or the undated tail).
public struct TimelineSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var year: Int?
    public var items: [TimelineItem]
}

/// Arranges visible moments as Year → (Trip →) Moment, oldest first — a story reads from the
/// beginning. Trips with a single visible moment are shown as that moment.
public struct TimelineBuilder: Sendable {
    public var calendar: Calendar
    /// The section of memories from before the relationship's start.
    public static let beforeStartID = "before-start"

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// - Parameters:
    ///   - storyStart: the relationship's start, when the couple gave one. Moments from before
    ///     it are not part of "Together since…": they are gathered first, in their own section
    ///     titled `beforeStartTitle` ("Before March 2021"), never mixed into the years after.
    public func sections(for story: Story, isVisible: (Moment) -> Bool, storyStart: Date? = nil, beforeStartTitle: String = "Before") -> [TimelineSection] {
        let visible = story.moments.filter(isVisible)
        var items: [(date: Date?, item: TimelineItem)] = []
        var emittedChapters = Set<UUID>()

        for moment in visible {
            if let chapterID = moment.chapterID, let chapter = story.chapter(id: chapterID) {
                guard emittedChapters.insert(chapterID).inserted else { continue }
                let members = visible.filter { $0.chapterID == chapterID }
                if members.count > 1 {
                    items.append((chapter.startDate, .chapter(chapter, members)))
                } else {
                    items.append((moment.startDate, .moment(moment)))
                }
            } else {
                items.append((moment.startDate, .moment(moment)))
            }
        }

        var sections: [TimelineSection] = []
        if let startDay = storyStart.map({ calendar.startOfDay(for: $0) }) {
            let before = items.filter { entry in entry.date.map { $0 < startDay } ?? false }
            if !before.isEmpty {
                sections.append(TimelineSection(id: Self.beforeStartID, title: beforeStartTitle, year: nil, items: before.map(\.item)))
                items.removeAll { entry in entry.date.map { $0 < startDay } ?? false }
            }
        }
        for entry in items {
            let year = entry.date.map { calendar.component(.year, from: $0) }
            let id = year.map(String.init) ?? "undated"
            if sections.last?.id == id {
                sections[sections.count - 1].items.append(entry.item)
            } else {
                sections.append(TimelineSection(
                    id: id,
                    title: year.map(String.init) ?? "Without a date",
                    year: year,
                    items: [entry.item]
                ))
            }
        }
        return sections
    }
}
