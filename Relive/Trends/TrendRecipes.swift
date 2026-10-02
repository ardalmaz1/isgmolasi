import CoreImage
import ReliveCore
import SwiftUI
import UIKit

// Recipes: how the app makes each on-device trend. A recipe is compiled into the app and is
// identified by id and version ("bw-editorial@1"); catalogs refer to recipes, they never contain
// them. Improving a trend later means adding "@2" here and publishing the trend with it — older
// apps, which don't have @2, simply don't show the trend (see TrendCatalogFilter).

/// A chosen photo, ready to draw.
struct TrendPhoto {
    let assetID: AssetID
    let image: UIImage?
    let date: Date?
}

/// Real facts a recipe may print. Nothing is invented: every value can be nil.
struct TrendRenderContext {
    var facts: CreationFacts
    /// "Jake & Emma" — only when the user gave both names.
    var coupleNames: String?
    var variation: Int
}

@MainActor
protocol TrendRecipe {
    var reference: TrendRecipeReference { get }
    /// Named variations for "Try another". At least one.
    var variations: [String] { get }
    var aspectRatio: CreationAspectRatio { get }
    /// The size (in design points) each photo is drawn at, for loading export images.
    func photoFrames(count: Int) -> [CanvasSize]
    /// Image processing applied to each photo (off the main thread). Identity by default.
    func process(_ image: UIImage, variation: Int) async -> UIImage
    func canvas(photos: [TrendPhoto], context: TrendRenderContext) -> AnyView
}

extension TrendRecipe {
    var designSize: CanvasSize { aspectRatio.designSize }

    func process(_ image: UIImage, variation: Int) async -> UIImage { image }
}

/// The recipes this build implements. The catalog filter hides trends whose recipe isn't here.
@MainActor
enum TrendRecipeRegistry {
    static let all: [any TrendRecipe] = [
        BWEditorialRecipe(),
        FilmCoupleRecipe(),
        PhotoBoothRecipe(),
        MagazineCoverRecipe(),
        CinematicPosterRecipe(),
    ]

    static var supported: Set<TrendRecipeReference> { Set(all.map(\.reference)) }

    static func recipe(for reference: TrendRecipeReference) -> (any TrendRecipe)? {
        all.first { $0.reference == reference }
    }
}

// MARK: - Image processing

/// Core Image steps shared by recipes. Deterministic: the same photo and variation always give
/// the same pixels (the grain is a fixed pattern).
enum TrendImageProcessing {
    /// One shared context. CIContext is thread-safe; the box keeps this warning-free on SDKs
    /// that do and don't mark it Sendable.
    private final class SharedContext: @unchecked Sendable {
        let context = CIContext(options: [.cacheIntermediates: false])
    }
    private static let shared = SharedContext()

    /// Runs `transform` on an upright version of `image`, off the main thread.
    static func apply(_ image: UIImage, _ transform: @escaping @Sendable (CIImage) -> CIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return image }
            let input = CIImage(cgImage: cgImage).oriented(CGImagePropertyOrientation(image.imageOrientation))
            let output = transform(input).cropped(to: input.extent)
            guard let rendered = shared.context.createCGImage(output, from: input.extent) else { return image }
            return UIImage(cgImage: rendered)
        }.value
    }

    static func monochrome(_ image: CIImage, tonal: Bool, contrast: Double) -> CIImage {
        image
            .applyingFilter(tonal ? "CIPhotoEffectTonal" : "CIPhotoEffectNoir")
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: contrast])
    }

    /// Scales red and blue against green: > 1 red warms, > 1 blue cools.
    static func colour(_ image: CIImage, red: Double, blue: Double, lift: Double, saturation: Double, contrast: Double) -> CIImage {
        image
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
                "inputBiasVector": CIVector(x: lift, y: lift * 0.9, z: lift * 0.75, w: 0),
            ])
    }

    static func vignette(_ image: CIImage, intensity: Double) -> CIImage {
        image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: intensity, kCIInputRadiusKey: 1.6])
    }

    /// Fine monochrome grain, soft-light blended. The noise is a fixed pattern, so it repeats exactly.
    static func grain(_ image: CIImage, amount: Double) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let scale = max(1, image.extent.width / 1400)
        let grey = noise
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount),
            ])
            .cropped(to: image.extent)
        return grey.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }
}

