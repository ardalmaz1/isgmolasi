import ReliveCore
import SwiftUI

/// Light editing of a saved book: its look, its cover, which photos and in what order, and the
/// user's own words. Every change is saved at once; the pages reflow from the story.
struct MemoryBookEditorView: View {
    let bookID: UUID

    @Environment(StoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picker: PickerPurpose?
    @State private var isEditingNote = false
    @State private var confirmsDelete = false
    @State private var limitMessage: String?
    @State private var isPickingFromLibrary = false

    private enum PickerPurpose: Identifiable {
        case cover
        case photos
        case replace(AssetID)

        var id: String {
            switch self {
            case .cover: "cover"
            case .photos: "photos"
            case .replace(let id): "replace-\(id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let book = store.book(id: bookID) {
                    form(book)
                } else {
                    QuietMessageView(title: "This book isn’t here anymore", message: "It may have been deleted.")
                }
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("bookEditDone")
                }
            }
        }
        .sheet(item: $picker) { purpose in
            pickerSheet(purpose)
        }
        .photoLibraryPicker(isPresented: $isPickingFromLibrary, maximum: max(1, BookLimits.maximumPhotos - (store.book(id: bookID)?.photoIDs.count ?? 0))) { identifiers in
            Task { await addFromPhotoLibrary(identifiers) }
        }
        .sheet(isPresented: $isEditingNote) {
            NoteEditorView(
                initialText: store.book(id: bookID)?.note ?? "",
                prompt: "A few words for the first page",
                privacyLine: "Printed after the cover. It stays on this iPhone unless you share a page."
            ) { text in
                update { $0.setNote(text) }
            }
        }
    }

    // MARK: - Form

    private func form(_ book: MemoryBook) -> some View {
        let library = store.creationLibrary(for: book)
        let layout = BookLayoutEngine(library: library).layout(book)
        return List {
            Section("Style") {
                HStack(spacing: Spacing.l) {
                    ForEach(BookStyle.allCases, id: \.self) { style in
                        StyleChoice(title: style.displayName, isSelected: book.style == style) {
                            update { $0.style = style }
                        }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }

            Section("Cover") {
                HStack(spacing: Spacing.m) {
                    Color.clear
                        .frame(width: 60, height: 75)
                        .overlay { AssetImageView(assetID: layout.pages.first?.slots.first?.assetID) }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                        .accessibilityHidden(true)
                    // Borderless: a List row with several default buttons fires all of them on a tap.
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Button("Change Cover") { picker = .cover }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("bookChangeCover")
                        if book.coverAssetID != nil {
                            Button("Use the Best Photo") { updateIfAllowed { $0.setCover(nil) } }
                                .buttonStyle(.borderless)
                                .font(Typography.footnote)
                        }
                    }
                }
            }

            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(Array(book.photoIDs.enumerated()), id: \.element) { index, id in
                            thumbnail(id: id, index: index, book: book, missing: layout.missingAssetIDs.contains(id))
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .scrollIndicators(.hidden)
                Button("Add or Remove Photos") { picker = .photos }
                    .accessibilityIdentifier("bookEditPhotos")
                if book.photoIDs.count < BookLimits.maximumPhotos {
                    Button("Add from Photo Library") { isPickingFromLibrary = true }
                        .accessibilityIdentifier("bookAddFromLibrary")
                }
                if let limitMessage {
                    Text(limitMessage)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            } header: {
                Text("Photos · \(book.photoIDs.count)")
            } footer: {
                Text("Touch and hold a photo to replace, move or remove it.")
            }

            Section {
                Button(book.trimmedNote == nil ? "Add a Note" : "Edit Note") { isEditingNote = true }
                    .accessibilityIdentifier("bookEditNote")
                Toggle("Include notes from moments", isOn: Binding(
                    get: { book.includesMomentNotes },
                    set: { value in update { $0.includesMomentNotes = value } }
                ))
                .tint(Palette.accent)
            } header: {
                Text("Your words")
            } footer: {
                Text("Relive never writes words for you. Only notes you wrote appear in the book.")
            }

            Section {
                Button("Update from \(sourceName(book.source))") {
                    let refreshed = MemoryBookBuilder(library: library).refreshed(book, now: Date())
                    store.saveBook(refreshed)
                }
            } footer: {
                Text("Adds photos that have joined since and leaves out deleted ones. Your style, cover and note stay.")
            }

            Section {
                Button("Delete Book", role: .destructive) { confirmsDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .reliveBackground()
        .confirmationDialog("Delete this book?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Book", role: .destructive) {
                store.deleteBook(id: bookID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your photos and moments are not affected.")
        }
    }

    private func thumbnail(id: AssetID, index: Int, book: MemoryBook, missing: Bool) -> some View {
        Color.clear
            .frame(width: 56, height: 70)
            .overlay { AssetImageView(assetID: id) }
            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if missing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white, .orange)
                        .padding(3)
                }
            }
            .contextMenu {
                Button { picker = .replace(id) } label: { Label("Replace", systemImage: "photo.on.rectangle") }
                Button { updateIfAllowed { $0.setCover(id) } } label: { Label("Use as Cover", systemImage: "book.closed") }
                if index > 0 {
                    Button { updateIfAllowed { $0.movePhoto(id, by: -1) } } label: { Label("Move Earlier", systemImage: "arrow.left") }
                }
                if index < book.photoIDs.count - 1 {
                    Button { updateIfAllowed { $0.movePhoto(id, by: 1) } } label: { Label("Move Later", systemImage: "arrow.right") }
                }
                Button(role: .destructive) { remove(id) } label: { Label("Remove", systemImage: "minus.circle") }
            }
            .accessibilityElement()
            .accessibilityLabel("Photo \(index + 1) of \(book.photoIDs.count)\(missing ? ", no longer in your library" : "")")
            .accessibilityActions {
                Button("Replace") { picker = .replace(id) }
                Button("Use as Cover") { updateIfAllowed { $0.setCover(id) } }
                if index > 0 { Button("Move Earlier") { updateIfAllowed { $0.movePhoto(id, by: -1) } } }
                if index < book.photoIDs.count - 1 { Button("Move Later") { updateIfAllowed { $0.movePhoto(id, by: 1) } } }
                Button("Remove") { remove(id) }
            }
    }

    @ViewBuilder
    private func pickerSheet(_ purpose: PickerPurpose) -> some View {
        let book = store.book(id: bookID)
        NavigationStack {
            switch purpose {
            case .cover:
                MemoryPickerView(
                    title: "Choose a Cover",
                    range: 1...1,
                    limitedTo: Set(book?.photoIDs ?? []),
                    onDone: { ids in
                        if let id = ids.first { updateIfAllowed { $0.setCover(id) } }
                        picker = nil
                    },
                    onCancel: { picker = nil }
                )
            case .photos:
                MemoryPickerView(
                    title: "Photos in This Book",
                    range: BookLimits.minimumPhotos...BookLimits.maximumPhotos,
                    initialSelection: book?.photoIDs ?? [],
                    onDone: { ids in
                        updateIfAllowed { $0.setPhotos(ids) }
                        picker = nil
                    },
                    onCancel: { picker = nil }
                )
            case .replace(let oldID):
                MemoryPickerView(
                    title: "Replace Photo",
                    range: 1...1,
                    excluded: Set(book?.photoIDs ?? []),
                    onDone: { ids in
                        if let id = ids.first { updateIfAllowed { $0.replacePhoto(oldID, with: id) } }
                        picker = nil
                    },
                    onCancel: { picker = nil }
                )
            }
        }
    }

    // MARK: - Changes

    /// Applies a change that may be refused (e.g. a cover that isn't in the book) and saves it.
    private func updateIfAllowed(_ change: (inout MemoryBook) -> Bool) {
        guard var book = store.book(id: bookID) else { return }
        guard change(&book) else { return }
        limitMessage = nil
        store.saveBook(book)
    }

    private func update(_ change: (inout MemoryBook) -> Void) {
        updateIfAllowed { book in
            change(&book)
            return true
        }
    }

    /// Photos picked from the photo library join the end of the book with their own metadata.
    private func addFromPhotoLibrary(_ identifiers: [AssetID]) async {
        let picks = await store.resolvePhotoLibraryPicks(identifiers)
        guard !picks.ids.isEmpty, var book = store.book(id: bookID) else { return }
        guard book.setPhotos(book.photoIDs + picks.ids.filter { !book.photoIDs.contains($0) }) else { return }
        book.rememberPhotoLibraryAssets(picks.libraryAssets)
        limitMessage = nil
        store.saveBook(book)
    }

    private func remove(_ id: AssetID) {
        guard var book = store.book(id: bookID) else { return }
        if book.removePhoto(id) {
            limitMessage = nil
            store.saveBook(book)
        } else {
            limitMessage = "A book keeps at least \(BookLimits.minimumPhotos) photos."
        }
    }

    private func sourceName(_ source: CreationSource) -> String {
        switch source {
        case .moment: "the Moment"
        case .trip: "the Trip"
        case .month(let month): CreationText.monthTitle(month)
        case .year(let year): String(year)
        case .photos: "Your Photos"
        case .favorites: "Favorites"
        }
    }
}
