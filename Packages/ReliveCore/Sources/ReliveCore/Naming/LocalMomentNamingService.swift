import Foundation

/// Deterministic, factual names built from dates and places only.
///
/// Examples:
/// - With a place away from home: "Kaş" / "August 2025"
/// - At home (the place isn't what's distinctive): named by time, e.g. "June Evening"
/// - Inside a trip, same place as the trip: "Friday Evening" / "August 8"
/// - Inside a trip, somewhere else: "Kekova" / "August 8"
/// - No place, part of a day: "December Evening" / "December 2024"
/// - No place, a whole day: "A Saturday in August" / "August 2025"
/// - No place, several days over a weekend: "August Weekend" / "August 2025"
/// - Gathered small moments: "Moments from March" / "2024"
/// - December 31 evening: "New Year's Eve" / "2024"
public struct LocalMomentNamingService: MomentNamingService {
    public var calendar: Calendar
    public var locale: Locale
    public var logicalDayStartHour: Int
    /// Single-day moments spanning at least this long are named after the whole day.
    public var wholeDayThreshold: TimeInterval

    public init(
        calendar: Calendar,
        locale: Locale = .reliveDisplay,
        logicalDayStartHour: Int = 4,
        wholeDayThreshold: TimeInterval = 5 * 3600
    ) {
        self.calendar = calendar
        self.locale = locale
        self.logicalDayStartHour = logicalDayStartHour
        self.wholeDayThreshold = wholeDayThreshold
    }

    public func title(for context: MomentNamingContext) async -> MomentTitle {
        makeTitle(for: context)
    }

    public func title(forChapter context: ChapterNamingContext) async -> MomentTitle {
        makeChapterTitle(for: context)
    }

    // MARK: - Synchronous core (also used by tests)

    public func makeTitle(for context: MomentNamingContext) -> MomentTitle {
        guard let start = context.start else {
            return MomentTitle(primary: words.undated)
        }
        let end = context.end ?? start
        let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)

        switch context.kind {
        case .undated:
            return MomentTitle(primary: words.undated)
        case .collection:
            return MomentTitle(primary: words.momentsFrom(monthName(start)), secondary: yearString(start))
        case .event:
            break
        }

        if context.isInChapter {
            let dayLabel = dayMonth(start)
            if let place = context.place, place.comparisonKey != context.chapterPlace?.comparisonKey {
                return MomentTitle(primary: place.name, secondary: dayLabel)
            }
            return MomentTitle(primary: timeOfDayName(start: start, end: end, middle: middle), secondary: dayLabel)
        }

        if let place = context.place, !context.isAtHome {
            return MomentTitle(primary: place.name, secondary: monthYear(start))
        }

        if let holiday = holidayName(start: start, end: end) {
            return MomentTitle(primary: holiday, secondary: yearString(start))
        }

        let days = calendar.logicalDayCount([start, end], startHour: logicalDayStartHour)
        if days > 1 {
            let touchesWeekend = coversWeekend(start: start, end: end)
            let primary = touchesWeekend ? words.weekend(monthName(start)) : words.fewDays(in: monthName(start))
            return MomentTitle(primary: primary, secondary: monthYear(start))
        }

        if end.timeIntervalSince(start) >= wholeDayThreshold {
            let weekday = calendar.isDateInWeekend(middle) ? weekdayName(middle) : nil
            return MomentTitle(primary: words.day(weekday, in: monthName(start)), secondary: monthYear(start))
        }

