import Foundation

/// Stage 1 — cleans raw metadata before any grouping happens.
///
/// - Drops invalid coordinates (out of range, or the 0,0 "null island" some apps write).
/// - Treats capture dates far in the future as unknown (a wrong device clock is more likely
///   than time travel).
/// - Separates dated from undated assets and sorts the dated ones chronologically, with the
///   identifier as a tie-breaker so output is deterministic.
public struct MetadataProcessor: Sendable {
    public struct Output: Sendable {
        public var dated: [MemoryAsset]
        public var undated: [MemoryAsset]
    }

    /// How far past "now" a capture date may be before we distrust it.
    public var futureTolerance: TimeInterval

    public init(futureTolerance: TimeInterval = 2 * 86_400) {
        self.futureTolerance = futureTolerance
    }

    public func process(_ assets: [MemoryAsset], now: Date) -> Output {
        var dated: [MemoryAsset] = []
        var undated: [MemoryAsset] = []
        var seen = Set<AssetID>()

        for var asset in assets where seen.insert(asset.id).inserted {
            if let location = asset.location, !location.isValid {
                asset.location = nil
            }
            if let date = asset.creationDate, date.timeIntervalSince(now) > futureTolerance {
                asset.creationDate = nil
            }
            if asset.creationDate == nil {
                undated.append(asset)
            } else {
                dated.append(asset)
            }
        }

        dated.sort(by: MetadataProcessor.chronological)
        undated.sort { $0.id < $1.id }
        return Output(dated: dated, undated: undated)
    }

    static func chronological(_ lhs: MemoryAsset, _ rhs: MemoryAsset) -> Bool {
        let left = lhs.creationDate ?? .distantFuture
        let right = rhs.creationDate ?? .distantFuture
        if left != right { return left < right }
        return lhs.id < rhs.id
    }
}
