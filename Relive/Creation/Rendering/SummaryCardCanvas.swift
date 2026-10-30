import ReliveCore
import SwiftUI
import UIKit

/// A 9:16 card that shares a month or a year — sized for a story on Instagram and the like:
/// its name, a few honest counts, a mosaic of its best photos, and the small Yuvi mark.
struct SummaryCardCanvas: View {
    static let size = CreationAspectRatio.story.designSize
    static let mosaicFrame = LayoutRect(x: 70, y: 520, width: 940, height: 1180)

    let eyebrow: String?
    let title: String
    let counts: String
    let photoIDs: [AssetID]
    let images: CanvasImages
    var missing: Set<AssetID> = []

    /// The mosaic, laid out with the Grid style inside `mosaicFrame`.
    static func makeMosaic(aspects: [Double]) -> CollageLayout {
        CollageLayoutEngine().layout(photoAspects: aspects, style: .grid, canvas: mosaicFrame.size, caption: .none)
    }

    let mosaic: CollageLayout

    private static let paper = Color(red: 0.969, green: 0.957, blue: 0.937)
    private static let ink = Color(red: 0.12, green: 0.11, blue: 0.1)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Self.paper
            VStack(alignment: .leading, spacing: 14) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(5)
                        .foregroundStyle(Self.ink.opacity(0.55))
                }
                Text(title)
                    .font(.system(size: 92, weight: .regular, design: .serif))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(counts)
                    .font(.system(size: 28))
                    .foregroundStyle(Self.ink.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 940, height: 300, alignment: .bottomLeading)
            .offset(x: 70, y: 170)

            ForEach(Array(mosaic.slots.enumerated()), id: \.offset) { _, slot in
                let id = photoIDs.indices.contains(slot.photoIndex) ? photoIDs[slot.photoIndex] : nil
                CanvasPhoto(image: id.flatMap { images[$0] }, size: slot.photoFrame.cgSize, isMissing: id.map { missing.contains($0) } ?? true)
                    .placed(at: slot.photoFrame.offsetBy(dx: Self.mosaicFrame.x, dy: Self.mosaicFrame.y))
            }

            YuviMark(height: 40)
                .frame(width: Self.size.width, height: 220)
                .offset(y: Self.mosaicFrame.y + Self.mosaicFrame.height)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}
