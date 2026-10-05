import Foundation

/// Brings stored memories back in line with what the photo library reports *now*.
///
/// Relive stores a snapshot of each memory's metadata when it is chosen. If that snapshot no
/// longer matches the library — the date was corrected in Photos, the item synced its real
/// metadata later, or an earlier version stored something else — every date, month, year and
/// place derived from it would be wrong. This compares each stored memory with the library's
/// current metadata (after the same normalization the Memory Engine applies) and repairs the
/// difference.
///
/// Guarantees:
/// - Never adds or removes a memory, and never duplicates one. Memories the library doesn't
///   return (deleted, access removed) are left exactly as stored.
/// - Keeps cached analysis.
/// - Idempotent: repairing the result again changes nothing.
public struct MetadataRepair: Sendable {
    public struct Change: Hashable, Sendable {
        public var assetID: AssetID
        public var previousDate: Date?
        public var repairedDate: Date?
        public var dateChanged: Bool
        public var locationChanged: Bool
        /// Kind, size, duration, traits or the Photos favorite flag.
        public var otherChanged: Bool
    }

    public struct Result: Sendable {
        /// Every stored memory, repaired where the library says otherwise.
        public var assets: [AssetID: MemoryAsset]
        public var changes: [Change]
        /// Stored memories the library didn't return; left untouched.
        public var notInLibrary: [AssetID]

        /// Dates or places changed, so moments, months and years must be worked out again.
        public var needsRebuild: Bool {
            changes.contains { $0.dateChanged || $0.locationChanged }
        }
    }

    public var processor: MetadataProcessor

    public init(processor: MetadataProcessor = MetadataProcessor()) {
        self.processor = processor
    }

    public func repair(stored: [AssetID: MemoryAsset], library: [MemoryAsset], now: Date) -> Result {
        let current = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var repaired = stored
        var changes: [Change] = []
        var missing: [AssetID] = []

        for id in stored.keys.sorted() {
            guard let old = stored[id] else { continue }
            guard let fresh = current[id] else {
                missing.append(id)
                continue
            }
            var canonical = processor.normalized(fresh, now: now)
            canonical.analysis = old.analysis
            let dateChanged = canonical.creationDate != old.creationDate
            let locationChanged = canonical.location != old.location
            let otherChanged = canonical.kind != old.kind
                || canonical.traits != old.traits
                || canonical.duration != old.duration
                || canonical.pixelWidth != old.pixelWidth
                || canonical.pixelHeight != old.pixelHeight
                || canonical.isFavorite != old.isFavorite
            guard dateChanged || locationChanged || otherChanged else { continue }
            repaired[id] = canonical
            changes.append(Change(
                assetID: id,
                previousDate: old.creationDate,
                repairedDate: canonical.creationDate,
                dateChanged: dateChanged,
                locationChanged: locationChanged,
                otherChanged: otherChanged
            ))
        }
        return Result(assets: repaired, changes: changes, notInLibrary: missing)
    }
}

/// A privacy-safe summary of the stored temporal metadata, for development logs: counts only —
/// no identifiers, contents or coordinates.
public struct MetadataAudit: Hashable, Sendable {
    public var assets: Int
    public var validDates: Int
    public var unknownDates: Int
    public var withLocation: Int
    /// Memories per year, chronological.
    public var years: [(year: Int, count: Int)] { yearCounts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
    /// Memories per month, chronological.
    public var months: [(month: MonthKey, count: Int)] { monthCounts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }

    private var yearCounts: [Int: Int]
    private var monthCounts: [MonthKey: Int]

    public init(assets: [MemoryAsset], calendar: Calendar) {
        self.assets = assets.count
        let dated = assets.compactMap(\.creationDate)
        validDates = dated.count
        unknownDates = assets.count - dated.count
        withLocation = assets.filter { $0.location != nil }.count
        yearCounts = dated.reduce(into: [:]) { $0[calendar.component(.year, from: $1), default: 0] += 1 }
        monthCounts = dated.reduce(into: [:]) { $0[MonthKey(date: $1, calendar: calendar), default: 0] += 1 }
    }

    /// `metadata_audit assets=97 validDates=97 unknownDates=0 located=40 years=[2025:25,2026:72] months=[2025-04:8,…]`
    public func logLine(repaired: Int? = nil) -> String {
        let years = self.years.map { "\($0.year):\($0.count)" }.joined(separator: ",")
        let months = self.months.map { String(format: "%04ld-%02ld:%ld", $0.month.year, $0.month.month, $0.count) }.joined(separator: ",")
        var line = "metadata_audit assets=\(assets) validDates=\(validDates) unknownDates=\(unknownDates) located=\(withLocation) years=[\(years)] months=[\(months)]"
        if let repaired { line += " repaired=\(repaired)" }
        return line
    }

    public static func == (lhs: MetadataAudit, rhs: MetadataAudit) -> Bool {
        lhs.assets == rhs.assets && lhs.validDates == rhs.validDates && lhs.unknownDates == rhs.unknownDates
            && lhs.withLocation == rhs.withLocation && lhs.yearCounts == rhs.yearCounts && lhs.monthCounts == rhs.monthCounts
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(assets)
        hasher.combine(validDates)
        hasher.combine(unknownDates)
    }
}
