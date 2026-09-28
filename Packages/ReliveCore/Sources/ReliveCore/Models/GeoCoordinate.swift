import Foundation

/// A latitude/longitude pair, independent of CoreLocation so the engine stays portable.
public struct GeoCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Rejects out-of-range values and "null island" (0, 0), which is what
    /// broken EXIF writers tend to produce instead of omitting the location.
    public var isValid: Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return !(abs(latitude) < 0.000_1 && abs(longitude) < 0.000_1)
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: GeoCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let sinLat: Double = sin(deltaLat / 2)
        let sinLon: Double = sin(deltaLon / 2)
        let cosProduct: Double = cos(lat1) * cos(lat2)
        let a: Double = sinLat * sinLat + cosProduct * sinLon * sinLon
        let angle: Double = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * angle
    }

    /// Mean position computed on the unit sphere so that points on either side of the
    /// antimeridian average correctly.
    public static func centroid(of coordinates: [GeoCoordinate]) -> GeoCoordinate? {
        guard !coordinates.isEmpty else { return nil }
        var x = 0.0, y = 0.0, z = 0.0
        for coordinate in coordinates {
            let lat = coordinate.latitude * .pi / 180
            let lon = coordinate.longitude * .pi / 180
            x += cos(lat) * cos(lon)
            y += cos(lat) * sin(lon)
            z += sin(lat)
        }
        let count = Double(coordinates.count)
        x /= count; y /= count; z /= count
        let hypotenuse = sqrt(x * x + y * y)
        guard hypotenuse > 1e-12 || abs(z) > 1e-12 else { return coordinates.first }
        return GeoCoordinate(
            latitude: atan2(z, hypotenuse) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    /// A coarse grid key (~1.1 km at the equator) used to deduplicate reverse-geocoding lookups.
    public var placeLookupKey: String {
        String(format: "%.2f,%.2f", latitude, longitude)
    }
}
