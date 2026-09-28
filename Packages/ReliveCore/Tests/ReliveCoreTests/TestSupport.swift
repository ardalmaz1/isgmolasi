import Foundation
@testable import ReliveCore

/// Fixed calendar (UTC+3, no DST) so tests don't depend on the machine's time zone.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600) ?? .current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}()

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    guard let value = testCalendar.date(from: components) else {
        fatalError("Invalid test date \(components)")
    }
    return value
}

enum Places {
    static let kas = GeoCoordinate(latitude: 36.2018, longitude: 29.6377)
    static let kasHarbour = GeoCoordinate(latitude: 36.1990, longitude: 29.6410)
    static let kekova = GeoCoordinate(latitude: 36.1936, longitude: 29.8420)
    static let kadikoy = GeoCoordinate(latitude: 40.9906, longitude: 29.0290)
    static let moda = GeoCoordinate(latitude: 40.9807, longitude: 29.0263)
    static let besiktas = GeoCoordinate(latitude: 41.0422, longitude: 29.0083)
    static let ankara = GeoCoordinate(latitude: 39.9334, longitude: 32.8597)
}

func makeAsset(
    _ id: String? = nil,
    at creationDate: Date?,
    location: GeoCoordinate? = nil,
    kind: MediaKind = .photo,
    favorite: Bool = false,
    width: Int = 3024,
    height: Int = 4032,
    traits: AssetTraits = [],
    analysis: AssetAnalysis? = nil
) -> MemoryAsset {
    let identifier = id ?? UUID().uuidString
    return MemoryAsset(
        localIdentifier: identifier,
        creationDate: creationDate,
        location: location,
        kind: kind,
        traits: traits,
        duration: kind == .video ? 12 : 0,
        pixelWidth: width,
        pixelHeight: height,
        isFavorite: favorite,
        analysis: analysis
    )
}

/// Analysis with a given fingerprint and optional quality signals.
func analysis(
    hash: UInt64? = nil,
    contrast: Double = 0.3,
    vector: [Float]? = nil,
    faces: Int = 0,
    faceQuality: Double? = nil,
    sharpness: Double? = 0.5,
    aesthetics: Double? = 0.5,
    utility: Bool = false
) -> AssetAnalysis {
    AssetAnalysis(
        faceCount: faces,
        faceCaptureQuality: faceQuality,
        sharpness: sharpness,
        aestheticScore: aesthetics,
        isUtility: utility,
        fingerprint: VisualFingerprint(differenceHash: hash, contrast: contrast, featureVector: vector)
    )
}

/// Returns assets at the given minute offsets from `start`.
func burst(from start: Date, minutes: [Double], location: GeoCoordinate? = nil, prefix: String) -> [MemoryAsset] {
    minutes.enumerated().map { index, minute in
        makeAsset("\(prefix)-\(index)", at: start.addingTimeInterval(minute * 60), location: location)
    }
}

/// Returns a stored analysis if the asset has one, otherwise a neutral analysis.
struct FakeAnalyzer: AssetAnalyzing {
    var failingIDs: Set<AssetID> = []

    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        if failingIDs.contains(asset.id) {
            return .unavailable()
        }
        return AssetAnalysis(sharpness: 0.5, aestheticScore: 0.5)
    }
}

/// Resolves names from a fixed table, matching the nearest entry within 30 km.
struct FakePlaceResolver: PlaceNameResolving {
    var table: [(GeoCoordinate, String)] = [
        (Places.kas, "Kaş"),
        (Places.kekova, "Kekova"),
        (Places.kadikoy, "Kadıköy"),
        (Places.besiktas, "Beşiktaş"),
        (Places.ankara, "Ankara"),
    ]

    func placeName(for coordinate: GeoCoordinate) async -> PlaceName? {
        let nearest = table.min { $0.0.distance(to: coordinate) < $1.0.distance(to: coordinate) }
        guard let nearest, nearest.0.distance(to: coordinate) <= 30_000 else { return nil }
        return PlaceName(name: nearest.1)
    }
}

/// Collects progress callbacks from a @Sendable context.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MemoryEngineProgress] = []

    func record(_ progress: MemoryEngineProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var values: [MemoryEngineProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

func makeEngine(
    analyzer: any AssetAnalyzing = FakeAnalyzer(),
    placeResolver: any PlaceNameResolving = FakePlaceResolver()
) -> MemoryEngine {
    MemoryEngine(
        configuration: MemoryEngineConfiguration(calendar: testCalendar),
        analyzer: analyzer,
        placeResolver: placeResolver,
        namingService: LocalMomentNamingService(calendar: testCalendar)
    )
}