        let part = PartOfDay(hour: calendar.component(.hour, from: middle))
        return MomentTitle(primary: words.part(part, of: monthName(start)), secondary: monthYear(start))
    }

    public func makeChapterTitle(for context: ChapterNamingContext) -> MomentTitle {
        let secondary = monthRange(start: context.start, end: context.end)
        if let place = context.place {
            return MomentTitle(primary: place.name, secondary: secondary)
        }
        return MomentTitle(primary: words.fewDaysAway, secondary: secondary)
    }

    // MARK: - Pieces

    private func timeOfDayName(start: Date, end: Date, middle: Date) -> String {
        let weekday = weekdayName(middle)
        if end.timeIntervalSince(start) >= wholeDayThreshold {
            return weekday
        }
        return words.part(PartOfDay(hour: calendar.component(.hour, from: middle)), of: weekday)
    }

    private func holidayName(start: Date, end: Date) -> String? {
        let logicalStart = calendar.logicalDay(for: start, startHour: logicalDayStartHour)
        let components = calendar.dateComponents([.month, .day], from: logicalStart)
        let hour = calendar.component(.hour, from: end)
        let endsLate = hour >= 18 || hour < logicalDayStartHour
        if components.month == 12, components.day == 31, endsLate {
            return words.newYearsEve
        }
        return nil
    }

    private func coversWeekend(start: Date, end: Date) -> Bool {
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            if calendar.isDateInWeekend(day) { return true }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }

    private var words: NamingWords { NamingWords(language: EditorialLanguage(locale: locale)) }

    private func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    func monthName(_ date: Date) -> String { formatter("MMMM").string(from: date) }
    func weekdayName(_ date: Date) -> String { formatter("EEEE").string(from: date) }
    func monthYear(_ date: Date) -> String { formatter("MMMMyyyy").string(from: date) }
    func dayMonth(_ date: Date) -> String { formatter("MMMMd").string(from: date) }
    func yearString(_ date: Date) -> String { formatter("yyyy").string(from: date) }

    func monthRange(start: Date, end: Date) -> String {
        let startMonth = calendar.yearMonth(of: start)
        let endMonth = calendar.yearMonth(of: end)
        if startMonth == endMonth {
            return monthYear(start)
        }
        if startMonth.year == endMonth.year {
            return "\(monthName(start)) – \(monthYear(end))"
        }
        return "\(monthYear(start)) – \(monthYear(end))"
    }
}

/// The words of moment names in one language. Turkish builds compounds ("Ağustos Akşamı",
/// "Cuma Gecesi") and suffixes proper names ("Ağustos'ta"); English keeps its title case.
struct NamingWords {
    let language: EditorialLanguage

    private var turkish: Bool { language == .turkish }

    var undated: String { turkish ? "Tarihsiz" : "Without a date" }
    var fewDaysAway: String { turkish ? "Birkaç Gün Uzakta" : "A Few Days Away" }
    var newYearsEve: String { turkish ? "Yılbaşı Gecesi" : "New Year's Eve" }

    func momentsFrom(_ month: String) -> String {
        turkish ? "\(month) Anları" : "Moments from \(month)"
    }

    func weekend(_ month: String) -> String {
        turkish ? "\(month) Hafta Sonu" : "\(month) Weekend"
    }

    func fewDays(in month: String) -> String {
        turkish ? "\(month)\(TurkishSuffix.locative(month)) Birkaç Gün" : "A Few Days in \(month)"
    }

    /// "A Saturday in August" / "Ağustos'ta Bir Cumartesi"; "A Day in August" without a weekday.
    func day(_ weekday: String?, in month: String) -> String {
        if turkish {
            return "\(month)\(TurkishSuffix.locative(month)) Bir \(weekday ?? "Gün")"
        }
        return "\(weekday.map { "A \($0)" } ?? "A Day") in \(month)"
    }

    /// "August Evening", "Friday Night" / "Ağustos Akşamı", "Cuma Gecesi".
    func part(_ part: PartOfDay, of name: String) -> String {
        guard turkish else { return "\(name) \(part.displayName)" }
        let compound = switch part {
        case .morning: "Sabahı"
        case .afternoon: "Öğleden Sonrası"
        case .evening: "Akşamı"
        case .night: "Gecesi"
        }
        return "\(name) \(compound)"
    }
}
