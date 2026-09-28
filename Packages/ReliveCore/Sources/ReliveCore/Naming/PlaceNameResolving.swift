import Foundation

/// Turns a coordinate into a place name. On device this is reverse geocoding (with a local
/// cache); in tests it is a lookup table. Implementations must never throw — no name is a
/// perfectly good answer and the story simply omits the place.
public protocol PlaceNameResolving: Sendable {
    func placeName(for coordinate: GeoCoordinate) async -> PlaceName?
}

/// Resolver that knows nothing. Used when location lookups are disabled or unavailable.
public struct NoPlaceNameResolver: PlaceNameResolving {
    public init() {}

    public func placeName(for coordinate: GeoCoordinate) async -> PlaceName? { nil }
}
