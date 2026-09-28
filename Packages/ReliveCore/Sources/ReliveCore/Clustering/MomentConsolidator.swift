import Foundation

public struct ConsolidationConfiguration: Hashable, Sendable {
    /// Clusters with at most this many assets count as "small".
    public var smallMomentMaximumSize: Int
    /// A month needs at least this many small clusters before they are gathered.
    public var minimumSmallMomentsToCombine: Int

    public init(smallMomentMaximumSize: Int = 2, minimumSmallMomentsToCombine: Int = 2) {
        self.smallMomentMaximumSize = smallMomentMaximumSize
        self.minimumSmallMomentsToCombine = minimumSmallMomentsToCombine
    }

    public static let standard = ConsolidationConfiguration()
}

/// Gathers scattered single photos into monthly collections.
///
/// A timeline made of dozens of one-photo "moments" reads like a list, not a story. When a month
/// has several small clusters (≤ 2 assets each) that are not part of a trip, they become one
/// `collection` moment ("Moments from March"). Larger moments are never merged.
public struct MomentConsolidator: Sendable {
    public struct Group: Hashable, Sendable {
        /// Indices into the input clusters, chronological.
        public var clusterIndices: [Int]
        public var isCollection: Bool
    }

    public var configuration: ConsolidationConfiguration
    public var calendar: Calendar

    public init(configuration: ConsolidationConfiguration = .standard, calendar: Calendar) {
        self.configuration = configuration
        self.calendar = calendar
    }

    /// - Parameters:
    ///   - sizes: asset count per cluster.
    ///   - startDates: start date per cluster.
    ///   - protectedIndices: clusters that must stay as they are (e.g. members of a chapter).
    public func consolidate(sizes: [Int], startDates: [Date], protectedIndices: Set<Int>) -> [Group] {
        precondition(sizes.count == startDates.count, "sizes and startDates must align")

        var smallByMonth: [YearMonth: [Int]] = [:]
        for index in sizes.indices
        where sizes[index] <= configuration.smallMomentMaximumSize && !protectedIndices.contains(index) {
            smallByMonth[calendar.yearMonth(of: startDates[index]), default: []].append(index)
        }

        var gathered = Set<Int>()
        var groups: [Group] = []
        for indices in smallByMonth.values where indices.count >= configuration.minimumSmallMomentsToCombine {
            groups.append(Group(clusterIndices: indices.sorted(), isCollection: true))
            gathered.formUnion(indices)
        }
        for index in sizes.indices where !gathered.contains(index) {
            groups.append(Group(clusterIndices: [index], isCollection: false))
        }

        return groups.sorted { lhs, rhs in
            let left = lhs.clusterIndices.first ?? 0
            let right = rhs.clusterIndices.first ?? 0
            return startDates[left] == startDates[right] ? left < right : startDates[left] < startDates[right]
        }
    }
}
