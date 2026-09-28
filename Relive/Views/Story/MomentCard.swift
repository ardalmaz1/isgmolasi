import ReliveCore
import SwiftUI

/// A moment in the timeline: the cover dominates; text stays small and factual. Larger moments
/// get a strip of three more photos underneath, like a photo-book spread.
struct MomentCard: View {
    let moment: Moment

    @Environment(StoryStore.self) private var store

    var body: some View {
        let hero = store.heroAssetID(for: moment)
        let extras = extraAssetIDs(excluding: hero)
        let note = store.userState(for: moment.id).note

        VStack(alignment: .leading, spacing: Spacing.s) {
            FramedAssetImage(assetID: hero, aspectRatio: 4 / 5)

            if !extras.isEmpty {
                HStack(spacing: 3) {
                    ForEach(extras, id: \.self) { id in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { AssetImageView(assetID: id) }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.photo / 2, style: .continuous))
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(moment.title.primary)
                    .font(Typography.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(detailLine)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if let note, !note.isEmpty {
                    Text("“\(note)”")
                        .font(Typography.bodySerif.italic())
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .padding(.top, Spacing.xxs)
                }
            }
            .padding(.top, Spacing.xxs)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(note: note))
        .accessibilityAddTraits(.isButton)
    }

    private var memoryCount: Int {
        moment.assetIDs.filter { store.isAvailable($0) && !moment.duplicateAssetIDs.contains($0) }.count
    }

    /// "August 6 – 9 · 64 memories"
    private var detailLine: String {
        var parts: [String] = []
        if let range = DateText.range(start: moment.startDate, end: moment.endDate) {
            parts.append(range)
        }
        parts.append(Counted.text(memoryCount, "memory", "memories"))
        return parts.joined(separator: " · ")
    }

    private func extraAssetIDs(excluding hero: AssetID?) -> [AssetID] {
        let candidates = moment.featuredAssetIDs.filter { $0 != hero && store.isAvailable($0) }
        guard candidates.count >= 4 else { return [] }
        // Evenly spaced through the moment so the strip shows its arc, not three near-identical shots.
        let step = Double(candidates.count) / 3
        return (0..<3).map { index in candidates[min(candidates.count - 1, Int(Double(index) * step + step / 2))] }
    }

    private func accessibilityText(note: String?) -> String {
        var parts = [moment.title.primary, detailLine]
        if let place = moment.place?.name, place != moment.title.primary {
            parts.append(place)
        }
        if let note, !note.isEmpty {
            parts.append("Your note: \(note)")
        }
        return parts.joined(separator: ", ")
    }
}
