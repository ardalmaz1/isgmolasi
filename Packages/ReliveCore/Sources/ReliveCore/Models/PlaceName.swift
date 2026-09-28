import Foundation

/// A human-readable place, produced by reverse geocoding on device.
public struct PlaceName: Codable, Hashable, Sendable {
    /// The short name we show: a town, neighbourhood or landmark ("Kaş").
    public var name: String
    /// Broader region ("Antalya"), when known.
    public var region: String?
    public var country: String?

    public init(name: String, region: String? = nil, country: String? = nil) {
        self.name = name
        self.region = region
        self.country = country
    }

    /// Case- and diacritic-insensitive key used to count distinct places.
    public var comparisonKey: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
