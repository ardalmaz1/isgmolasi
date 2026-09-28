import Foundation

/// All tunables of the pipeline in one place.
public struct MemoryEngineConfiguration: Sendable {
    public var calendar: Calendar
    public var clustering: ClusteringConfiguration
    public var chapters: ChapterConfiguration
    public var consolidation: ConsolidationConfiguration
    public var similarity: SimilarityConfiguration
    public var heroWeights: HeroScoringWeights
    /// How many assets are analyzed in parallel. Vision is heavy; a handful is plenty.
    public var analysisConcurrency: Int
    /// A moment's photos must lie within this distance of their centre for the centre to name it.
    public var coherentPlaceRadius: Double
    /// Capture dates further in the future than this are treated as unknown.
    public var futureDateTolerance: TimeInterval

    public init(
        calendar: Calendar,
        clustering: ClusteringConfiguration = .standard,
        chapters: ChapterConfiguration = .standard,
        consolidation: ConsolidationConfiguration = .standard,
        similarity: SimilarityConfiguration = .standard,
        heroWeights: HeroScoringWeights = .standard,
        analysisConcurrency: Int = 4,
        coherentPlaceRadius: Double = 25_000,
        futureDateTolerance: TimeInterval = 2 * 86_400
    ) {
        self.calendar = calendar
        self.clustering = clustering
        self.chapters = chapters
        self.consolidation = consolidation
        self.similarity = similarity
        self.heroWeights = heroWeights
        self.analysisConcurrency = analysisConcurrency
        self.coherentPlaceRadius = coherentPlaceRadius
        self.futureDateTolerance = futureDateTolerance
    }
}
