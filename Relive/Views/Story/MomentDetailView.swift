import ReliveCore
import SwiftUI

/// One moment: cover, facts, the user's own words, and every photo.
struct MomentDetailView: View {
    let momentID: MomentID
    let source: String

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsSimilar = false
    @State private var isEditingNote = false
    @State private var isSharing = false
    @State private var viewerSelection: ViewerSelection?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        Group {
            if let moment = store.moment(id: momentID), store.isVisible(moment) {
                content(for: moment)
            } else {
                QuietMessageView(
                    title: "This memory isn’t here anymore",
                    message: "Its photos may have been removed or hidden."
                )
                .frame(maxHeight: .infinity)
                .reliveBackground()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { app.recordMomentOpened(momentID, source: source) }
    }

    private func content(for moment: Moment) -> some View {
        let assets = store.displayAssets(for: moment, includeSimilar: showsSimilar)
        let similarCount = store.similarCount(for: moment)
        let hero = store.heroAssetID(for: moment)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if let hero { viewerSelection = ViewerSelection(assetID: hero) }
                } label: {
                    FramedAssetImage(assetID: hero, aspectRatio: 4 / 5, cornerRadius: 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cover photo. Opens full screen.")

                MomentFacts(moment: moment, chapter: store.chapter(for: moment))
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.l)

                NoteSection(note: store.userState(for: moment.id).note) {
                    isEditingNote = true
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.l)

                CreateFromThisSection(moment: moment)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.l)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets) { asset in
                        Button {
                            viewerSelection = ViewerSelection(assetID: asset.id)
                        } label: {
                            PhotoGridCell(asset: asset, isFavorite: store.isFavorite(.memory, asset.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("momentPhoto")
                        .contextMenu {
                            let isFavorite = store.isFavorite(.memory, asset.id)
                            Button {
                                store.toggleFavorite(.memory, asset.id)
                            } label: {
                                Label(isFavorite ? "Remove from Favorites" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
                            }
                            if asset.kind == .photo {
                                Button {
                                    store.setCover(asset.id, for: moment.id)
                                } label: {
                                    Label("Use as Cover", systemImage: "photo.on.rectangle")
                                }
                            }
                        }
                    }
                }

                if similarCount > 0 {
                    Button(showsSimilar ? "Hide similar photos" : "Show \(Counted.text(similarCount, "similar photo", "similar photos"))") {
                        withAnimation(.easeInOut(duration: 0.25)) { showsSimilar.toggle() }
                    }
                    .buttonStyle(.reliveQuiet)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.s)
                }
            }
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The moment itself; its photos keep their own favorites.
                FavoriteButton(kind: .moment, identifier: moment.id.uuidString, label: "Favorite moment", accessibilityID: "momentFavorite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isSharing = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isEditingNote = true
                    } label: {
                        Label(store.userState(for: moment.id).hasNote ? "Edit Note" : "Add a Note", systemImage: "pencil")
                    }
                    if store.userState(for: moment.id).heroOverrideAssetID != nil {
                        Button {
                            store.setCover(nil, for: moment.id)
                        } label: {
                            Label("Use Suggested Cover", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.hideMoment(moment.id)
                        dismiss()
                    } label: {
                        Label("Hide This Memory", systemImage: "eye.slash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditingNote) {
            NoteEditorView(initialText: store.userState(for: moment.id).note ?? "") { text in
                store.setNote(text, for: moment.id)
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareMomentView(moment: moment)
        }
        .fullScreenCover(item: $viewerSelection) { selection in
            AssetViewer(assets: store.displayAssets(for: moment, includeSimilar: true), startAssetID: selection.assetID)
        }
    }
}

/// Identifies which photo the full-screen viewer should open on.
struct ViewerSelection: Identifiable {
    let assetID: AssetID
    var id: AssetID { assetID }
}

/// Title, dates, place, counts. Facts only.
private struct MomentFacts: View {
    let moment: Moment
    let chapter: Chapter?

    @Environment(StoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                Text(range)
                    .eyebrowStyle()
            }
            Text(moment.title.primary)
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let placeText {
                Label(placeText, systemImage: "mappin")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(countText)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var placeText: String? {
        guard let place = moment.place ?? chapter?.place else { return nil }
        if let region = place.region, region != place.name {
            return "\(place.name), \(region)"
        }
        return place.name
    }

    private var countText: String {
        let available = moment.assetIDs.filter { store.isAvailable($0) && !moment.duplicateAssetIDs.contains($0) }
        let videos = available.filter { store.assets[$0]?.kind == .video }.count
        var text = Counted.text(available.count, "memory", "memories")
        if videos > 0 {
            text += " · \(Counted.text(videos, "video", "videos"))"
        }
        if let chapter, chapter.title.primary != moment.title.primary {
            text += " · Part of \(chapter.title.primary)"
        }
        return text
    }
}

/// The user's own words. Relive never writes here.
private struct NoteSection: View {
    let note: String?
    let onEdit: () -> Void

    var body: some View {
        if let note, !note.isEmpty {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your note")
                        .eyebrowStyle()
                    Text(note)
                        .font(Typography.bodySerif)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.m)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your note")
        } else {
            Button(action: onEdit) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "pencil.line")
                        .accessibilityHidden(true)
                    Text("What do you remember about this?")
                        .font(Typography.bodySerif.italic())
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(Spacing.m)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
