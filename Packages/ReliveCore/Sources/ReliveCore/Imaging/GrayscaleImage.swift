import Foundation

/// An 8-bit luminance bitmap. The app renders a small thumbnail into this format; everything
/// computed from it (perceptual hash, contrast, sharpness) is platform-independent and tested.
public struct GrayscaleImage: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major, `width * height` bytes, no padding.
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Builds from a buffer whose rows may be padded (as CoreGraphics bitmaps often are).
    public init?(width: Int, height: Int, bytesPerRow: Int, buffer: UnsafeRawBufferPointer) {
        guard width > 0, height > 0, bytesPerRow >= width, buffer.count >= bytesPerRow * (height - 1) + width else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                pixels[row * width + column] = buffer[row * bytesPerRow + column]
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    // MARK: - Measurements

    /// 64-bit difference hash (dHash): shrink to 9×8, then record whether each pixel is
    /// brighter than its right-hand neighbour. Survives resizing and recompression, which is
    /// exactly what happens when a photo is re-saved from a messaging app.
    ///
    /// `deadBand` (in luminance levels) treats nearly equal neighbours as "not brighter".
    /// Without it, horizontally uniform areas such as a clear sky produce bits decided by
    /// compression noise, and a copy's hash drifts away from its original's.
    public func differenceHash(deadBand: Double = 2) -> UInt64 {
        let small = downsampled(width: 9, height: 8)
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for row in 0..<8 {
            for column in 0..<8 {
                if small[row * 9 + column] - small[row * 9 + column + 1] > deadBand {
                    hash |= 1 << bit
                }
                bit += 1
            }
        }
        return hash
    }

    /// Standard deviation of luminance, 0...1. Near-uniform images have low contrast and their
    /// perceptual hashes are dominated by noise.
    public func contrast() -> Double {
        let count = Double(pixels.count)
        var sum = 0.0, sumOfSquares = 0.0
        for value in pixels {
            let v = Double(value)
            sum += v
            sumOfSquares += v * v
        }
        let mean = sum / count
        let variance = max(0, sumOfSquares / count - mean * mean)
        return variance.squareRoot() / 255
    }

    /// Variance of the 4-neighbour Laplacian — a classic focus measure. Blurry images have few
    /// strong second derivatives, so the variance is low.
    public func laplacianVariance() -> Double {
        guard width >= 3, height >= 3 else { return 0 }
        var sum = 0.0, sumOfSquares = 0.0
        var count = 0.0
        for row in 1..<(height - 1) {
            let base = row * width
            for column in 1..<(width - 1) {
                let center = Double(pixels[base + column])
                let laplacian = Double(pixels[base + column - 1]) + Double(pixels[base + column + 1])
                    + Double(pixels[base - width + column]) + Double(pixels[base + width + column])
                    - 4 * center
                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
            }
        }
        let mean = sum / count
        return max(0, sumOfSquares / count - mean * mean)
    }

    /// Maps Laplacian variance to 0...1 with a soft knee at `halfPoint` (score 0.5).
    /// The default suits thumbnails around 256 px on the long side.
    public func sharpness(halfPoint: Double = 300) -> Double {
        let variance = laplacianVariance()
        return variance / (variance + halfPoint)
    }

    // MARK: - Resampling

    /// Box-filter downsample to the given size. Returns luminance values (not rounded).
    public func downsampled(width targetWidth: Int, height targetHeight: Int) -> [Double] {
        var output = [Double](repeating: 0, count: targetWidth * targetHeight)
        for targetRow in 0..<targetHeight {
            let rowStart = targetRow * height / targetHeight
            let rowEnd = max(rowStart + 1, (targetRow + 1) * height / targetHeight)
            for targetColumn in 0..<targetWidth {
                let columnStart = targetColumn * width / targetWidth
                let columnEnd = max(columnStart + 1, (targetColumn + 1) * width / targetWidth)
                var sum = 0.0
                for row in rowStart..<min(rowEnd, height) {
                    let base = row * width
                    for column in columnStart..<min(columnEnd, width) {
                        sum += Double(pixels[base + column])
                    }
                }
                let area = Double((min(rowEnd, height) - rowStart) * (min(columnEnd, width) - columnStart))
                output[targetRow * targetWidth + targetColumn] = area > 0 ? sum / area : 0
            }
        }
        return output
    }

    /// Box-filter downsample so the longest side is at most `maxDimension`.
    public func scaled(maxDimension: Int) -> GrayscaleImage {
        let longest = max(width, height)
        guard longest > maxDimension, maxDimension > 0 else { return self }
        let scale = Double(maxDimension) / Double(longest)
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        let values = downsampled(width: targetWidth, height: targetHeight)
        let bytes = values.map { UInt8(clamping: Int($0.rounded())) }
        return GrayscaleImage(width: targetWidth, height: targetHeight, pixels: bytes) ?? self
    }
}

/// Pixel-derived measurements used by the analyzer.
public struct PixelMetrics: Hashable, Sendable {
    public var differenceHash: UInt64
    public var contrast: Double
    public var sharpness: Double

    public init(image: GrayscaleImage, sharpnessDimension: Int = 256) {
        differenceHash = image.differenceHash()
        contrast = image.contrast()
        sharpness = image.scaled(maxDimension: sharpnessDimension).sharpness()
    }
}
