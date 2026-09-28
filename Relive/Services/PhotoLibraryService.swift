import CoreLocation
import Photos
import ReliveCore

/// What Relive may see in the photo library.
enum PhotoAccessStatus: Equatable, Sendable {
    case notDetermined
    /// The user chose specific photos for Relive (the preferred, privacy-preserving mode).
    case limited
    case full
    case denied
    case restricted

    var canReadSelection: Bool { self == .limited || self == .full }
}

/// Everything Relive needs from the photo library, expressed in value types. Views and stores
/// never touch PhotoKit objects directly.
protocol PhotoLibraryProviding: Sendable {
    func accessStatus() -> PhotoAccessStatus
    func requestAccess() async -> PhotoAccessStatus
    /// Metadata for the given identifiers. Identifiers that no longer resolve are omitted.
    func assets(withIdentifiers identifiers: [AssetID]) async -> [MemoryAsset]
    /// Every photo and video Relive can see. With limited access this is exactly the user's selection.
    func allAccessibleAssets() async -> [MemoryAsset]
    /// The subset of identifiers that still resolve (not deleted, access not revoked).
    func availableIdentifiers(among identifiers: [AssetID]) async -> Set<AssetID>
}

/// PhotoKit-backed implementation. Stateless and thread-safe.
struct PhotoKitLibraryService: PhotoLibraryProviding {
    func accessStatus() -> PhotoAccessStatus {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PhotoAccessStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.map(status)
    }

    func assets(withIdentifiers identifiers: [AssetID]) async -> [MemoryAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        return Self.memoryAssets(from: result)
    }

    func allAccessibleAssets() async -> [MemoryAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return Self.memoryAssets(from: PHAsset.fetchAssets(with: options))
    }

    func availableIdentifiers(among identifiers: [AssetID]) async -> Set<AssetID> {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var found = Set<AssetID>()
        result.enumerateObjects { asset, _, _ in found.insert(asset.localIdentifier) }
        return found
    }

    // MARK: - Mapping

    private static func memoryAssets(from result: PHFetchResult<PHAsset>) -> [MemoryAsset] {
        var assets: [MemoryAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            if let memoryAsset = memoryAsset(from: asset) {
                assets.append(memoryAsset)
            }
        }
        return assets
    }

    private static func memoryAsset(from asset: PHAsset) -> MemoryAsset? {
        let kind: MediaKind
        switch asset.mediaType {
        case .image: kind = .photo
        case .video: kind = .video
        default: return nil
        }

        var traits: AssetTraits = []
        if asset.mediaSubtypes.contains(.photoScreenshot) { traits.insert(.screenshot) }
        if asset.mediaSubtypes.contains(.photoLive) { traits.insert(.livePhoto) }
        if asset.mediaSubtypes.contains(.photoPanorama) { traits.insert(.panorama) }
        if asset.mediaSubtypes.contains(.photoDepthEffect) { traits.insert(.depthEffect) }

        let location = asset.location.map {
            GeoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }

        return MemoryAsset(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            location: location,
            kind: kind,
            traits: traits,
            duration: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isFavorite: asset.isFavorite
        )
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoAccessStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .limited: .limited
        case .authorized: .full
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
