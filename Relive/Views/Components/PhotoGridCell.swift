import ReliveCore
import SwiftUI

/// Square thumbnail used in moment grids. Videos show their duration; favorites a small mark.
struct PhotoGridCell: View {
    let asset: MemoryAsset

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { AssetImageView(assetID: asset.id) }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.kind == .video {
                    Text(Self.durationText(asset.duration))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [asset.kind == .video ? "Video" : "Photo"]
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if asset.isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
