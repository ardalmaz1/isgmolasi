import ReliveCore
import SwiftUI

/// The one favorite control: a heart that keeps a memory, moment or creation close. It changes
/// only Relive's own list — never the photo, its metadata or Apple Photos favorites.
struct FavoriteButton: View {
    let kind: FavoriteKind
    let identifier: String
    /// Colour of the empty heart (white over photos, ink on paper).
    var tint: Color = Palette.textPrimary
    /// What VoiceOver calls it ("Favorite", "Favorite moment"); it adds "Selected" when it is one.
    var label = "Favorite"
    var accessibilityID = "favoriteButton"

    @Environment(StoryStore.self) private var store

    var body: some View {
        let isFavorite = store.isFavorite(kind, identifier)
        Button {
            store.toggleFavorite(kind, identifier)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFavorite ? Palette.favorite : tint)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isFavorite)
        .accessibilityLabel(label)
        .accessibilityValue(isFavorite ? "Selected" : "Not selected")
        .accessibilityHint(isFavorite ? "Removes it from your favorites" : "Keeps it in your favorites")
        .accessibilityIdentifier(accessibilityID)
    }
}

/// A small heart on a thumbnail that is a Relive favorite.
struct FavoriteMark: View {
    /// Over a photo (white with a shadow) or on paper (the accent heart on a paper disc).
    var onPhoto = true

    var body: some View {
        Group {
            if onPhoto {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            } else {
                Image(systemName: "heart.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.favorite)
                    .frame(width: 22, height: 22)
                    .background(Palette.background, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            }
        }
        .padding(6)
        .accessibilityHidden(true)
    }
}

extension Palette {
    /// The filled heart: the app's accent, so it reads as Relive's own mark.
    static let favorite = Palette.accent
}
