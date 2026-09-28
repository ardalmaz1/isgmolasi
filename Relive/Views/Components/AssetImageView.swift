import ReliveCore
import SwiftUI

/// Shows one photo (or a video's poster frame) from the library, sized to its container.
/// Fills its frame; the parent decides the shape. Missing photos degrade to a quiet placeholder.
struct AssetImageView: View {
    let assetID: AssetID?
    var contentMode: ContentMode = .fill
    /// Extra resolution factor, e.g. for zoomable full-screen images.
    var quality: CGFloat = 1

    @Environment(\.photoImageLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedID: AssetID?
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Palette.placeholder
                if let image, loadedID == assetID {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeOut(duration: 0.25)))
                } else if failed {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Palette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .task(id: LoadKey(assetID: assetID, bucket: bucket(for: proxy.size))) {
                await load(size: proxy.size)
            }
        }
    }

    private struct LoadKey: Hashable {
        let assetID: AssetID?
        let bucket: Int
    }

    /// Requests are bucketed to 128 px steps so small layout changes reuse cached images.
    private func bucket(for size: CGSize) -> Int {
        let longest = max(size.width, size.height) * displayScale * quality
        return Int((longest / 128).rounded(.up))
    }

    private func load(size: CGSize) async {
        guard let assetID, size.width > 0, size.height > 0 else { return }
        let side = CGFloat(bucket(for: size)) * 128
        let aspect = size.width / max(size.height, 1)
        let pixelSize = aspect >= 1
            ? CGSize(width: side, height: (side / aspect).rounded(.up))
            : CGSize(width: (side * aspect).rounded(.up), height: side)
        let result = await loader.image(
            for: assetID,
            pixelSize: pixelSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit
        )
        guard !Task.isCancelled else { return }
        if let result {
            image = result
            loadedID = assetID
            failed = false
        } else if loadedID != assetID {
            failed = true
        }
    }
}

/// A photo in a fixed aspect ratio with the app's photo corner radius.
struct FramedAssetImage: View {
    let assetID: AssetID?
    var aspectRatio: CGFloat = 4 / 5
    var cornerRadius: CGFloat = Radius.photo

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { AssetImageView(assetID: assetID) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
