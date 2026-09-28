import Foundation

/// Coarse part of the day, used for factual names like "December Evening".
public enum PartOfDay: String, Sendable, CaseIterable {
    case morning
    case afternoon
    case evening
    case night

    public init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    public var displayName: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }
}

extension Calendar {
    /// The "day" a photo belongs to, where days start at `startHour` instead of midnight.
    /// A 00:40 photo from a night out belongs to the evening before, not the next day.
    func logicalDay(for date: Date, startHour: Int) -> Date {
        let shifted = date.addingTimeInterval(-Double(startHour) * 3600)
        return startOfDay(for: shifted)
    }

    func isSameLogicalDay(_ lhs: Date, _ rhs: Date, startHour: Int) -> Bool {
        logicalDay(for: lhs, startHour: startHour) == logicalDay(for: rhs, startHour: startHour)
    }

    /// Number of distinct logical days touched by the given dates.
    func logicalDayCount(_ dates: [Date], startHour: Int) -> Int {
        Set(dates.map { logicalDay(for: $0, startHour: startHour) }).count
    }

    /// (year, month) pair used for grouping.
    func yearMonth(of date: Date) -> YearMonth {
        let components = dateComponents([.year, .month], from: date)
        return YearMonth(year: components.year ?? 0, month: components.month ?? 0)
    }
}

struct YearMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

enum Statistics {
    /// Median of a non-empty collection; `nil` when empty.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
