import ReliveCore
import SwiftUI

/// The couple's own collection: reachable from Create and from Us (no extra tab).
enum CollectionRoute: Hashable {
    case favorites
    case creations
    case drafts
    case book(UUID)
}

extension View {
    /// Registers the collection screens for a navigation stack.
    func collectionDestinations() -> some View {
        navigationDestination(for: CollectionRoute.self) { route in
            switch route {
            case .favorites: FavoritesView()
            case .creations: MyCreationsView()
            case .drafts: DraftsView()
            case .book(let id): MemoryBookReaderView(bookID: id)
            }
        }
    }
}