/// Text helpers shared by recipe canvases.
@MainActor
enum TrendText {
    static func place(_ context: TrendRenderContext) -> String? {
        CreationText.place(context.facts.place) ?? {
            if case .named(let name)? = context.facts.title { return name }
            return nil
        }()
    }

    static func period(_ context: TrendRenderContext) -> String? {
        CreationText.periodLine(context.facts.dateSpan)
    }

    static func day(_ context: TrendRenderContext) -> String? {
        CreationText.dateLine(context.facts.dateSpan)
    }
}

// MARK: - B&W Editorial (local)

struct BWEditorialRecipe: TrendRecipe {
    let reference = TrendRecipeReference(id: "bw-editorial", version: 1)
    let variations = ["Noir", "Soft"]
    let aspectRatio = CreationAspectRatio.portrait

    static let border: CGFloat = 64
    static let bottomBand: CGFloat = 210

    func photoFrames(count: Int) -> [CanvasSize] {
        let size = designSize
        let width = size.width - 2 * Self.border
        let height = size.height - Self.border - Self.bottomBand
        if count >= 2 {
            let each = (width - 24) / 2
            return [CanvasSize(width: each, height: height), CanvasSize(width: each, height: height)]
        }
        return [CanvasSize(width: width, height: height)]
    }

    func process(_ image: UIImage, variation: Int) async -> UIImage {
        let tonal = variation % variations.count == 1
        return await TrendImageProcessing.apply(image) { input in
            TrendImageProcessing.grain(
                TrendImageProcessing.monochrome(input, tonal: tonal, contrast: tonal ? 1.0 : 1.18),
                amount: 0.22
            )
        }
    }

