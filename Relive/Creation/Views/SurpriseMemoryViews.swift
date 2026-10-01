import ReliveCore
import SwiftUI

/// Navigation value for opening today's Surprise Memory.
struct SurpriseRoute: Hashable {
    let momentID: MomentID
    let assetID: AssetID
}

/// A small card on Today, shown only on a real anniversary: "Remember this? · A year ago this week".
/// Deliberately compact so it never competes with Found for You.
struct SurpriseMemoryCard: View {
    let memory: SurpriseMemory
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.m) {
                    Color.clear
                        .frame(width: 64, height: 80)
                        .overlay { AssetImageView(assetID: memory.assetID) }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Remember this?").eyebrowStyle()
                        Text(memory.ageDescription)
                            .font(Typography.title3)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        if let place = memory.place?.name {
                            Text(place)
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Opens the memory")
            .accessibilityIdentifier("surpriseCard")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Not now")
        }
        .padding(.leading, Spacing.s)
        .padding(.vertical, Spacing.s)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private var accessibilityText: String {
        ["Remember this?", memory.ageDescription, memory.place?.name].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The surprise, opened: the photo, when it was, and what to do with it.
struct SurpriseMemoryView: View {
    let route: SurpriseRoute

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store

    var body: some View {
        let library = store.creationLibrary
        let memory = SurpriseMemoryService(library: library).restore(momentID: route.momentID, assetID: route.assetID, now: Date())
        let moment = store.moment(id: route.momentID)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                FramedAssetImage(assetID: route.assetID, aspectRatio: 4 / 5)
                    .accessibilityLabel("Photo")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("A little memory for you").eyebrowStyle()
                    if let memory {
                        Text(memory.ageDescription)
                            .font(Typography.display)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let line = detailLine(moment: moment) {
                        Text(line)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let moment {
                    VStack(spacing: Spacing.s) {
                        NavigationLink(value: MomentRoute(momentID: moment.id, source: "surprise")) {
                            Text("See the Moment")
                        }
                        .buttonStyle(.relivePrimary)
                        .accessibilityIdentifier("surpriseSeeMoment")

                        HStack(spacing: Spacing.s) {
                            Button("Make a Collage") {
                                app.startCreation(.collage, from: .source(collageSource(for: moment, library: library)), origin: "surprise")
                            }
                            .buttonStyle(.reliveOutline)
                            .frame(maxWidth: .infinity)
                            Button("Make a Story") {
                                app.startCreation(.story, from: .source(.moment(moment.id)), origin: "surprise")
                            }
                            .buttonStyle(.reliveOutline)
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    QuietMessageView(title: "This memory isn’t here anymore", message: "Its photos may have been removed or hidden.")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { app.openSurprise() }
    }

    /// "Kaş · August 6, 2025" — the moment's real place and the photo's real date.
    private func detailLine(moment: Moment?) -> String? {
        let date = store.assets[route.assetID]?.creationDate.map(DateText.fullDate)
        let place = moment?.place?.name ?? moment.flatMap { store.chapter(for: $0)?.place?.name }
        let parts = [moment?.title.primary, place, date].compactMap { $0 }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: " · ")
    }

    /// The collage starts from the moment, with this photo leading.
    private func collageSource(for moment: Moment, library: CreationLibrary) -> CreationSource {
        let rest = library.initialPhotos(for: .moment(moment.id), limit: CreationLimits.collagePreselection).filter { $0 != route.assetID }
        let photos = [route.assetID] + rest.prefix(CreationLimits.collagePreselection - 1)
        return photos.count >= CreationLimits.collage.lowerBound ? .photos(photos) : .moment(moment.id)
    }
}

/// "Create from this" on a moment: a collage or a story from its own photos.
struct CreateFromThisSection: View {
    let moment: Moment

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Create from this").eyebrowStyle()
            HStack(spacing: Spacing.s) {
                Button {
                    app.startCreation(.collage, from: .source(.moment(moment.id)), origin: "moment")
                } label: {
                    Label("Collage", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.reliveOutline)
                .accessibilityIdentifier("createFromThisCollage")
                Button {
                    app.startCreation(.story, from: .source(.moment(moment.id)), origin: "moment")
                } label: {
                    Label("Story", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.reliveOutline)
                .accessibilityIdentifier("createFromThisStory")
            }
        }
    }
}
