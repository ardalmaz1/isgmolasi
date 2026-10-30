import AVFoundation
import CoreVideo
import ReliveCore
import UIKit

/// Why a movie couldn't be made, in words for the user.
enum MovieExportError: LocalizedError, Equatable {
    case notEnoughPhotos
    case missingPhotos(Int)
    case renderFailed
    case notEnoughSpace
    case interrupted
    case photosAccessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notEnoughPhotos:
            "A movie needs at least \(MovieEligibility.minimumPhotos) photos."
        case .missingPhotos(let count):
            count == 1
                ? "One photo is no longer in your library. Remove it from the movie, then try again."
                : "\(count) photos are no longer in your library. Remove them from the movie, then try again."
        case .renderFailed:
            "Something went wrong while making the movie. Please try again."
        case .notEnoughSpace:
            "There isn’t enough free space on this iPhone to make the movie."
        case .interrupted:
            "Making the movie stopped when Yuvi left the screen. Please try again."
        case .photosAccessDenied:
            "Yuvi isn’t allowed to save to Photos. You can allow it in Settings."
        case .saveFailed:
            "Couldn’t save the movie to Photos. Please try again."
        }
    }
}

/// What a finished render produced.
struct MovieRenderResult: Sendable {
    let url: URL
    let duration: Double
    let pixelSize: CGSize
    let frames: Int
    let seconds: Double
    let bytes: Int64
}

/// Renders a `MoviePlan` to an H.264 `.mp4`, frame by frame, on-device.
///
/// - 30 fps, 1080×1920 (9:16) or 1920×1080 (16:9), H.264 High profile, ~10 Mbit/s.
/// - Frames are drawn by `MovieFrameDrawer` from `MovieTimeline` (the same as the preview).
/// - Only the photos on screen (and the next one) are in memory, each at the size it is drawn;
///   a scene's pixels are released as soon as it has played.
/// - Cancellable between frames; a cancelled or failed render deletes its partial file.
struct MovieRenderer: Sendable {
    static let framesPerSecond: Int32 = 30
    /// Bits per second at full size (scaled down with the frame area for smaller test renders).
    static let bitRate = 10_000_000

    let plan: MoviePlan
    let loader: any CreationPhotoLoading
    /// 1 for export; tests render small.
    var scale: Double = 1

    func render(to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> MovieRenderResult {
        guard plan.isReady, !plan.scenes.isEmpty else { throw MovieExportError.notEnoughPhotos }
        let started = Date()
        let canvas = plan.settings.aspect.renderSize
        let width = Int((canvas.width * scale / 2).rounded()) * 2
        let height = Int((canvas.height * scale / 2).rounded()) * 2
        let timeline = MovieTimeline(plan: plan)
        let fps = Self.framesPerSecond
        let frameCount = max(1, Int((timeline.duration * Double(fps)).rounded(.down)))

        try? FileManager.default.removeItem(at: url)
        try Self.checkSpace(width: width, height: height, duration: timeline.duration)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw MovieExportError.renderFailed
        }
        let bitRate = max(1_000_000, Int(Double(Self.bitRate) * scale * scale))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2,
                AVVideoExpectedSourceFrameRateKey: Int(fps),
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw MovieExportError.renderFailed }
        writer.add(input)
        guard writer.startWriting() else { throw MovieExportError.renderFailed }
        writer.startSession(atSourceTime: .zero)

        var images: [Int: MovieSceneImages] = [:]
        var missing = Set<Int>()
        let imageLoader = MovieImageLoader(loader: loader, scale: scale)
        do {
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let time = Double(index) / Double(fps)
                let frame = timeline.frame(at: time)

                // Pixels for what's on screen, and the next scene ahead of time; drop the rest.
                var wanted = Set(frame.layers.map(\.sceneIndex))
                if let last = wanted.max(), last + 1 < plan.scenes.count { wanted.insert(last + 1) }
                for key in images.keys where !wanted.contains(key) { images[key] = nil }
                for sceneIndex in wanted.sorted() where images[sceneIndex] == nil && !missing.contains(sceneIndex) {
                    if let loaded = await imageLoader.images(for: plan.scenes[sceneIndex], aspect: plan.settings.aspect) {
                        images[sceneIndex] = loaded
                    } else {
                        missing.insert(sceneIndex)
                    }
                }
                if !missing.isEmpty { throw MovieExportError.missingPhotos(missing.count) }

                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(4))
                }
                guard let buffer = Self.pixelBuffer(from: adaptor, width: width, height: height) else { throw MovieExportError.renderFailed }
                Self.draw(frame, plan: plan, into: buffer, images: images)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps)) else {
                    throw writer.error.map(Self.classify) ?? MovieExportError.renderFailed
                }
                if index % 6 == 0 { progress(Double(index) / Double(frameCount)) }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error.map(Self.classify) ?? MovieExportError.renderFailed
            }
        } catch {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress(1)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return MovieRenderResult(
            url: url,
            duration: Double(frameCount) / Double(fps),
            pixelSize: CGSize(width: width, height: height),
            frames: frameCount,
            seconds: Date().timeIntervalSince(started),
            bytes: bytes
        )
    }

    // MARK: - Frames

    private static func pixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        }
        if buffer == nil {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
        }
        return buffer
    }

    private static func draw(_ frame: MovieTimeline.Frame, plan: MoviePlan, into buffer: CVPixelBuffer, images: [Int: MovieSceneImages]) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        // Top-left origin, like UIKit.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        MovieFrameDrawer.draw(frame, plan: plan, in: context, size: CGSize(width: width, height: height), images: images)
        UIGraphicsPopContext()
    }

    // MARK: - Space and errors

    /// Roughly the file's size plus headroom; refuses early instead of failing at 90%.
    private static func checkSpace(width: Int, height: Int, duration: Double) throws {
        let expected = Double(bitRate) / 8 * duration * Double(width * height) / (1080 * 1920)
        let needed = Int64(expected * 2 + 50_000_000)
        let folder = FileManager.default.temporaryDirectory
        if let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage, available > 0, available < needed {
            throw MovieExportError.notEnoughSpace
        }
    }

    private static func classify(_ error: Error) -> MovieExportError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return .notEnoughSpace }
        if nsError.domain == AVFoundationErrorDomain, nsError.code == AVError.diskFull.rawValue { return .notEnoughSpace }
        if nsError.domain == AVFoundationErrorDomain, nsError.code == AVError.operationInterrupted.rawValue { return .interrupted }
        return .renderFailed
    }

    /// The private temporary folder movies are written to (cleared before each new render).
    static var temporaryFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "ReliveMovies", directoryHint: .isDirectory)
    }

    static func temporaryURL(name: String) throws -> URL {
        let folder = temporaryFolder
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return folder.appending(path: "\(safe).mp4", directoryHint: .notDirectory)
    }

    static func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryFolder)
    }
}
