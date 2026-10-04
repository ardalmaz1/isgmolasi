import ReliveCore
import SwiftUI

/// Everything the couple chose to keep close: memories, moments and creations. Private and
/// local; favoriting never changes a photo or Apple Photos favorites.
struct FavoritesView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @State private var segment: Segment = .memories
    @State private var viewerSelection: ViewerSelection?

    enum Segment: String, CaseIterable, Identifiable {
        case memories = "Memories"
        case moments = "Moments"
        case creations = "Creations"

        var id: String { rawValue }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let creationColumns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.m, alignment: .top)]

    var body: some View {
        let library = store.creationLibrary
        let memories = store.favoriteMemories
        let moments = library.favoriteMoments
        let creations = store.favoriteKeptItems
        let isEmpty = memories.isEmpty && moments.isEmpty && creations.isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if isEmpty {
                    QuietMessageView(
                        title: "No favorites yet",
                        message: "Favorite memories to keep them close and create from them later."
                    )
                    .accessibilityIdentifier("favoritesEmpty")
                } else {
                    Text(summary(memories: memories.count, moments: moments.count, creations: creations.count))
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.screenMargin)

                    Picker("Show", selection: $segment) {
                        ForEach(Segment.allCases) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.screenMargin)
                    .accessibilityIdentifier("favoritesSegments")

                    switch segment {
                    case .memories: memoryGrid(memories)
                    case .moments: momentList(moments)
                    case .creations: creationGrid(creations)
                    }
                }
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !library.favoritePhotos.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    CreateFromFavoritesMenu(origin: "favorites")
                }
            }
        }
        .fullScreenCover(item: $viewerSelection) { selection in
            AssetViewer(assets: memories, startAssetID: selection.assetID)
        }
    }

    /// "12 memories · 3 moments · 2 creations" — counts, nothing more.
    private func summary(memories: Int, moments: Int, creations: Int) -> String {
        var parts: [String] = []
        if memories > 0 { parts.append(Counted.text(memories, "memory", "memories")) }
        if moments > 0 { parts.append(Counted.text(moments, "moment", "moments")) }
        if creations > 0 { parts.append(Counted.text(creations, "creation", "creations")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func memoryGrid(_ memories: [MemoryAsset]) -> some View {
        if memories.isEmpty {
            segmentMessage("Tap the heart on a photo to keep it here.")
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(memories) { asset in
                    Button {
                        viewerSelection = ViewerSelection(assetID: asset.id)
                    } label: {
                        PhotoGridCell(asset: asset, isFavorite: true)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.setFavorite(.memory, asset.id, isFavorite: false)
                        } label: {
                            Label("Remove from Favorites", systemImage: "heart.slash")
                        }
                    }
                    .accessibilityAction(named: "Remove from Favorites") {
                        store.setFavorite(.memory, asset.id, isFavorite: false)
                    }
                    .accessibilityIdentifier("favoritePhoto")
                }
            }
        }
    }

    @ViewBuilder
    private func momentList(_ moments: [Moment]) -> some View {
        if moments.isEmpty {
            segmentMessage("Tap the heart on a moment to keep it here.")
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                ForEach(moments.reversed()) { moment in
                    NavigationLink(value: MomentRoute(momentID: moment.id, source: "favorites")) {
                        MomentCard(moment: moment)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.setFavorite(.moment, moment.id.uuidString, isFavorite: false)
                        } label: {
                            Label("Remove from Favorites", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
        }
    }

    @ViewBuilder
    private func creationGrid(_ items: [KeptItem]) -> some View {
        if items.isEmpty {
            segmentMessage("Tap the heart on something you made to keep it here.")
        } else {
            LazyVGrid(columns: creationColumns, spacing: Spacing.l) {
                ForEach(items) { item in
                    KeptItemLink(item: item, origin: "favorites")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
        }
    }

    private func segmentMessage(_ text: String) -> some View {
        Text(text)
            .font(Typography.callout)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .padding(.horizontal, Spacing.screenMargin)
    }
}

/// "Create from Favorites": a collage, a story or a book from the memories the couple
/// favorited. When there aren't enough, the flow says so plainly.
struct CreateFromFavoritesMenu: View {
    let origin: String
    var style: Style = .toolbar

    enum Style {
        case toolbar
        case button
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Button { app.startCreation(.collage, from: .source(.favorites), origin: origin) } label: {
                Label("Memory Collage", systemImage: "square.grid.2x2")
            }
            Button { app.startCreation(.story, from: .source(.favorites), origin: origin) } label: {
                Label("Story", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            Button { app.startCreation(.book, from: .source(.favorites), origin: origin) } label: {
                Label("Memory Book", systemImage: "book.closed")
            }
        } label: {
            switch style {
            case .toolbar:
                Label("Create from Favorites", systemImage: "wand.and.stars")
            case .button:
                Text("Create from Favorites")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
        }
        .accessibilityIdentifier("createFromFavorites")
    }
}
