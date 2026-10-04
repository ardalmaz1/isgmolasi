import ReliveCore
import SwiftUI

/// My Creations: the collages, stories and books the couple made, most recent first. Each is
/// kept as its state and drawn again from their photos; deleting one never touches a photo.
struct MyCreationsView: View {
    @Environment(StoryStore.self) private var store
    @State private var filter: KeptKind?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.m, alignment: .top)]

    var body: some View {
        let all = store.keptItems
        let kinds = KeptKind.allCases.filter { kind in all.contains { $0.kind == kind } }
        let items = filter.map { kind in all.filter { $0.kind == kind } } ?? all

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if all.isEmpty {
                    QuietMessageView(
                        title: "Nothing here yet",
                        message: "Things you make with Relive will appear here."
                    )
                    .accessibilityIdentifier("creationsEmpty")
                } else {
                    if kinds.count > 1 {
                        Picker("Show", selection: $filter) {
                            Text("All").tag(KeptKind?.none)
                            ForEach(kinds) { kind in
                                Text(kind.pluralName).tag(KeptKind?.some(kind))
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Spacing.screenMargin)
                        .accessibilityIdentifier("creationsFilter")
                    }
                    LazyVGrid(columns: columns, spacing: Spacing.l) {
                        ForEach(items) { item in
                            KeptItemLink(item: item, origin: "my_creations")
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle("My Creations")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: kinds) { _, kinds in
            if let filter, !kinds.contains(filter) { self.filter = nil }
        }
    }
}

/// A creation's card that opens it: books in the reader, collages and stories in their editor
/// exactly as they were left. Touch and hold for Favorite and Delete.
struct KeptItemLink: View {
    let item: KeptItem
    let origin: String
    var width: CGFloat?

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            switch item {
            case .book(let book):
                NavigationLink(value: CollectionRoute.book(book.id)) {
                    CreationCard(item: item, width: width)
                }
                .accessibilityIdentifier("savedBook")
            case .creation(let creation):
                Button {
                    app.open(item, origin: origin)
                } label: {
                    CreationCard(item: item, width: width)
                }
                .accessibilityIdentifier(creation.kind == .collage ? "savedCollage" : "savedStory")
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { app.open(item, origin: origin) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
            let isFavorite = store.isFavorite(.creation, item.favoriteID)
            Button { store.toggleFavorite(.creation, item.favoriteID) } label: {
                Label(isFavorite ? "Remove from Favorites" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            Divider()
            Button(role: .destructive) { confirmsDelete = true } label: {
                Label("Delete \(item.kind.name)", systemImage: "trash")
            }
        }
        .accessibilityHint("Opens it. More actions are available.")
        .accessibilityActions {
            Button(store.isFavorite(.creation, item.favoriteID) ? "Remove from Favorites" : "Favorite") {
                store.toggleFavorite(.creation, item.favoriteID)
            }
            Button("Delete \(item.kind.name)") { confirmsDelete = true }
        }
        .confirmationDialog("Delete this \(item.kind.name.lowercased())?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete \(item.kind.name)", role: .destructive) { store.deleteKept(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It’s removed from Relive. Its photos stay in Relive and in the Photos app.")
        }
    }
}
