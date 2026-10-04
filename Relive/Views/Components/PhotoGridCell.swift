import ReliveCore
import SwiftUI

/// Square thumbnail used in moment grids. Videos show their duration; Relive favorites a small
/// mark. (Apple Photos favorites are not shown here: Relive's favorites are its own.)
struct PhotoGridCell: View {
    let asset: MemoryAsset
    /// A Relive favorite.
    var isFavorite = false

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
                if isFavorite { FavoriteMark() }
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
        if isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
