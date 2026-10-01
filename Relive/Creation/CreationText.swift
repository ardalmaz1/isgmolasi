import Foundation
import ReliveCore

/// Words printed on creations, formatted from `CreationFacts`. Only real values are formatted;
/// every function returns nil when there is nothing true to say.
@MainActor
enum CreationText {
    enum TitleUse {
        /// The headline of a whole creation: "September Together", "Our 2026".
        case headline
        /// A label inside one: "September", "2026".
        case label
    }

    private static let monthFormatter = formatter("MMMM")
    private static let monthYearFormatter = formatter("MMMMyyyy")
    private static let dayFormatter = formatter("MMMMd")
    private static let dayYearFormatter = formatter("MMMMdyyyy")
    private static let shortMonthYearFormatter = formatter("MMMyyyy")

    private static let dayRangeFormatter: DateIntervalFormatter = interval("MMMMdyyyy")
    private static let monthRangeFormatter: DateIntervalFormatter = interval("MMMMyyyy")
    private static let yearRangeFormatter: DateIntervalFormatter = interval("yyyy")
    private static let shortDayRangeFormatter: DateIntervalFormatter = interval("MMMMd")

    static func title(_ title: CreationTitle?, use: TitleUse = .headline) -> String? {
        guard let title else { return nil }
        switch title {
        case .named(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .month(let month):
            guard let name = monthName(month) else { return nil }
            return use == .headline ? "\(name) Together" : name
        case .year(let year):
            return use == .headline ? "Our \(year)" : String(year)
        }
    }

    /// "August 6, 2026" · "August 6 – 9, 2026" · "June – August 2026" · "2025 – 2026".
    static func dateLine(_ span: DateSpan?) -> String? {
        guard let span else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(span.start, inSameDayAs: span.end) {
            return dayYearFormatter.string(from: span.start)
        }
        let start = calendar.dateComponents([.year, .month], from: span.start)
        let end = calendar.dateComponents([.year, .month], from: span.end)
        if start.year == end.year && start.month == end.month {
            return dayRangeFormatter.string(from: span.start, to: span.end)
        }
        if start.year == end.year {
            return monthRangeFormatter.string(from: span.start, to: span.end)
        }
        return yearRangeFormatter.string(from: span.start, to: span.end)
    }

    /// Coarser, for opening cards: "August 2026", or a range when the span crosses months.
    static func periodLine(_ span: DateSpan?) -> String? {
        guard let span else { return nil }
        let calendar = Calendar.current
        let start = calendar.dateComponents([.year, .month], from: span.start)
        let end = calendar.dateComponents([.year, .month], from: span.end)
        if start.year == end.year && start.month == end.month {
            return monthYearFormatter.string(from: span.start)
        }
        if start.year == end.year {
            return monthRangeFormatter.string(from: span.start, to: span.end)
        }
        return yearRangeFormatter.string(from: span.start, to: span.end)
    }

    /// For one card inside a story: "August 6", or "August 6 – 9".
    static func dayLine(_ span: DateSpan?) -> String? {
        guard let span else { return nil }
        if Calendar.current.isDate(span.start, inSameDayAs: span.end) {
            return dayFormatter.string(from: span.start)
        }
        return shortDayRangeFormatter.string(from: span.start, to: span.end)
    }

    static func monthName(_ month: MonthKey) -> String? {
        month.start(in: Calendar.current).map(monthFormatter.string(from:))
    }

    /// "September 2026"
    static func monthTitle(_ month: MonthKey) -> String {
        month.start(in: Calendar.current).map(monthYearFormatter.string(from:)) ?? "\(month.month)/\(month.year)"
    }

    /// "Kaş" — only the name; regions make captions long.
    static func place(_ place: PlaceName?) -> String? {
        guard let name = place?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    /// "36.20° N · 29.64° E"
    static func coordinate(_ coordinate: GeoCoordinate?) -> String? {
        guard let coordinate, coordinate.isValid else { return nil }
        let latitude = String(format: "%.2f° %@", abs(coordinate.latitude), coordinate.latitude >= 0 ? "N" : "S")
        let longitude = String(format: "%.2f° %@", abs(coordinate.longitude), coordinate.longitude >= 0 ? "E" : "W")
        return "\(latitude) · \(longitude)"
    }

    /// A camera-style date imprint from the photo's own capture date: "8 6 '26".
    static func filmStamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return String(format: "%d %d '%02d", month, day, year % 100)
    }

    /// "Aug 2026" in capitals, for film edges.
    static func filmEdge(_ span: DateSpan?) -> String? {
        span.map { shortMonthYearFormatter.string(from: $0.start).uppercased() }
    }

    /// "53 memories · 4 moments · 2 places" — only non-zero counts.
    static func counts(_ statistics: StoryStatistics, includeTrips: Bool = false) -> String {
        var parts = [Counted.text(statistics.memoryCount, "memory", "memories")]
        if statistics.momentCount > 0 { parts.append(Counted.text(statistics.momentCount, "moment", "moments")) }
        if includeTrips && statistics.chapterCount > 0 { parts.append(Counted.text(statistics.chapterCount, "trip", "trips")) }
        if statistics.placeCount > 0 { parts.append(Counted.text(statistics.placeCount, "place", "places")) }
        return parts.joined(separator: " · ")
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static func interval(_ template: String) -> DateIntervalFormatter {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = template
        return formatter
    }
}
