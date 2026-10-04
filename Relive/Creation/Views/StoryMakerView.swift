import ReliveCore
import SwiftUI

/// Story Maker: Relive designs a 3–7 card story from real memories. The user can ask for
/// another design, pick a look, make small corrections to a card, and save or share the cards.
struct StoryMakerView: View {
    @Bindable var model: StoryMakerModel
    let onClose: () -> Void
    let onChoosePhotos: () -> Void

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replacing: Replacement?
    @State private var libraryReplacement: Replacement?

    private struct Replacement: Identifiable, Equatable {
        let cardID: Int
        let slot: Int
        var id: String { "\(cardID)-\(slot)" }
    }

    var body: some View {
        Group {
            if let shortfall = model.shortfall {
                shortfallView(shortfall)
            } else {
                editor
            }
        }
        .reliveBackground()
        .navigationTitle("Story Maker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
            if model.shortfall == nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Share This Card") { Task { await share(all: false) } }
                        Button("Share All Cards") { Task { await share(all: true) } }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!model.canExport)
                    .accessibilityIdentifier("storyShare")
                }
            }
        }
        .task(id: model.design?.photoIDs) {
            await model.loadPreviews(using: CreationImageSource(loader: loader))
        }
        .sheet(item: $replacing) { replacement in
            NavigationStack {
                MemoryPickerView(
                    title: "Replace Photo",
                    range: 1...1,
                    excluded: Set(model.design?.photoIDs ?? []),
                    onDone: { ids in
                        if let id = ids.first { model.replacePhoto(cardID: replacement.cardID, slot: replacement.slot, with: id) }
                        replacing = nil
                    },
                    onCancel: { replacing = nil }
                )
            }
        }
        .photoLibraryPicker(isPresented: libraryPickerPresented, maximum: 1) { identifiers in
            guard let replacement = libraryReplacement else { return }
            libraryReplacement = nil
            Task {
                let picks = await store.resolvePhotoLibraryPicks(identifiers)
                if let id = picks.ids.first {
                    model.replacePhoto(cardID: replacement.cardID, slot: replacement.slot, with: id, photoLibraryAssets: picks.libraryAssets)
                }
            }
        }
    }

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.3) }

    private var editor: some View {
        VStack(spacing: Spacing.s) {
            TabView(selection: $model.currentCardID) {
                ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                    ScaledCanvas(designSize: StoryCardCanvas.size) {
                        StoryCardCanvas(
                            card: card,
                            style: model.style,
                            images: model.previewImages,
                            missing: model.missing,
                            aspects: model.aspects(for: card),
                            number: index + 1
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.s)
                    .tag(card.id)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(StoryCardText.accessibilityDescription(of: card, number: index + 1, total: model.cards.count))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("storyCards")

            if let card = model.currentCard, let index = model.cards.firstIndex(where: { $0.id == card.id }) {
                HStack(spacing: Spacing.m) {
                    Text("Card \(index + 1) of \(model.cards.count)")
                        .font(Typography.footnote.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    cardMenu(card)
                }
                .padding(.horizontal, Spacing.screenMargin)
            }

            Button {
                withAnimation(animation) { model.makeItForMe() }
            } label: {
                Label("Make it for me", systemImage: "wand.and.stars")
            }
            .buttonStyle(.reliveOutline)
            .accessibilityHint("Designs the story again: a style, an order and layouts for these photos")
            .accessibilityIdentifier("storyMakeItForMe")

            FlowLayout {
                ForEach(StoryStyle.allCases, id: \.self) { style in
                    StyleChoice(title: style.displayName, isSelected: model.style == style) {
                        withAnimation(animation) { model.setStyle(style) }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("storyStyles")

            VStack(spacing: Spacing.xs) {
                ExportStatusView(controller: model.export)
                HStack(spacing: Spacing.s) {
                    Button("Save This Card") { Task { await save(all: false) } }
                        .buttonStyle(.reliveOutline)
                        .accessibilityIdentifier("storySaveOne")
                    Button("Save All \(model.cards.count)") { Task { await save(all: true) } }
                        .buttonStyle(.relivePrimary)
                        .accessibilityIdentifier("storySaveAll")
                }
                .disabled(!model.canExport)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.s)
        }
    }

    /// Small corrections to the card on screen. Relive designed it; these only adjust it.
    private func cardMenu(_ card: StoryCard) -> some View {
        Menu {
            if StoryDesigner.alternatives(for: card).count > 1 {
                Button { withAnimation(animation) { model.changeLayout(of: card.id) } } label: {
                    Label("Change Layout", systemImage: "rectangle.3.group")
                }
            }
            ForEach(Array(card.photos.indices), id: \.self) { slot in
                let name = card.photos.count == 1 ? "Photo" : "Photo \(slot + 1)"
                Menu {
                    Button { replacing = Replacement(cardID: card.id, slot: slot) } label: { Label("From Relive", systemImage: "book.closed") }
                    Button { libraryReplacement = Replacement(cardID: card.id, slot: slot) } label: { Label("From Photo Library", systemImage: "photo.on.rectangle") }
                } label: {
                    Label("Replace \(name)", systemImage: "photo.on.rectangle.angled")
                }
            }
            if card.hasDate {
                Button { model.toggleDate(of: card.id) } label: {
                    Label(card.showsDate ? "Hide Date" : "Show Date", systemImage: "calendar")
                }
            }
            if card.hasPlace {
                Button { model.togglePlace(of: card.id) } label: {
                    Label(card.showsPlace ? "Hide Place" : "Show Place", systemImage: "mappin")
                }
            }
            if card.hasCoordinates {
                Button { model.toggleCoordinates(of: card.id) } label: {
                    Label(card.showsCoordinates ? "Hide Coordinates" : "Show Coordinates", systemImage: "location")
                }
            }
            if card.role != .opening, model.cards.count > 2 {
                Button(role: .destructive) { withAnimation(animation) { model.removeCard(card.id) } } label: {
                    Label("Remove Card", systemImage: "trash")
                }
            }
        } label: {
            Label("Edit Card", systemImage: "slider.horizontal.3")
                .font(Typography.callout.weight(.semibold))
        }
        .accessibilityIdentifier("storyEditCard")
    }

    private var libraryPickerPresented: Binding<Bool> {
        Binding(get: { libraryReplacement != nil }, set: { if !$0 { libraryReplacement = nil } })
    }

    private func shortfallView(_ shortfall: CreationShortfall) -> some View {
        let message: String
        switch shortfall {
        case .notEnoughPhotos(let available, let required):
            message = available == 0
                ? "A story needs at least \(required) photos, and there are none here that can be used."
                : "A story needs at least \(required) photos, and there \(available == 1 ? "is only 1" : "are only \(available)") here."
        }
        return QuietMessageView(
            title: "Not enough photos for a story",
            message: message,
            actionTitle: "Choose Photos",
            action: onChoosePhotos
        )
        .frame(maxHeight: .infinity)
    }

    private func targetIDs(all: Bool) -> [Int] {
        all ? model.cards.map(\.id) : [model.currentCard?.id].compactMap { $0 }
    }

    private func save(all: Bool) async {
        let ids = targetIDs(all: all)
        let images = CreationImageSource(loader: loader)
        await model.export.save(store: store, analytics: analytics, properties: model.analyticsProperties) {
            try await model.renderExport(cardIDs: ids, using: images)
        }
    }

    private func share(all: Bool) async {
        let ids = targetIDs(all: all)
        let images = CreationImageSource(loader: loader)
        await model.export.share(name: "Relive Story", analytics: analytics, properties: model.analyticsProperties) {
            try await model.renderExport(cardIDs: ids, using: images)
        }
    }
}
