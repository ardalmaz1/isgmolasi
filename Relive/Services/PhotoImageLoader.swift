import AVFoundation
import CoreImage
import Photos
import ReliveCore
import SwiftUI
import UIKit

/// Loads pixels for display and analysis straight from the photo library. Nothing is copied
/// into the app's storage; decoded thumbnails live only in a memory cache.
///
/// `PHImageManager` and `NSCache` are thread-safe, which is why this class can be shared freely.
final class PhotoImageLoader: @unchecked Sendable {
    static let shared = PhotoImageLoader()

    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init() {
        cache.countLimit = 400
        // Bounded by decoded size too, so large preview images (books, creations) can't grow the
        // cache without limit; NSCache also empties itself under memory pressure.
        cache.totalCostLimit = 160 * 1024 * 1024
        manager.allowsCachingHighQualityImages = false
    }

    /// Image for display, sized in pixels. Returns `nil` if the asset is gone or unavailable.
    /// - Parameter caches: keep the result in the memory cache. Large one-off images (exports)
    ///   pass `false` so they don't push out the thumbnails the screens reuse.
    func image(
        for id: AssetID,
        pixelSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        caches: Bool = true
    ) async -> UIImage? {
        let key = "\(id)|\(Int(pixelSize.width))x\(Int(pixelSize.height))|\(contentMode.rawValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let image = await request(asset: asset, pixelSize: pixelSize, contentMode: contentMode, options: options)
        if let image, caches {
            let pixels = image.size.width * image.scale * image.size.height * image.scale
            cache.setObject(image, forKey: key, cost: Int(pixels) * 4)
        }
        return image
    }

    /// A small upright bitmap for on-device analysis. Never downloads from iCloud: if only a
    /// cloud original exists, analysis degrades instead of spending the user's data.
    func analysisImage(for id: AssetID, maxDimension: CGFloat) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let size = CGSize(width: maxDimension, height: maxDimension)
        guard let image = await request(asset: asset, pixelSize: size, contentMode: .aspectFit, options: options) else {
            return nil
        }
        return uprightCGImage(from: image)
    }

    /// Streams a video from the library (downloading from iCloud if needed).
    func playerItem(for id: AssetID) async -> AVPlayerItem? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              asset.mediaType == .video else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func request(
        asset: PHAsset,
        pixelSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions
    ) async -> UIImage? {
        let box = RequestBox(manager: manager)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                let requestID = manager.requestImage(
                    for: asset,
                    targetSize: pixelSize,
                    contentMode: contentMode,
                    options: options
                ) { image, info in
                    // `.highQualityFormat` delivers once, but guard anyway: a continuation must
                    // resume exactly once.
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isFinal = !isDegraded
                        || info?[PHImageErrorKey] != nil
                        || (info?[PHImageCancelledKey] as? Bool) == true
                    guard isFinal, box.markResumed() else { return }
                    continuation.resume(returning: image)
                }
                box.setRequestID(requestID)
            }
        } onCancel: {
            box.cancel()
        }
    }

    private func uprightCGImage(from image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard image.imageOrientation != .up else { return cgImage }
        let oriented = CIImage(cgImage: cgImage).oriented(CGImagePropertyOrientation(image.imageOrientation))
        return ciContext.createCGImage(oriented, from: oriented.extent)
    }
}

/// Tracks one image request across the continuation and its cancellation handler.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var resumed = false
    private var requestID: PHImageRequestID?

    init(manager: PHImageManager) {
        self.manager = manager
    }

    func setRequestID(_ id: PHImageRequestID) {
        lock.lock()
        requestID = id
        lock.unlock()
    }

    /// Returns true the first time it is called.
    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }

    func cancel() {
        lock.lock()
        let id = requestID
        lock.unlock()
        if let id {
            manager.cancelImageRequest(id)
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

extension EnvironmentValues {
    @Entry var photoImageLoader: PhotoImageLoader = .shared
}
