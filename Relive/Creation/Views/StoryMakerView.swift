import ReliveCore
import SwiftUI

/// Story Maker: Relive arranges 3–6 cards from real memories; the user picks a look, previews
/// each card, and saves or shares one or all of them.
struct StoryMakerView: View {
    @Bindable var model: StoryMakerModel
    let onClose: () -> Void
    let onChoosePhotos: () -> Void

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .task(id: model.cards.map(\.assetID)) {
            await model.loadPreviews(using: CreationImageSource(loader: loader))
        }
    }

    private var editor: some View {
        VStack(spacing: Spacing.m) {
            TabView(selection: $model.currentCardID) {
                ForEach(model.cards) { card in
                    ScaledCanvas(designSize: StoryCardCanvas.size) {
                        StoryCardCanvas(
                            card: card,
                            style: model.style,
                            image: card.assetID.flatMap { model.previewImages[$0] },
                            isMissing: card.assetID.map { model.missing.contains($0) } ?? false,
                            number: card.id
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.s)
                    .tag(card.id)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: card))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("storyCards")

            if let index = model.cards.firstIndex(where: { $0.id == model.currentCard?.id }) {
                Text("Card \(index + 1) of \(model.cards.count)")
                    .font(Typography.footnote.monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.l) {
                    ForEach(StoryStyle.allCases, id: \.self) { style in
                        StyleChoice(title: style.displayName, isSelected: model.style == style) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { model.style = style }
                            model.export.clearMessage()
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
            }
            .scrollIndicators(.hidden)

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

    private func accessibilityLabel(for card: StoryCardPlan) -> String {
        let text = StoryCardText(card: card)
        let kind: String
        switch card.kind {
        case .opening: kind = "Opening card"
        case .photo: kind = "Photo card"
        case .memory: kind = "Memory card"
        case .closing: kind = "Closing card"
        }
        return ([kind, text.title, text.subtitle, text.closing].compactMap { $0 }).joined(separator: ", ")
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
