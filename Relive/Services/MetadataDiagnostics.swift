import Foundation
import ImageIO
import os
import Photos
import ReliveCore

/// Development-only logging of where each memory's date and place come from, so a device test
/// can be checked from the Xcode console (subsystem `app.relive`, category `metadata`).
///
/// Lines carry a short identifier prefix, dates and yes/no flags — never photo contents, names
/// or coordinates. Nothing here runs in release builds, and nothing is shown to the user.
enum MetadataLog {
    static let logger = Logger(subsystem: "app.relive", category: "metadata")

    /// The first characters of a library identifier: enough to follow one photo through the log.
    static func shortID(_ id: AssetID) -> String {
        String(id.prefix(8))
    }

    /// ISO 8601 in the device's time zone, so month and year boundaries read as the app sees them.
    static func iso(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    #if DEBUG
    /// One line per memory read from the photo library at import: what the library reported and
    /// what Relive stored.
    static func imported(source: [MemoryAsset], stored: [AssetID: MemoryAsset]) {
        for asset in source {
            let kept = stored[asset.id]
            logger.debug("asset_metadata_imported id=\(shortID(asset.id), privacy: .public) sourceDate=\(iso(asset.creationDate), privacy: .public) persistedDate=\(iso(kept?.creationDate), privacy: .public) sourceLocationPresent=\(asset.location != nil, privacy: .public)")
        }
    }

    /// Memories whose stored date differs from the library's because the engine distrusted it
    /// (a capture date in the future).
    static func normalized(source: [MemoryAsset], stored: [MemoryAsset]) {
        let sourceDates = Dictionary(source.map { ($0.id, $0.creationDate) }, uniquingKeysWith: { first, _ in first })
        for asset in stored {
            guard let original = sourceDates[asset.id], original != asset.creationDate else { continue }
            logger.notice("asset_metadata_normalized id=\(shortID(asset.id), privacy: .public) sourceDate=\(iso(original), privacy: .public) persistedDate=\(iso(asset.creationDate), privacy: .public)")
        }
    }

    static func repaired(_ changes: [MetadataRepair.Change]) {
        for change in changes {
            logger.notice("asset_metadata_repaired id=\(shortID(change.assetID), privacy: .public) storedDate=\(iso(change.previousDate), privacy: .public) libraryDate=\(iso(change.repairedDate), privacy: .public) date=\(change.dateChanged, privacy: .public) location=\(change.locationChanged, privacy: .public) other=\(change.otherChanged, privacy: .public)")
        }
    }

    static func audit(_ assets: [MemoryAsset], calendar: Calendar, repaired: Int? = nil) {
        logger.notice("\(MetadataAudit(assets: assets, calendar: calendar).logLine(repaired: repaired), privacy: .public)")
    }
    #endif
}

#if DEBUG
/// Development-only check of the question a device test needs answered first: does the photo
/// library's capture date (`PHAsset.creationDate`, which Relive uses) agree with the capture
/// date written inside the image file itself (EXIF `DateTimeOriginal`)?
///
/// Images saved from some apps carry the date they were saved, not taken. If this logs
/// `differs > 0`, the library itself reports those dates; Relive is showing what it was given.
/// Reads only what is already on the device (no iCloud downloads), at most `limit` photos, off
/// the main thread, once per launch.
enum EmbeddedDateAudit {
    static let limit = 150
    private static let once = OnceFlag()

    /// Set the first time it is checked, from any thread.
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var isSet = false

        func claim() -> Bool {
            lock.withLock {
                defer { isSet = true }
                return !isSet
            }
        }
    }

    static func runOnce(assets: [MemoryAsset]) {
        guard !assets.isEmpty, once.claim(), PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return }
        let photos = assets.filter { $0.kind == .photo }.sorted { $0.id < $1.id }.prefix(limit).map { ($0.id, $0.creationDate) }
        Task.detached(priority: .utility) {
            await check(Array(photos))
        }
    }

    private static func check(_ photos: [(AssetID, Date?)]) async {
        var matches = 0, differs = 0, noEmbedded = 0, unreadable = 0
        for (id, stored) in photos {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                  let data = await originalData(of: asset) else {
                unreadable += 1
                continue
            }
            guard let embedded = embeddedCaptureDate(in: data) else {
                noEmbedded += 1
                continue
            }
            let library = asset.creationDate
            let gap = library.map { abs($0.timeIntervalSince(embedded)) } ?? .infinity
            if gap <= 86_400 {
                matches += 1
            } else {
                differs += 1
                MetadataLog.logger.notice("asset_embedded_date_differs id=\(MetadataLog.shortID(id), privacy: .public) libraryDate=\(MetadataLog.iso(library), privacy: .public) storedDate=\(MetadataLog.iso(stored), privacy: .public) embeddedDate=\(MetadataLog.iso(embedded), privacy: .public) source=\(sourceName(asset.sourceType), privacy: .public)")
            }
        }
        MetadataLog.logger.notice("embedded_date_check checked=\(photos.count, privacy: .public) matches=\(matches, privacy: .public) differs=\(differs, privacy: .public) noEmbeddedDate=\(noEmbedded, privacy: .public) unreadable=\(unreadable, privacy: .public)")
    }

    private static func originalData(of asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.version = .original
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// EXIF `DateTimeOriginal`, in its recorded offset when there is one (otherwise the
    /// device's time zone, as Photos does).
    static func embeddedCaptureDate(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String, let zone = timeZone(offset) {
            formatter.timeZone = zone
        } else {
            formatter.timeZone = .current
        }
        return formatter.date(from: text)
    }

    /// "+03:00" → UTC+3.
    private static func timeZone(_ offset: String) -> TimeZone? {
        let sign: Int = offset.hasPrefix("-") ? -1 : 1
        let digits = offset.drop { $0 == "+" || $0 == "-" }.split(separator: ":")
        guard digits.count == 2, let hours = Int(digits[0]), let minutes = Int(digits[1]) else { return nil }
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }

    private static func sourceName(_ type: PHAssetSourceType) -> String {
        if type.contains(.typeCloudShared) { return "sharedAlbum" }
        if type.contains(.typeiTunesSynced) { return "synced" }
        return "library"
    }
}
#endif
