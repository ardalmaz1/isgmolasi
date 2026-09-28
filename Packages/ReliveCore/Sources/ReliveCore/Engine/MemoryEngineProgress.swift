import Foundation

/// The pipeline stage currently running. The processing screen maps each stage to one honest
/// message, so the words on screen always describe real work.
public enum MemoryEngineStage: Int, Comparable, Sendable, CaseIterable {
    case readingMetadata
    case analyzingImages
    case findingMoments
    case findingPlaces
    case choosingFavorites
    case finished

    public static func < (lhs: MemoryEngineStage, rhs: MemoryEngineStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MemoryEngineProgress: Equatable, Sendable {
    public var stage: MemoryEngineStage
    public var completedUnits: Int
    public var totalUnits: Int

    public init(stage: MemoryEngineStage, completedUnits: Int = 0, totalUnits: Int = 0) {
        self.stage = stage
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
    }

    /// Progress within the current stage, 0...1 (1 when the stage has no measurable units).
    public var stageFraction: Double {
        guard totalUnits > 0 else { return stage == .finished ? 1 : 0 }
        return min(1, Double(completedUnits) / Double(totalUnits))
    }

    /// Overall progress estimate, 0...1. Image analysis dominates real run time, so it gets
    /// most of the bar; the other stages are fast.
    public var overallFraction: Double {
        let spans: [MemoryEngineStage: (start: Double, length: Double)] = [
            .readingMetadata: (0.00, 0.02),
            .analyzingImages: (0.02, 0.83),
            .findingMoments: (0.85, 0.03),
            .findingPlaces: (0.88, 0.10),
            .choosingFavorites: (0.98, 0.02),
            .finished: (1.00, 0.00),
        ]
        guard let span = spans[stage] else { return 0 }
        return min(1, span.start + span.length * stageFraction)
    }
}

/// Counts that explain what the engine did. Used for logging and honest UI copy.
public struct MemoryEngineDiagnostics: Equatable, Sendable {
    public var inputCount = 0
    public var undatedCount = 0
    public var locatedCount = 0
    public var analyzedCount = 0
    public var analysisFailureCount = 0
    public var duplicateCount = 0
    public var similarCount = 0
    public var momentCount = 0
    public var chapterCount = 0
    public var namedPlaceCount = 0

    public init() {}
}

public struct MemoryEngineResult: Sendable {
    public var story: Story
    /// Input assets with analysis filled in, so callers can cache it.
    public var assets: [MemoryAsset]
    public var diagnostics: MemoryEngineDiagnostics
}