    func canvas(photos: [TrendPhoto], context: TrendRenderContext) -> AnyView {
        let frames = photoFrames(count: photos.count)
        let size = designSize
        return AnyView(
            ZStack(alignment: .topLeading) {
                Color(white: 0.985)
                HStack(spacing: 24) {
                    ForEach(Array(zip(photos.prefix(frames.count), frames).enumerated()), id: \.offset) { _, pair in
                        CanvasPhoto(image: pair.0.image, size: pair.1.cgSize, isMissing: pair.0.image == nil)
                    }
                }
                .offset(x: Self.border, y: Self.border)
                VStack(alignment: .leading, spacing: 10) {
                    if let place = TrendText.place(context) {
                        Text(place.uppercased())
                            .font(.system(size: 40, weight: .semibold))
                            .tracking(10)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if let day = TrendText.day(context) {
                        Text(day.uppercased())
                            .font(.system(size: 22, weight: .medium))
                            .tracking(4)
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
                .foregroundStyle(Color(white: 0.08))
                .frame(width: size.width - 2 * Self.border, height: Self.bottomBand - 40, alignment: .leading)
                .offset(x: Self.border, y: size.height - Self.bottomBand + 20)
                MadeWithRelive(size: 18, color: Color(white: 0.55))
                    .frame(width: size.width - 2 * Self.border, alignment: .trailing)
                    .offset(x: Self.border, y: size.height - 56)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        )
    }
}

// MARK: - Film Couple (local)

struct FilmCoupleRecipe: TrendRecipe {
    let reference = TrendRecipeReference(id: "film-couple", version: 1)
    let variations = ["Warm", "Faded", "Cool"]
    let aspectRatio = CreationAspectRatio.portrait

    func photoFrames(count: Int) -> [CanvasSize] { [designSize] }

    func process(_ image: UIImage, variation: Int) async -> UIImage {
        let choice = variation % variations.count
        return await TrendImageProcessing.apply(image) { input in
            let graded: CIImage
            switch choice {
            case 1: graded = TrendImageProcessing.colour(input, red: 1.03, blue: 0.95, lift: 0.07, saturation: 0.82, contrast: 0.9)
            case 2: graded = TrendImageProcessing.colour(input, red: 0.96, blue: 1.05, lift: 0.03, saturation: 0.95, contrast: 1.04)
            default: graded = TrendImageProcessing.colour(input, red: 1.07, blue: 0.9, lift: 0.035, saturation: 1.08, contrast: 1.05)
            }
            return TrendImageProcessing.grain(TrendImageProcessing.vignette(graded, intensity: 0.55), amount: 0.28)
        }
    }

    func canvas(photos: [TrendPhoto], context: TrendRenderContext) -> AnyView {
        let size = designSize
        let stamp = CreationText.filmStamp(photos.first?.date)
        return AnyView(
            ZStack(alignment: .bottomTrailing) {
                CanvasPhoto(image: photos.first?.image, size: size.cgSize, isMissing: photos.first?.image == nil)
                if let stamp {
                    Text(stamp)
                        .font(.system(size: 46, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.18))
                        .shadow(color: Color(red: 1, green: 0.4, blue: 0.1).opacity(0.7), radius: 8)
                        .padding(.trailing, 70)
                        .padding(.bottom, 90)
                }
                MadeWithRelive(size: 18, color: .white.opacity(0.75))
                    .padding(.bottom, 30)
                    .frame(width: size.width, alignment: .center)
            }
            .frame(width: size.width, height: size.height)
        )
    }
}

// MARK: - Photo Booth Strip (template)

struct PhotoBoothRecipe: TrendRecipe {
    let reference = TrendRecipeReference(id: "photo-booth", version: 1)
    let variations = ["Black & White", "Colour"]
    let aspectRatio = CreationAspectRatio.story

    static let stripWidth: CGFloat = 560
    static let padding: CGFloat = 32
    static let gap: CGFloat = 22
    static let footer: CGFloat = 110

    private func frameSize(count: Int) -> CanvasSize {
        let width = Self.stripWidth - 2 * Self.padding
        return CanvasSize(width: width, height: count >= 4 ? width * 0.86 : width * 1.05)
    }

    func photoFrames(count: Int) -> [CanvasSize] {
        Array(repeating: frameSize(count: count), count: count)
    }

    func process(_ image: UIImage, variation: Int) async -> UIImage {
        guard variation % variations.count == 0 else {
            return await TrendImageProcessing.apply(image) { TrendImageProcessing.colour($0, red: 1.02, blue: 0.97, lift: 0.02, saturation: 1.05, contrast: 1.06) }
        }
        return await TrendImageProcessing.apply(image) { input in
            TrendImageProcessing.grain(TrendImageProcessing.monochrome(input, tonal: false, contrast: 1.12), amount: 0.18)
        }
    }

    func canvas(photos: [TrendPhoto], context: TrendRenderContext) -> AnyView {
        let size = designSize
        let frame = frameSize(count: photos.count)
        let stripHeight = Self.padding + CGFloat(photos.count) * frame.height + CGFloat(max(0, photos.count - 1)) * Self.gap + Self.footer
        return AnyView(
            ZStack {
                Color(red: 0.86, green: 0.81, blue: 0.74)
                VStack(spacing: Self.gap) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                        CanvasPhoto(image: photo.image, size: frame.cgSize, isMissing: photo.image == nil)
                    }
                    Text(TrendText.day(context) ?? " ")
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.3))
                        .frame(height: Self.footer - Self.gap - Self.padding / 2)
                }
                .padding(.top, Self.padding)
                .frame(width: Self.stripWidth, height: stripHeight, alignment: .top)
                .background(Color(white: 0.985))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .rotationEffect(.degrees(-2.5))
                MadeWithRelive(size: 20, color: Color(white: 0.35))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
            }
            .frame(width: size.width, height: size.height)
        )
    }
}

// MARK: - Magazine Cover (template)

