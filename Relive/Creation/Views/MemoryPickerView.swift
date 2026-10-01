import ReliveCore
import SwiftUI

/// Choose photos from the story — only memories the user already gave Relive, grouped by moment,
/// newest first. Never asks for more photo-library access.
struct MemoryPickerView: View {
    let title: String
    /// How many photos may be chosen (1...1 replaces a single photo).
    let range: ClosedRange<Int>
    var excluded: Set<AssetID> = []
    let onDone: ([AssetID]) -> Void
    let onCancel: () -> Void

    @Environment(StoryStore.self) private var store
    @State private var selection: [AssetID]
    @State private var showsLimit = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(
        title: String,
        range: ClosedRange<Int>,
        initialSelection: [AssetID] = [],
        excluded: Set<AssetID> = [],
        onDone: @escaping ([AssetID]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.range = range
        self.excluded = excluded
        self.onDone = onDone
        self.onCancel = onCancel
        _selection = State(initialValue: Array(initialSelection.prefix(range.upperBound)))
    }

    private var isSingle: Bool { range.upperBound == 1 }

    var body: some View {
        let library = store.creationLibrary
        let groups = library.visibleMoments.reversed().compactMap { moment -> MomentPhotos? in
            let photos = library.usablePhotos(in: moment).filter { !excluded.contains($0) }
            return photos.isEmpty ? nil : MomentPhotos(moment: moment, photos: photos)
        }

        Group {
            if groups.isEmpty {
                QuietMessageView(
                    title: "No photos to choose from",
                    message: "Add memories to your story and they’ll appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.l) {
                        ForEach(groups) { group in
                            let moment = group.moment
                            VStack(alignment: .leading, spacing: Spacing.xs) {
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
                                .padding(.horizontal, Spacing.screenMargin)
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isHeader)

                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(group.photos, id: \.self) { id in
                                        cell(for: id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, Spacing.m)
                }
            }
        }
        .reliveBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text(statusText)
                .font(Typography.footnote)
                .foregroundStyle(showsLimit ? Palette.textPrimary : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
                .background(.bar)
                .accessibilityIdentifier("pickerStatus")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSingle ? "Use Photo" : "Done") { onDone(selection) }
                    .disabled(!range.contains(selection.count))
                    .accessibilityIdentifier("pickerDone")
            }
        }
    }

    private var statusText: String {
        if showsLimit { return "You can choose up to \(range.upperBound) photos." }
        if isSingle { return "Choose a photo" }
        if selection.isEmpty { return "Choose \(range.lowerBound)–\(range.upperBound) photos" }
        if selection.count < range.lowerBound {
            return "\(selection.count) chosen · choose at least \(range.lowerBound)"
        }
        return "\(selection.count) of up to \(range.upperBound) chosen"
    }

    private func cell(for id: AssetID) -> some View {
        let order = selection.firstIndex(of: id)
        return Button {
            toggle(id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { AssetImageView(assetID: id) }
                .clipped()
                .overlay {
                    if order != nil {
                        Rectangle().strokeBorder(Palette.accent, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let order {
                        Text(isSingle ? "✓" : "\(order + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Palette.accent, in: Circle())
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: id))
        .accessibilityValue(order.map { isSingle ? "Selected" : "Selected, number \($0 + 1)" } ?? "")
        .accessibilityAddTraits(order != nil ? .isSelected : [])
        .accessibilityIdentifier("pickerPhoto")
    }

    private func accessibilityLabel(for id: AssetID) -> String {
        guard let date = store.assets[id]?.creationDate else { return "Photo" }
        return "Photo, \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func toggle(_ id: AssetID) {
        showsLimit = false
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else if isSingle {
            selection = [id]
        } else if selection.count < range.upperBound {
            selection.append(id)
        } else {
            showsLimit = true
        }
    }
}

/// A moment and the photos that can be chosen from it.
private struct MomentPhotos: Identifiable {
    let moment: Moment
    let photos: [AssetID]
    var id: MomentID { moment.id }
}

/// Choose one moment to make something from.
struct MomentPickerView: View {
    let kind: CreationKind
    let onPick: (MomentID) -> Void
    let onCancel: () -> Void

    @Environment(StoryStore.self) private var store

    var body: some View {
        let library = store.creationLibrary
        let moments = Array(library.visibleMoments.reversed())

        Group {
            if moments.isEmpty {
                QuietMessageView(title: "No moments yet", message: "Add memories to your story and Relive will find its moments.")
            } else {
                List(moments) { moment in
                    let count = library.usablePhotos(in: moment).count
                    let enough = count >= kind.photoRange.lowerBound
                    Button {
                        onPick(moment.id)
                    } label: {
                        HStack(spacing: Spacing.m) {
                            Color.clear
                                .frame(width: 60, height: 75)
                                .overlay { AssetImageView(assetID: library.lead(of: moment) ?? store.heroAssetID(for: moment)) }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(moment.title.primary)
                                    .font(Typography.title3)
                                    .foregroundStyle(Palette.textPrimary)
                                if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                                    Text(range)
                                        .font(Typography.footnote)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                Text(enough ? Counted.text(count, "photo", "photos") : "Needs at least \(kind.photoRange.lowerBound) photos")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(enough ? 1 : 0.5)
                    }
                    .disabled(!enough)
                    .listRowBackground(Palette.background)
                    .accessibilityIdentifier("momentPickerRow")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .reliveBackground()
        .navigationTitle("Choose a Moment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
