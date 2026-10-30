import Foundation

/// Plain, factual "how long ago" labels: "2 years ago", "A year ago this week", "5 months ago".
public struct RelativeAgeDescriber: Sendable {
    public var calendar: Calendar
    /// Within this many days of the same calendar date, add "this week".
    public var anniversaryWindowDays: Int

    public init(calendar: Calendar, anniversaryWindowDays: Int = 3) {
        self.calendar = calendar
        self.anniversaryWindowDays = anniversaryWindowDays
    }

    public func describe(_ date: Date, now: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        let days = components.day ?? 0

        let w = CoreWords()
        if years >= 1 {
            let base = years == 1 ? w.pick("A year ago", "Bir yıl önce") : w.pick("\(years) years ago", "\(years) yıl önce")
            return isNearAnniversary(date, now: now) ? w.pick("\(base) this week", "\(base) bu hafta") : base
        }
        if months >= 1 {
            return months == 1 ? w.pick("A month ago", "Bir ay önce") : w.pick("\(months) months ago", "\(months) ay önce")
        }
        if days >= 14 {
            return w.pick("A few weeks ago", "Birkaç hafta önce")
        }
        return w.pick("Recently", "Yakın zamanda")
    }

    /// True when `date` falls within the window around the same day in the current year.
    public func isNearAnniversary(_ date: Date, now: Date) -> Bool {
        let years = calendar.dateComponents([.year], from: date, to: now).year ?? 0
        guard years >= 1 else { return false }
        for offset in [years, years + 1] {
            guard let shifted = calendar.date(byAdding: .year, value: offset, to: date) else { continue }
            let distance = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: shifted), to: calendar.startOfDay(for: now)).day ?? Int.max)
            if distance <= anniversaryWindowDays { return true }
        }
        return false
    }
}
