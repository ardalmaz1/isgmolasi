import Foundation
import Testing
@testable import ReliveCore

/// Synthetic "photos" built from gradients and shapes.
enum SyntheticImage {
    /// A scene with a horizon, a sun and a figure. `variant` shifts the composition.
    static func scene(width: Int, height: Int, variant: Int = 0) -> GrayscaleImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let fy = Double(y) / Double(height)
                let fx = Double(x) / Double(width)
                var value = fy < 0.55 ? 200 - 120 * fy : 60 + 40 * fx
                let sunX = 0.7 - 0.4 * Double(variant % 2), sunY = 0.25
                if (fx - sunX) * (fx - sunX) + (fy - sunY) * (fy - sunY) < 0.01 { value = 250 }
                if fx > 0.3 && fx < 0.4 && fy > 0.4 && fy < 0.9 { value = 20 }
                pixels[y * width + x] = UInt8(clamping: Int(value))
            }
        }
        return make(width, height, pixels)
    }

    static func checkerboard(size: Int, cell: Int) -> GrayscaleImage {
        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size where ((x / cell) + (y / cell)).isMultiple(of: 2) {
                pixels[y * size + x] = 255
            }
        }
        return make(size, size, pixels)
    }

    static func flat(size: Int, value: UInt8) -> GrayscaleImage {
        make(size, size, [UInt8](repeating: value, count: size * size))
    }

    /// Resized copy with deterministic noise — what a messaging app does to a photo.
    static func recompressed(_ image: GrayscaleImage, maxDimension: Int, noise: Int) -> GrayscaleImage {
        let small = image.scaled(maxDimension: maxDimension)
        var state: UInt64 = 42
        let noisy = small.pixels.map { value -> UInt8 in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let delta = Int(state >> 60) % (2 * noise + 1) - noise
            return UInt8(clamping: Int(value) + delta)
        }
        return make(small.width, small.height, noisy)
    }

    static func boxBlurred(_ image: GrayscaleImage, radius: Int) -> GrayscaleImage {
        var output = image.pixels
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum = 0, count = 0
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < image.width, ny < image.height else { continue }
                        sum += Int(image.pixels[ny * image.width + nx])
                        count += 1
                    }
                }
                output[y * image.width + x] = UInt8(sum / count)
            }
        }
        return make(image.width, image.height, output)
    }

    /// Synthetic dimensions are always valid; this only unwraps the failable initializer.
    private static func make(_ width: Int, _ height: Int, _ pixels: [UInt8]) -> GrayscaleImage {
        guard let image = GrayscaleImage(width: width, height: height, pixels: pixels) else {
            fatalError("Invalid synthetic image \(width)×\(height)")
        }
        return image
    }
}

@Suite("GrayscaleImage")
struct GrayscaleImageTests {
    @Test("A resized, recompressed copy has a nearly identical hash")
    func recompressedCopyMatches() {
        let original = SyntheticImage.scene(width: 480, height: 640)
        let copy = SyntheticImage.recompressed(original, maxDimension: 200, noise: 4)
        let distance = (original.differenceHash() ^ copy.differenceHash()).nonzeroBitCount
        #expect(distance <= 5)
    }

    @Test("A different composition has a distant hash")
    func differentSceneDiffers() {
        let first = SyntheticImage.scene(width: 480, height: 640, variant: 0)
        let second = SyntheticImage.scene(width: 480, height: 640, variant: 1)
        let flipped = SyntheticImage.checkerboard(size: 256, cell: 16)
        #expect((first.differenceHash() ^ second.differenceHash()).nonzeroBitCount > 5)
        #expect((first.differenceHash() ^ flipped.differenceHash()).nonzeroBitCount > 10)
    }

    @Test("Sharp detail scores higher than the same image blurred")
    func sharpnessOrdersBlur() {
        let sharp = SyntheticImage.checkerboard(size: 128, cell: 4)
        let blurred = SyntheticImage.boxBlurred(sharp, radius: 3)
        #expect(sharp.sharpness() > blurred.sharpness())
        #expect(SyntheticImage.flat(size: 64, value: 128).sharpness() == 0)
    }

    @Test("Contrast is zero for flat images and high for checkerboards")
    func contrastRange() {
        #expect(SyntheticImage.flat(size: 32, value: 90).contrast() == 0)
        #expect(SyntheticImage.checkerboard(size: 32, cell: 4).contrast() > 0.45)
    }

    @Test("Padded rows are read correctly")
    func paddedRows() throws {
        let bytes: [UInt8] = [1, 2, 0, 0, 3, 4, 0, 0]
        let image = try #require(bytes.withUnsafeBytes { GrayscaleImage(width: 2, height: 2, bytesPerRow: 4, buffer: $0) })
        #expect(image.pixels == [1, 2, 3, 4])
    }

    @Test("Scaling keeps aspect ratio and never upsamples")
    func scaling() {
        let image = SyntheticImage.scene(width: 400, height: 200)
        let scaled = image.scaled(maxDimension: 100)
        #expect(scaled.width == 100 && scaled.height == 50)
        #expect(image.scaled(maxDimension: 1000).width == 400)
    }

    @Test("Pixel metrics combine hash, contrast and sharpness")
    func pixelMetrics() {
        let metrics = PixelMetrics(image: SyntheticImage.scene(width: 300, height: 400))
        #expect(metrics.contrast > 0.1)
        #expect(metrics.sharpness > 0 && metrics.sharpness < 1)
    }
}
