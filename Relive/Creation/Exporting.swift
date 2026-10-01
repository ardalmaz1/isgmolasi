import Observation
import Photos
import ReliveCore
import SwiftUI
import UIKit

/// Why an export didn't happen, in words for the user.
enum CreationExportError: LocalizedError, Equatable {
    case missingPhotos(Int)
    case renderFailed
    case photosAccessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingPhotos(let count):
            count == 1
                ? "One photo is no longer in your library. Replace or remove it, then try again."
                : "\(count) photos are no longer in your library. Replace or remove them, then try again."
        case .renderFailed:
            "Something went wrong while making the image. Please try again."
        case .photosAccessDenied:
            "Relive isn’t allowed to save to Photos. You can allow it in Settings."
        case .saveFailed:
            "Couldn’t save to Photos. Please try again."
        }
    }
}

/// Where creation pixels come from: the photo library in the app, a stand-in in tests (which
/// must never touch PhotoKit — that would raise the system permission prompt).
protocol CreationPhotoLoading: Sendable {
    func image(for id: AssetID, pixelSize: CGSize, contentMode: PHImageContentMode, caches: Bool) async -> UIImage?
}

extension PhotoImageLoader: CreationPhotoLoading {}

/// Loads pixels for creations. Previews use modest, cached sizes; exports load each photo at
/// the size its frame needs in the final image (never the full original) without caching.
struct CreationImageSource {
    let loader: any CreationPhotoLoading

    /// A whole (uncropped) image for previews, or nil if the photo is gone.
    func previewImage(for id: AssetID, longSide: Double = CreationImageSizing.previewLongSide) async -> UIImage? {
        await loader.image(for: id, pixelSize: CGSize(width: longSide, height: longSide), contentMode: .aspectFit, caches: true)
    }

    /// Export images for photos and the frames they fill. Throws if any photo can't be loaded.
    func exportImages(for frames: [(id: AssetID, frame: CanvasSize)]) async throws -> CanvasImages {
        var images: CanvasImages = [:]
        var missing = 0
        for (id, frame) in frames where images[id] == nil {
            try Task.checkCancellation()
            let pixels = CreationImageSizing.exportPixelSize(forFrame: frame)
            if let image = await loader.image(for: id, pixelSize: pixels.cgSize, contentMode: .aspectFill, caches: false) {
                images[id] = image
            } else {
                missing += 1
            }
        }
        if missing > 0 { throw CreationExportError.missingPhotos(missing) }
        return images
    }
}

/// Saving finished images to the photo library. Asks only for permission to *add* photos.
enum PhotoLibrarySaver {
    static func requestAddAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }

    /// Saves JPEG data as new photos and returns their identifiers.
    static func save(_ jpegs: [Data]) async throws -> [AssetID] {
        guard await requestAddAccess() else { throw CreationExportError.photosAccessDenied }
        let collector = IdentifierCollector()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for data in jpegs {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                    if let id = request.placeholderForCreatedAsset?.localIdentifier {
                        collector.append(id)
                    }
                }
            }
        } catch {
            throw CreationExportError.saveFailed
        }
        return collector.identifiers
    }

    private final class IdentifierCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AssetID] = []

        func append(_ id: AssetID) {
            lock.withLock { storage.append(id) }
        }

        var identifiers: [AssetID] {
            lock.withLock { storage }
        }
    }
}

/// Runs one export at a time for a creation screen, and reports how it went.
///
/// Repeated taps while an export runs are ignored, the work continues briefly if the app is
/// sent to the background, and nothing is left half-done on failure.
@Observable
@MainActor
final class ExportController {
    enum Phase: Equatable {
        case idle
        case working(String)
        case finished(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The last failure can be fixed in Settings.
    private(set) var offersSettings = false

    var isBusy: Bool {
        if case .working = phase { return true }
        return false
    }

    /// Renders with `render`, encodes, then saves to Photos.
    func save(
        store: StoryStore,
        analytics: any AnalyticsTracking,
        properties: [String: String],
        render: @escaping @MainActor () async throws -> [UIImage]
    ) async {
        await run(message: "Saving…") {
            let images = try await render()
            let jpegs = await Self.encode(images)
            guard jpegs.count == images.count, !jpegs.isEmpty else { throw CreationExportError.renderFailed }
            let ids = try await PhotoLibrarySaver.save(jpegs)
            store.recordCreatedAssets(ids)
            analytics.track(.creationExported, properties.merging(["destination": "photos", "images": String(jpegs.count)]) { $1 })
            return jpegs.count == 1 ? "Saved to Photos" : "\(jpegs.count) images saved to Photos"
        }
    }

    /// Renders with `render`, encodes, and opens the share sheet.
    func share(
        name: String,
        analytics: any AnalyticsTracking,
        properties: [String: String],
        render: @escaping @MainActor () async throws -> [UIImage]
    ) async {
        await run(message: "Preparing…") {
            let images = try await render()
            let jpegs = await Self.encode(images)
            guard jpegs.count == images.count, !jpegs.isEmpty else { throw CreationExportError.renderFailed }
            let urls = try Self.writeShareFiles(jpegs, name: name)
            SystemPresenter.share(items: urls) { completed, activity in
                guard completed else { return }
                analytics.track(.creationExported, properties.merging([
                    "destination": "share",
                    "activity": activity ?? "unknown",
                    "images": String(jpegs.count),
                ]) { $1 })
            }
            return nil
        }
    }

    func clearMessage() {
        if !isBusy { phase = .idle }
    }

    private func run(message: String, _ work: @MainActor () async throws -> String?) async {
        guard !isBusy else { return }
        phase = .working(message)
        offersSettings = false
        let activity = BackgroundActivity(name: "relive.export")
        defer { activity.end() }
        do {
            let result = try await work()
            phase = result.map { .finished($0) } ?? .idle
        } catch is CancellationError {
            phase = .idle
        } catch let error as CreationExportError {
            offersSettings = error == .photosAccessDenied
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(CreationExportError.renderFailed.errorDescription ?? "Something went wrong.")
        }
    }

    /// JPEG encoding happens off the main thread.
    static func encode(_ images: [UIImage]) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            images.compactMap { $0.jpegData(compressionQuality: 0.92) }
        }.value
    }

    /// Writes images to a private temporary folder for the share sheet, replacing earlier ones.
    static func writeShareFiles(_ jpegs: [Data], name: String) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ReliveShare", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try jpegs.enumerated().map { index, data in
            let fileName = jpegs.count == 1 ? "\(name).jpg" : "\(name) \(index + 1).jpg"
            let url = folder.appending(path: fileName, directoryHint: .notDirectory)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }
    }
}

/// The status line under creation actions: progress, confirmation or what went wrong.
struct ExportStatusView: View {
    let controller: ExportController

    var body: some View {
        Group {
            switch controller.phase {
            case .idle:
                EmptyView()
            case .working(let message):
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                    Text(message)
                }
                .foregroundStyle(Palette.textSecondary)
            case .finished(let message):
                Label(message, systemImage: "checkmark")
                    .foregroundStyle(Palette.textPrimary)
            case .failed(let message):
                VStack(spacing: Spacing.xs) {
                    Text(message)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    if controller.offersSettings {
                        Button("Open Settings") { SystemPresenter.openSettings() }
                            .font(Typography.footnote.weight(.semibold))
                    }
                }
            }
        }
        .font(Typography.footnote)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: controller.phase)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var identifier: String {
        switch controller.phase {
        case .idle: "exportIdle"
        case .working: "exportWorking"
        case .finished: "exportFinished"
        case .failed: "exportFailed"
        }
    }
}
