import CoreGraphics
import os
import ReliveCore
import Vision

/// On-device image analysis with Vision, run on a small thumbnail (never the full-resolution
/// original).
///
/// Signals: number of faces and their capture quality (no identification — Relive never learns
/// who is in a photo), a feature print for similarity, Apple's aesthetics estimate (which also
/// flags "utility" images such as receipts and screenshots of text), and pixel statistics from
/// ReliveCore (perceptual hash, contrast, sharpness).
///
/// Every request fails independently; failures are recorded so the engine can degrade gracefully.
struct VisionAssetAnalyzer: AssetAnalyzing {
    private static let logger = Logger(subsystem: "app.relive", category: "analysis")

    let imageLoader: PhotoImageLoader
    /// Longest side of the analysis thumbnail, in pixels.
    var thumbnailDimension: CGFloat = 512

    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis {
        guard let image = await imageLoader.analysisImage(for: asset.id, maxDimension: thumbnailDimension) else {
            return .unavailable()
        }
        return await Self.analyze(image: image)
    }

    static func analyze(image: CGImage) async -> AssetAnalysis {
        var analysis = AssetAnalysis()
        var failures: AnalysisFailures = []

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])

        // Faces and their capture quality.
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        do {
            try handler.perform([faceRequest])
            let faces = faceRequest.results ?? []
            analysis.faceCount = faces.count
            analysis.faceCaptureQuality = faces.compactMap { $0.faceCaptureQuality }.max().map(Double.init)
        } catch {
            failures.insert(.faceDetection)
            logger.debug("Face analysis failed: \(error.localizedDescription, privacy: .public)")
        }

        // Feature print for similarity.
        let printRequest = VNGenerateImageFeaturePrintRequest()
        var featureVector: [Float]?
        do {
            try handler.perform([printRequest])
            featureVector = printRequest.results?.first.flatMap(floats(from:))
            if featureVector == nil { failures.insert(.featurePrint) }
        } catch {
            failures.insert(.featurePrint)
            logger.debug("Feature print failed: \(error.localizedDescription, privacy: .public)")
        }

        // Aesthetics and utility detection.
        do {
            let observation = try await CalculateImageAestheticsScoresRequest().perform(on: image)
            // overallScore is in -1...1.
            analysis.aestheticScore = Double((observation.overallScore + 1) / 2)
            analysis.isUtility = observation.isUtility
        } catch {
            failures.insert(.aesthetics)
            logger.debug("Aesthetics failed: \(error.localizedDescription, privacy: .public)")
        }

        // Perceptual hash, contrast and sharpness.
        var fingerprint = VisualFingerprint(featureVector: featureVector)
        if let grayscale = grayscale(from: image, maxDimension: 256) {
            let metrics = PixelMetrics(image: grayscale)
            fingerprint.differenceHash = metrics.differenceHash
            fingerprint.contrast = metrics.contrast
            analysis.sharpness = metrics.sharpness
        } else {
            failures.insert(.pixelMetrics)
        }

        analysis.fingerprint = fingerprint
        analysis.failures = failures
        return analysis
    }

    /// Converts a Vision feature print into a Float array (either element type is possible).
    private static func floats(from observation: VNFeaturePrintObservation) -> [Float]? {
        let data = observation.data
        let count = observation.elementCount
        guard count > 0 else { return nil }
        switch observation.elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return nil }
            return data.withUnsafeBytes { raw in
                (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
            }
        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return nil }
            return data.withUnsafeBytes { raw in
                (0..<count).map { Float(raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Double>.size, as: Double.self)) }
            }
        default:
            return nil
        }
    }

    /// Renders the image into an 8-bit grayscale bitmap no larger than `maxDimension`.
    private static func grayscale(from image: CGImage, maxDimension: Int) -> GrayscaleImage? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Double(maxDimension) / Double(longest))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        return GrayscaleImage(width: width, height: height, pixels: pixels)
    }
}
