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

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func sections(for story: Story, isVisible: (Moment) -> Bool) -> [TimelineSection] {
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
