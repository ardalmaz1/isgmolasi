import ReliveCore
import SwiftUI
import UIKit

/// A 4:5 card that shares a month or a year: its name, a few honest counts, and a mosaic of its
/// best photos.
struct SummaryCardCanvas: View {
    static let size = CreationAspectRatio.portrait.designSize
    static let mosaicFrame = LayoutRect(x: 70, y: 400, width: 940, height: 860)

    let eyebrow: String?
    let title: String
    let counts: String
    let photoIDs: [AssetID]
    let images: CanvasImages
    var missing: Set<AssetID> = []
    var showsWatermark = true

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
            .offset(x: 70, y: 60)

            ForEach(Array(mosaic.slots.enumerated()), id: \.offset) { _, slot in
                let id = photoIDs.indices.contains(slot.photoIndex) ? photoIDs[slot.photoIndex] : nil
                CanvasPhoto(image: id.flatMap { images[$0] }, size: slot.photoFrame.cgSize, isMissing: id.map { missing.contains($0) } ?? true)
                    .placed(at: slot.photoFrame.offsetBy(dx: Self.mosaicFrame.x, dy: Self.mosaicFrame.y))
            }

            if showsWatermark {
                MadeWithRelive(size: 20, color: Self.ink.opacity(0.4))
                    .frame(width: 940, height: 40, alignment: .trailing)
                    .offset(x: 70, y: Self.size.height - 66)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}
