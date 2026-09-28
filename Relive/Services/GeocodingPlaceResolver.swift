import CoreLocation
import Foundation
import os
import ReliveCore

/// Names places with Apple's reverse geocoder, one coordinate per moment (never per photo),
/// with a persistent local cache so each place is looked up only once.
///
/// Reverse geocoding sends a coordinate — not a photo — to Apple's geocoding service. It is
/// the only network call in the analysis pipeline, and failures simply leave a moment unnamed.
/// The geocoder is rate-limited, so requests run one at a time and the resolver stops for the
/// current run after repeated failures.
actor GeocodingPlaceResolver: PlaceNameResolving {
    private struct CacheEntry: Codable {
        var place: PlaceName?
        var resolvedAt: Date
    }

    private static let logger = Logger(subsystem: "app.relive", category: "places")

    private let geocoder = CLGeocoder()
    private let cacheURL: URL
    private var cache: [String: CacheEntry]
    private var consecutiveFailures = 0
    private let maximumConsecutiveFailures = 3

    init(cacheURL: URL = GeocodingPlaceResolver.defaultCacheURL) {
        self.cacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    static var defaultCacheURL: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Relive", directoryHint: .isDirectory)
        return directory.appending(path: "place-names.json")
    }

    func placeName(for coordinate: GeoCoordinate) async -> PlaceName? {
        let key = coordinate.placeLookupKey
        if let entry = cache[key] {
            return entry.place
        }
        guard consecutiveFailures < maximumConsecutiveFailures else { return nil }

        do {
            let place = try await lookUp(coordinate)
            consecutiveFailures = 0
            cache[key] = CacheEntry(place: place, resolvedAt: Date())
            persist()
            return place
        } catch {
            consecutiveFailures += 1
            Self.logger.info("Reverse geocoding failed: \(error.localizedDescription, privacy: .public)")
            // Back off briefly; the geocoder throttles bursts.
            try? await Task.sleep(for: .seconds(1))
            return nil
        }
    }

    /// Resets the failure budget so a later run (e.g. after adding memories) can try again.
    func resetFailures() {
        consecutiveFailures = 0
    }

    func clearCache() {
        cache = [:]
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func lookUp(_ coordinate: GeoCoordinate) async throws -> PlaceName? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = self.geocoder
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    // "No result" is an answer, not a failure worth retrying.
                    if let clError = error as? CLError, clError.code == .geocodeFoundNoResult {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: placemarks?.first.flatMap(Self.placeName(from:)))
            }
        }
    }

    /// Prefers the town or city ("Kaş"), falling back to broader areas.
    private nonisolated static func placeName(from placemark: CLPlacemark) -> PlaceName? {
        let candidates = [placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea, placemark.country]
        guard let name = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return PlaceName(name: name, region: placemark.administrativeArea, country: placemark.country)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Could not save place cache: \(error.localizedDescription, privacy: .public)")
        }
    }
}