struct MagazineCoverRecipe: TrendRecipe {
    let reference = TrendRecipeReference(id: "magazine-cover", version: 1)
    let variations = ["White", "Black", "Red"]
    let aspectRatio = CreationAspectRatio.portrait

    func photoFrames(count: Int) -> [CanvasSize] { [designSize] }

    func canvas(photos: [TrendPhoto], context: TrendRenderContext) -> AnyView {
        let size = designSize
        let masthead: Color = switch context.variation % variations.count {
        case 1: .black
        case 2: Color(red: 0.82, green: 0.1, blue: 0.12)
        default: .white
        }
        let lines = Color.white
        return AnyView(
            ZStack(alignment: .topLeading) {
                CanvasPhoto(image: photos.first?.image, size: size.cgSize, isMissing: photos.first?.image == nil)
                LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Text("US")
                        .font(.system(size: 300, weight: .black, design: .serif))
                        .foregroundStyle(masthead)
                        .tracking(-6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 10)
                    if let period = TrendText.period(context) {
                        Text(period.uppercased())
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(6)
                            .foregroundStyle(lines)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        if let place = TrendText.place(context) {
                            Text(place)
                                .font(.system(size: 92, weight: .bold, design: .serif))
                                .foregroundStyle(lines)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                        }
                        if let names = context.coupleNames {
                            Text(names.uppercased())
                                .font(.system(size: 30, weight: .semibold))
                                .tracking(5)
                                .foregroundStyle(lines)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 70)
                    .padding(.bottom, 110)
                }
                .shadow(color: .black.opacity(0.3), radius: 10)
                .frame(width: size.width, height: size.height)
                MadeWithRelive(size: 18, color: .white.opacity(0.8))
                    .frame(width: size.width - 140, alignment: .trailing)
                    .offset(x: 70, y: size.height - 60)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        )
    }
}

// MARK: - Cinematic Poster (template)

struct CinematicPosterRecipe: TrendRecipe {
    let reference = TrendRecipeReference(id: "cinematic-poster", version: 1)
    let variations = ["Colour", "Mono"]
    let aspectRatio = CreationAspectRatio.story

    /// A 2.39 : 1 widescreen frame across the poster.
    func photoFrames(count: Int) -> [CanvasSize] {
        [CanvasSize(width: designSize.width, height: (designSize.width / 2.39).rounded())]
    }

    func process(_ image: UIImage, variation: Int) async -> UIImage {
        if variation % variations.count == 1 {
            return await TrendImageProcessing.apply(image) { TrendImageProcessing.monochrome($0, tonal: true, contrast: 1.1) }
        }
        return await TrendImageProcessing.apply(image) { input in
            TrendImageProcessing.vignette(
                TrendImageProcessing.colour(input, red: 1.04, blue: 1.02, lift: 0.0, saturation: 0.9, contrast: 1.12),
                intensity: 0.4
            )
        }
    }

    func canvas(photos: [TrendPhoto], context: TrendRenderContext) -> AnyView {
        let size = designSize
        let frame = photoFrames(count: 1)[0]
        let title = TrendText.place(context)
        var credits: [String] = []
        if let names = context.coupleNames { credits.append("starring \(names)") }
        if let day = TrendText.day(context) { credits.append("filmed \(day)") }
        return AnyView(
            ZStack {
                Color.black
                VStack(spacing: 70) {
                    if let title {
                        Text(title.uppercased())
                            .font(.system(size: 64, weight: .light))
                            .tracking(26)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .padding(.horizontal, 60)
                    }
                    CanvasPhoto(image: photos.first?.image, size: frame.cgSize, isMissing: photos.first?.image == nil)
                    VStack(spacing: 14) {
                        ForEach(credits, id: \.self) { line in
                            Text(line.uppercased())
                                .font(.system(size: 22, weight: .regular).width(.condensed))
                                .tracking(6)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                MadeWithRelive(size: 18, color: .white.opacity(0.5))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
            }
            .frame(width: size.width, height: size.height)
        )
    }
}
