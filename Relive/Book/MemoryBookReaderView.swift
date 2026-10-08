import ReliveCore
import SwiftUI
import UIKit

/// Reading a Memory Book: one page at a time, swiped like a book. Pages are laid out again from
/// the story each time, so deleted photos drop out and the user's edits show at once.
struct MemoryBookReaderView: View {
    let bookID: UUID
    /// Shown as Close when the reader is presented on its own.
    var onClose: (() -> Void)?

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PremiumStore.self) private var premium
    @State private var gate = PremiumGate()
    @State private var pageID: Int? = 0
    @State private var isEditing = false
    @State private var export = ExportController()

    var body: some View {
        Group {
            if let book = store.book(id: bookID) {
                reader(book: book, layout: BookLayoutEngine(library: store.creationLibrary(for: book)).layout(book))
            } else {
                QuietMessageView(title: "This book isn’t here anymore", message: "It may have been deleted.")
                    .frame(maxHeight: .infinity)
            }
        }
        .background(deskColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            if store.book(id: bookID) != nil {
                ToolbarItem(placement: .primaryAction) {
                    FavoriteButton(kind: .creation, identifier: bookID.uuidString, label: "Favorite book", accessibilityID: "bookFavorite")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .accessibilityIdentifier("bookEdit")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            MemoryBookEditorView(bookID: bookID)
        }
        .premiumPaywall(gate)
        .onChange(of: pageID) { _, _ in export.clearMessage() }
        .onChange(of: store.book(id: bookID)?.updatedAt) { _, _ in export.clearMessage() }
    }

    /// The surface the book lies on. The pages keep their paper colour in Dark Mode.
    private var deskColor: Color {
        colorScheme == .dark ? Color(red: 0.09, green: 0.085, blue: 0.08) : Palette.surface
    }

    private func reader(book: MemoryBook, layout: BookLayout) -> some View {
        let current = layout.pages.first { $0.id == pageID } ?? layout.pages.first
        return VStack(spacing: Spacing.s) {
            if !layout.missingAssetIDs.isEmpty {
                AccessBanner(
                    message: layout.missingAssetIDs.count == 1
                        ? "One photo is no longer in your library and was left out."
                        : "\(layout.missingAssetIDs.count) photos are no longer in your library and were left out.",
                    actionTitle: "Edit Book",
                    action: { isEditing = true }
                )
                .padding(.horizontal, Spacing.screenMargin)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(layout.pages) { page in
                        BookPageView(page: page, style: book.style, total: layout.pages.count)
                            .padding(.horizontal, Spacing.l)
                            .padding(.vertical, Spacing.s)
                            .containerRelativeFrame(.horizontal)
                            .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pageID)
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("bookPages")

            Text(pageLabel(current, total: layout.pages.count))
                .font(Typography.footnote.monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
                .accessibilityIdentifier("bookPageLabel")

            // Reading, browsing and editing the whole book are free; keeping it is Premium.
            VStack(spacing: Spacing.xs) {
                ExportStatusView(controller: export)
                HStack(spacing: Spacing.s) {
                    Button {
                        if let current { Task { await share(current, style: book.style, title: layout.facts.title, hero: layout.photoIDs.first) } }
                    } label: {
                        Label("Share Page", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.reliveOutline)
                    .frame(maxWidth: .infinity)
                    .disabled(export.isBusy)
                    .accessibilityIdentifier("bookSharePage")
                    Button("Save Page") {
                        if let current { Task { await save(current, style: book.style, hero: layout.photoIDs.first) } }
                    }
                    .buttonStyle(.reliveOutline)
                    .frame(maxWidth: .infinity)
                    .disabled(export.isBusy || isSaved)
                    .accessibilityIdentifier("bookSavePage")
                }
                Button {
                    Task { await saveFullBook(layout.pages, style: book.style, hero: layout.photoIDs.first) }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("Save Full Book")
                        if !premium.showsPremium {
                            Image(systemName: "sparkles")
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.relivePrimary)
                .disabled(export.isBusy || layout.pages.isEmpty)
                .accessibilityLabel("Save Full Book")
                .accessibilityHint(premium.showsPremium ? "Saves every page to Photos" : "Premium. Saves every page to Photos")
                .accessibilityIdentifier("bookSaveFullBook")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.s)
        }
        .navigationTitle(CreationText.title(layout.facts.title) ?? "Memory Book")
    }

    /// Saved, and nothing has changed since: saving again would make a duplicate.
    private var isSaved: Bool {
        if case .finished = export.phase { return true }
        return false
    }

    private func pageLabel(_ page: BookPage?, total: Int) -> String {
        guard let page else { return "" }
        if page.kind == .cover { return "Cover" }
        return "Page \(page.id + 1) of \(total)"
    }

    private var properties: [String: String] { ["kind": "memory_book_page"] }

    private func save(_ page: BookPage, style: BookStyle, hero: AssetID?) async {
        await gate.export(.memoryBookExport, entry: .memoryBook, premium: premium, heroAssetID: hero) { succeeded in
            let images = CreationImageSource(loader: loader)
            await export.save(store: store, analytics: analytics, properties: properties, onSaved: succeeded) {
                let image = try await MemoryBookExport.render(page, style: style, using: images)
                return [image]
            }
        }
    }

    private func share(_ page: BookPage, style: BookStyle, title: CreationTitle?, hero: AssetID?) async {
        let name = CreationText.title(title) ?? "Memory Book"
        await gate.export(.memoryBookExport, entry: .memoryBook, premium: premium, heroAssetID: hero) { succeeded in
            let images = CreationImageSource(loader: loader)
            await export.share(name: "\(name) – page \(page.id + 1)", analytics: analytics, properties: properties, onShared: succeeded) {
                let image = try await MemoryBookExport.render(page, style: style, using: images)
                return [image]
            }
        }
    }

    /// Every page to Photos, rendered and encoded one at a time.
    private func saveFullBook(_ pages: [BookPage], style: BookStyle, hero: AssetID?) async {
        await gate.export(.memoryBookExport, entry: .memoryBook, premium: premium, heroAssetID: hero) { succeeded in
            let images = CreationImageSource(loader: loader)
            await export.saveEncoded(store: store, analytics: analytics, properties: ["kind": "memory_book"], message: "Saving \(pages.count) pages…", onSaved: succeeded) {
                var jpegs: [Data] = []
                for page in pages {
                    try Task.checkCancellation()
                    let image = try await MemoryBookExport.render(page, style: style, using: images)
                    guard let data = await ExportController.encode([image]).first else { throw CreationExportError.renderFailed }
                    jpegs.append(data)
                }
                return jpegs
            }
        }
    }
}

/// One page in the reader. Loads its photos when it comes on screen and lets them go when it
/// leaves, so a long book never holds every page's images at once.
struct BookPageView: View {
    let page: BookPage
    let style: BookStyle
    let total: Int

    @Environment(\.photoImageLoader) private var loader
    @State private var images: CanvasImages = [:]
    @State private var missing: Set<AssetID> = []

    var body: some View {
        ScaledCanvas(designSize: BookPageCanvas.size) {
            BookPageCanvas(page: page, style: style, images: images, missing: missing)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BookPageText.accessibilityDescription(of: page, total: total))
        .accessibilityAddTraits(.isImage)
        .task(id: page) { await load() }
        .onDisappear {
            images = [:]
        }
    }

    /// Requests each photo at roughly the size it is shown (a page fills a phone's width).
    private func load() async {
        let source = CreationImageSource(loader: loader)
        for slot in page.slots where images[slot.assetID] == nil {
            guard !Task.isCancelled else { return }
            let longest = max(slot.frame.width, slot.frame.height)
            let side = min(1600, max(400, (longest / 200).rounded(.up) * 200))
            if let image = await source.previewImage(for: slot.assetID, longSide: side) {
                images[slot.assetID] = image
            } else if !Task.isCancelled {
                missing.insert(slot.assetID)
            }
        }
    }
}

/// Renders a page for Save and Share, at 2160 × 2700 px.
@MainActor
enum MemoryBookExport {
    static func render(_ page: BookPage, style: BookStyle, using images: CreationImageSource) async throws -> UIImage {
        let loaded = try await images.exportImages(for: page.slots.map { ($0.assetID, $0.frame.size) })
        let canvas = BookPageCanvas(page: page, style: style, images: loaded)
        guard let image = CreationRenderer.render(canvas, size: BookPageCanvas.size) else {
            throw CreationExportError.renderFailed
        }
        return image
    }
}
