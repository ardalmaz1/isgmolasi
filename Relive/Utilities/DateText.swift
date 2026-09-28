import Foundation
import ReliveCore

/// Date strings used across the UI. Formatters follow the app's language and the user's region.
@MainActor
enum DateText {
    private static let dayFormatter = formatter("EEEEMMMMd")
    private static let dayYearFormatter = formatter("EEEEMMMMdyyyy")
    private static let monthYearFormatter = formatter("MMMMyyyy")
    private static let fullDateFormatter = formatter("MMMMdyyyy")
    private static let headerFormatter = formatter("EEEEMMMMd")

    private static let rangeFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "MMMMd"
        return formatter
    }()

    private static let rangeYearFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "MMMMdyyyy"
        return formatter
    }()

    /// "Friday, August 8" · "August 6 – 9" · nil for undated moments.
    static func range(start: Date?, end: Date?, includeYear: Bool = false) -> String? {
        guard let start else { return nil }
        let end = end ?? start
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) || end < start {
            return (includeYear ? dayYearFormatter : dayFormatter).string(from: start)
        }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let formatter = (includeYear || !sameYear) ? rangeYearFormatter : rangeFormatter
        return formatter.string(from: start, to: end)
    }

    /// "August 2025"
    static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    /// "March 14, 2021"
    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    /// "Monday, September 28"
    static func todayHeader(_ date: Date) -> String {
        headerFormatter.string(from: date)
    }

    /// How the relationship start reads, honest about precision: "March 14, 2021", "March 2021", "2021".
    static func relationshipStart(_ start: RelationshipStart) -> String {
        switch start.precision {
        case .day: return fullDate(start.date)
        case .month: return monthYear(start.date)
        case .year: return String(Calendar.current.component(.year, from: start.date))
        }
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

/// Counted nouns with thousands separators: "1 moment", "1,568 days".
enum Counted {
    static func text(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count.formatted()) \(count == 1 ? singular : plural)"
    }
}
