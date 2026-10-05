import ReliveCore
import SwiftUI

/// "+" in Favorites: browse what is already in Relive — memories, moments, creations — and add
/// several at once. Only Relive's own library is shown (never the whole photo library), and
/// anything already a favorite is marked rather than added twice.
struct AddFavoritesView: View {
    let onDone: () -> Void

    @Environment(StoryStore.self) private var store
    @State private var segment: FavoritesView.Segment = .memories
    @State private var memories: [AssetID] = []
    @State private var moments: Set<MomentID> = []
    @State private var creations: Set<UUID> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        let library = store.creationLibrary
        VStack(spacing: 0) {
            Picker("Add", selection: $segment) {
                ForEach(FavoritesView.Segment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.s)
            .accessibilityIdentifier("addFavoritesSegments")

            switch segment {
            case .memories: memoryGrid(library)
            case .moments: momentList(library)
            case .creations: creationList
            }
        }
        .reliveBackground()
        .navigationTitle("Add Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onDone)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(selectedCount > 0 ? "Add (\(selectedCount))" : "Add", action: add)
                    .disabled(selectedCount == 0)
                    .accessibilityIdentifier("addFavoritesConfirm")
            }
        }
    }

    private var selectedCount: Int { memories.count + moments.count + creations.count }

    private func add() {
        let now = Date()
        for id in memories { store.setFavorite(.memory, id, isFavorite: true, now: now) }
        for id in moments { store.setFavorite(.moment, id.uuidString, isFavorite: true, now: now) }
        for id in creations { store.setFavorite(.creation, id.uuidString, isFavorite: true, now: now) }
        onDone()
    }

    // MARK: - Memories

    @ViewBuilder
    private func memoryGrid(_ library: CreationLibrary) -> some View {
        let groups = library.visibleMoments.reversed().compactMap { moment -> MomentGroup? in
            let shown = moment.featuredAssetIDs.filter { library.isAvailable($0) && store.assets[$0] != nil }
            return shown.isEmpty ? nil : MomentGroup(moment: moment, ids: shown)
        }
        if groups.isEmpty {
            emptyMessage("Add memories to your story and they’ll appear here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            MomentHeading(moment: group.moment)
                                .padding(.horizontal, Spacing.screenMargin)
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(group.ids, id: \.self) { id in
                                    memoryCell(id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, Spacing.s)
            }
        }
    }

    private func memoryCell(_ id: AssetID) -> some View {
        let already = store.isFavorite(.memory, id)
        let selected = memories.contains(id)
        return Button {
            if let index = memories.firstIndex(of: id) {
                memories.remove(at: index)
            } else {
                memories.append(id)
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { AssetImageView(assetID: id) }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if already { FavoriteMark() }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Palette.accent)
                            .padding(4)
                    }
                }
                .opacity(already ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(already)
        .accessibilityLabel(cellLabel(id))
        .accessibilityValue(already ? "Already a favorite" : (selected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("addFavoritePhoto")
    }

    private func cellLabel(_ id: AssetID) -> String {
        let kind = store.assets[id]?.kind == .video ? "Video" : "Photo"
        guard let date = store.assets[id]?.creationDate else { return kind }
        return "\(kind), \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - Moments

    @ViewBuilder
    private func momentList(_ library: CreationLibrary) -> some View {
        let all = Array(library.visibleMoments.reversed())
        if all.isEmpty {
            emptyMessage("Moments appear here once your story has memories.")
        } else {
            List(all) { moment in
                let already = store.isFavorite(.moment, moment.id.uuidString)
                let selected = moments.contains(moment.id)
                Button {
                    if selected { moments.remove(moment.id) } else { moments.insert(moment.id) }
                } label: {
                    HStack(spacing: Spacing.m) {
                        Color.clear
                            .frame(width: 56, height: 70)
                            .overlay { AssetImageView(assetID: library.lead(of: moment) ?? store.heroAssetID(for: moment)) }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                            .accessibilityHidden(true)
                        MomentHeading(moment: moment)
                        Spacer(minLength: 0)
                        selectionMark(already: already, selected: selected)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(already)
                .listRowBackground(Palette.background)
                .accessibilityValue(already ? "Already a favorite" : (selected ? "Selected" : "Not selected"))
                .accessibilityIdentifier("addFavoriteMoment")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Creations

    @ViewBuilder
    private var creationList: some View {
        let items = store.keptItems
        if items.isEmpty {
            emptyMessage("Things you make with Relive will appear here.")
        } else {
            List(items) { item in
                let already = store.isFavorite(.creation, item.favoriteID)
                let selected = creations.contains(item.id)
                let summary = KeptSummary(item: item, store: store)
                Button {
                    if selected { creations.remove(item.id) } else { creations.insert(item.id) }
                } label: {
                    HStack(spacing: Spacing.m) {
                        Palette.surface
                            .frame(width: 56, height: 70)
                            .overlay { CreationPreview(item: KeptPreviewItem(item)).padding(3) }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title)
                                .font(Typography.callout.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Text(summary.detail)
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        selectionMark(already: already, selected: selected)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(already)
                .listRowBackground(Palette.background)
                .accessibilityValue(already ? "Already a favorite" : (selected ? "Selected" : "Not selected"))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Pieces

    private func selectionMark(already: Bool, selected: Bool) -> some View {
        Image(systemName: already ? "heart.fill" : (selected ? "checkmark.circle.fill" : "circle"))
            .font(.title3)
            .foregroundStyle(already || selected ? Palette.accent : Palette.textTertiary)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHidden(true)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(Typography.callout)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A moment and the memories that can be added from it.
private struct MomentGroup: Identifiable {
    let moment: Moment
    let ids: [AssetID]
    var id: MomentID { moment.id }
}

/// A moment's name and real dates, as in the photo pickers.
private struct MomentHeading: View {
    let moment: Moment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(moment.title.primary)
                .font(Typography.title3)
                .foregroundStyle(Palette.textPrimary)
            if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                Text(range)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
