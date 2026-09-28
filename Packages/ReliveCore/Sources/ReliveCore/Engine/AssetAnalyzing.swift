import Foundation

/// Computes on-device visual signals for one asset. The app implements this with Vision on a
/// small thumbnail; tests use fakes.
///
/// Must not throw: when something fails, return an `AssetAnalysis` with the matching
/// `failures` flags so the rest of the pipeline can degrade gracefully.
public protocol AssetAnalyzing: Sendable {
    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis
}

/// Analyzer that looks at nothing. Moments still form from metadata alone.
public struct MetadataOnlyAnalyzer: AssetAnalyzing {
    public init() {}

    public func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        AssetAnalysis.unavailable()
    }
}
