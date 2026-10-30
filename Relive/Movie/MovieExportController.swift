import Observation
import os
import Photos
import ReliveCore
import SwiftUI
import UIKit

/// Where finished movies are saved. The app saves to the photo library; hosted tests use a
/// stand-in (PhotoKit would raise the system permission prompt).
protocol MovieSaving: Sendable {
    /// Saves the video file as a new item in Photos and returns its identifier.
    func saveVideo(at url: URL) async throws -> AssetID?
}

struct PhotoLibraryMovieSaver: MovieSaving {
    func saveVideo(at url: URL) async throws -> AssetID? {
        guard await PhotoLibrarySaver.requestAddAccess() else { throw MovieExportError.photosAccessDenied }
        let holder = IdentifierHolder()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
                holder.value = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw MovieExportError.saveFailed
        }
        return holder.value
    }

    private final class IdentifierHolder: @unchecked Sendable {
        var value: AssetID?
    }
}

/// Makes a movie file and saves or shares it — one at a time, with honest progress.
///
/// - Repeated taps while a movie is being made are ignored (never two exports).
/// - Cancel stops between frames and deletes the partial file.
/// - Leaving the app: rendering continues for the short time iOS allows; if that runs out it
///   stops cleanly and says so (the file is never left half-written).
/// - A saved movie is recorded as Relive's own first, so it is never imported as a memory.
@Observable
@MainActor
final class MovieExportController {
    enum Phase: Equatable {
        case idle
        /// 0...1.
        case rendering(Double)
        case saving
        case finished(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var offersSettings = false
    /// The last render's numbers (for DEBUG diagnostics and tests).
    @ObservationIgnored private(set) var lastResult: MovieRenderResult?
    @ObservationIgnored private let saver: any MovieSaving
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var wasInterrupted = false

    init(saver: any MovieSaving = PhotoLibraryMovieSaver()) {
        self.saver = saver
    }

    var isBusy: Bool {
        switch phase {
        case .rendering, .saving: true
        default: false
        }
    }

    /// Renders, then saves to Photos. `onSaved` runs once the movie is in Photos.
    func save(
        plan: MoviePlan,
        loader: any CreationPhotoLoading,
        store: StoryStore?,
        analytics: any AnalyticsTracking,
        properties: [String: String],
        onSaved: @escaping @MainActor () -> Void = {}
    ) async {
        let saver = self.saver
        await run(plan: plan, loader: loader, analytics: analytics, properties: properties.merging(["destination": "photos"]) { $1 }) { result in
            self.phase = .saving
            let id = try await saver.saveVideo(at: result.url)
            if let id { store?.recordCreatedAssets([id]) }
            MovieRenderer.removeTemporaryFiles()
            onSaved()
            return String(localized: "Saved to Photos")
        }
    }

    /// Renders, then opens the share sheet with the movie file. `onShared` runs only if it was
    /// actually shared.
    func share(
        plan: MoviePlan,
        loader: any CreationPhotoLoading,
        analytics: any AnalyticsTracking,
        properties: [String: String],
        onShared: @escaping @MainActor () -> Void = {}
    ) async {
        await run(plan: plan, loader: loader, analytics: analytics, properties: properties.merging(["destination": "share"]) { $1 }) { result in
            SystemPresenter.share(items: [result.url]) { completed, _ in
                if completed {
                    analytics.track(.movieShared, properties)
                    onShared()
                }
                MovieRenderer.removeTemporaryFiles()
            }
            return nil
        }
    }

    /// Stops a movie being made. Nothing is saved.
    func cancel() {
        task?.cancel()
    }

    func clearMessage() {
        if !isBusy { phase = .idle }
    }

    // MARK: - Running

    private func run(
        plan: MoviePlan,
        loader: any CreationPhotoLoading,
        analytics: any AnalyticsTracking,
        properties: [String: String],
        deliver: @escaping @MainActor (MovieRenderResult) async throws -> String?
    ) async {
        guard !isBusy else { return }
        guard plan.isReady else {
            phase = .failed(MovieExportError.notEnoughPhotos.errorDescription ?? "")
            return
        }
        phase = .rendering(0)
        offersSettings = false
        wasInterrupted = false
        beginBackgroundTask()
        analytics.track(.movieExportStarted, properties)
        #if DEBUG
        let size = plan.settings.aspect.renderSize
        Logger(subsystem: "app.relive", category: "movie").notice("movie_export_started scenes=\(plan.scenes.count, privacy: .public) duration=\(String(format: "%.1f", plan.duration), privacy: .public) resolution=\(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public)")
        #endif

        let work = Task { @MainActor [weak self] in
            do {
                let url = try MovieRenderer.temporaryURL(name: "Yuvi Movie")
                let renderer = MovieRenderer(plan: plan, loader: loader, mark: YuviMark.image(height: 54, scale: 2)?.cgImage)
                let result = try await Task.detached(priority: .userInitiated) {
                    try await renderer.render(to: url) { value in
                        Task { @MainActor in
                            guard let self, case .rendering = self.phase else { return }
                            self.phase = .rendering(value)
                        }
                    }
                }.value
                try Task.checkCancellation()
                self?.lastResult = result
                #if DEBUG
                Logger(subsystem: "app.relive", category: "movie").notice("movie_export_completed seconds=\(String(format: "%.1f", result.seconds), privacy: .public) fileSizeMB=\(String(format: "%.1f", Double(result.bytes) / 1_048_576), privacy: .public) frames=\(result.frames, privacy: .public)")
                #endif
                let message = try await deliver(result)
                analytics.track(.movieExportCompleted, properties.merging(["result": "success", "seconds": String(Int(result.seconds.rounded()))]) { $1 })
                self?.phase = message.map { .finished($0) } ?? .idle
            } catch {
                MovieRenderer.removeTemporaryFiles()
                guard let self else { return }
                let failure: MovieExportError? = if error is CancellationError {
                    self.wasInterrupted ? .interrupted : nil
                } else {
                    (error as? MovieExportError) ?? .renderFailed
                }
                if let failure {
                    self.offersSettings = failure == .photosAccessDenied
                    self.phase = .failed(failure.errorDescription ?? String(localized: "Something went wrong."))
                    analytics.track(.movieExportFailed, properties.merging(["result": failure.code]) { $1 })
                } else {
                    self.phase = .idle
                    analytics.track(.movieExportFailed, properties.merging(["result": "cancelled"]) { $1 })
                }
            }
        }
        task = work
        await work.value
        task = nil
        endBackgroundTask()
    }

    /// iOS gives a little time to finish when the app leaves the screen; if that runs out, the
    /// render stops cleanly and says why.
    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "relive.movie") { [weak self] in
            MainActor.assumeIsolated {
                self?.wasInterrupted = true
                self?.task?.cancel()
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

extension MovieExportError {
    /// Non-identifying analytics code.
    var code: String {
        switch self {
        case .notEnoughPhotos: "not_enough_photos"
        case .missingPhotos: "missing_photos"
        case .renderFailed: "render_failed"
        case .notEnoughSpace: "not_enough_space"
        case .interrupted: "interrupted"
        case .photosAccessDenied: "photos_access_denied"
        case .saveFailed: "save_failed"
        }
    }
}
