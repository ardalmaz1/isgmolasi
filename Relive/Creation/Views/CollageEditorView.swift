import ReliveCore
import SwiftUI

/// Memory Collage: a large live preview and a few deliberate choices — style, shape, the
/// caption lines that are true, and the photos' order. Not a design tool.
struct CollageEditorView: View {
    @Bindable var model: CollageEditorModel
    let onClose: () -> Void

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picker: PickerPurpose?

    private enum PickerPurpose: Identifiable {
        case edit
        case replace(Int)

        var id: String {
            switch self {
            case .edit: "edit"
            case .replace(let index): "replace-\(index)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                preview
                    .padding(.horizontal, Spacing.screenMargin)

                Text(model.selectedIndex == nil ? "Tap two photos to swap them." : "Now tap the photo to swap with.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)

                Button {
                    withAnimation(animation) { model.makeItForMe() }
                } label: {
                    Label("Make it for me", systemImage: "wand.and.stars")
                }
                .buttonStyle(.reliveOutline)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Chooses a style, shape and order for these photos")
                .accessibilityIdentifier("makeItForMe")

                if !model.missingInCollage.isEmpty {
                    AccessBanner(
                        message: model.missingInCollage.count == 1
                            ? "One photo is no longer in your library."
                            : "\(model.missingInCollage.count) photos are no longer in your library.",
                        actionTitle: "Remove Missing",
                        action: removeMissing
                    )
                    .padding(.horizontal, Spacing.screenMargin)
                }

                styleSection
                shapeSection
                if model.hasTitle || model.hasDate || model.hasPlace {
                    detailsSection
                }
                photosSection
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle("Memory Collage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await share() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.canExport)
                .accessibilityIdentifier("collageShare")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.xs) {
                ExportStatusView(controller: model.export)
                Button {
                    Task { await save() }
                } label: {
                    Text("Save to Photos")
                }
                .buttonStyle(.relivePrimary)
                .disabled(!model.canExport)
                .accessibilityIdentifier("collageSave")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xs)
            .background(Palette.background.opacity(0.97), ignoresSafeAreaEdges: .bottom)
        }
        .task(id: model.photoIDs) {
            await model.loadPreviews(using: CreationImageSource(loader: loader))
        }
        .sheet(item: $picker) { purpose in
            NavigationStack {
                switch purpose {
                case .edit:
                    MemoryPickerView(
                        title: "Choose Photos",
                        range: model.range,
                        initialSelection: model.photoIDs,
                        onDone: { ids in
                            model.setPhotos(ids)
                            picker = nil
                        },
                        onCancel: { picker = nil }
                    )
                case .replace(let index):
                    MemoryPickerView(
                        title: "Replace Photo",
                        range: 1...1,
                        excluded: Set(model.photoIDs),
                        onDone: { ids in
                            if let id = ids.first { model.replacePhoto(at: index, with: id) }
                            picker = nil
                        },
                        onCancel: { picker = nil }
                    )
                }
            }
        }
        .onChange(of: model.style) { _, _ in model.export.clearMessage() }
        .onChange(of: model.aspectRatio) { _, _ in model.export.clearMessage() }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    // MARK: - Preview

    private var preview: some View {
        let layout = model.layout
        return ScaledCanvas(designSize: layout.canvas) {
            ZStack(alignment: .topLeading) {
                CollageCanvas(
                    layout: layout,
                    photoIDs: model.photoIDs,
                    images: model.previewImages,
                    missing: model.missing,
                    caption: model.caption,
                    highlightedIndex: model.selectedIndex
                )
                ForEach(Array(layout.slots.enumerated()), id: \.offset) { _, slot in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(animation) { model.tapPhoto(at: slot.photoIndex) }
                        }
                        .placed(at: slot.frame, rotation: slot.rotation)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 520)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collage preview, \(model.style.displayName) style, \(model.aspectRatio.label), \(Counted.text(model.photoIDs.count, "photo", "photos"))")
        .accessibilityIdentifier("collagePreview")
    }

    // MARK: - Choices

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Style").eyebrowStyle()
                .padding(.horizontal, Spacing.screenMargin)
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.l) {
                    ForEach(CollageStyle.allCases, id: \.self) { style in
                        StyleChoice(title: style.displayName, isSelected: model.style == style) {
                            withAnimation(animation) { model.style = style }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Shape").eyebrowStyle()
            Picker("Shape", selection: $model.aspectRatio.animation(animation)) {
                ForEach(CreationAspectRatio.allCases, id: \.self) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, Spacing.screenMargin)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Details").eyebrowStyle()
            if let title = model.titleText {
                Toggle(isOn: $model.showsTitle.animation(animation)) {
                    LabeledText(label: "Title", value: title)
                }
            }
            if let date = model.dateText {
                Toggle(isOn: $model.showsDate.animation(animation)) {
                    LabeledText(label: "Date", value: date)
                }
            }
            if let place = model.placeText {
                Toggle(isOn: $model.showsPlace.animation(animation)) {
                    LabeledText(label: "Place", value: place)
                }
            }
        }
        .tint(Palette.accent)
        .padding(.horizontal, Spacing.screenMargin)
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Photos").eyebrowStyle()
                Spacer()
                Button("Edit Photos") { picker = .edit }
                    .font(Typography.callout.weight(.semibold))
                    .accessibilityIdentifier("collageEditPhotos")
            }
            .padding(.horizontal, Spacing.screenMargin)

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(model.photoIDs.enumerated()), id: \.element) { index, id in
                        thumbnail(id: id, index: index)
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
            }
            .scrollIndicators(.hidden)

            Text("Touch and hold a photo to replace, move or remove it.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, Spacing.screenMargin)
        }
    }

    private func thumbnail(id: AssetID, index: Int) -> some View {
        let isSelected = model.selectedIndex == index
        return Button {
            withAnimation(animation) { model.tapPhoto(at: index) }
        } label: {
            Color.clear
                .frame(width: 64, height: 80)
                .overlay { AssetImageView(assetID: id) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.photo, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    if model.missing.contains(id) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.white, .orange)
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { picker = .replace(index) } label: { Label("Replace", systemImage: "photo.on.rectangle") }
            if index > 0 {
                Button { withAnimation(animation) { model.move(from: index, by: -1) } } label: { Label("Move Earlier", systemImage: "arrow.left") }
            }
            if index < model.photoIDs.count - 1 {
                Button { withAnimation(animation) { model.move(from: index, by: 1) } } label: { Label("Move Later", systemImage: "arrow.right") }
            }
            if model.photoIDs.count > model.range.lowerBound {
                Button(role: .destructive) { withAnimation(animation) { model.removePhoto(at: index) } } label: { Label("Remove", systemImage: "minus.circle") }
            }
        }
        .accessibilityLabel("Photo \(index + 1) of \(model.photoIDs.count)")
        .accessibilityValue(isSelected ? "Picked up for swapping" : "")
        .accessibilityHint("Double-tap to swap with another photo")
        .accessibilityActions {
            Button("Replace") { picker = .replace(index) }
            if index > 0 { Button("Move Earlier") { model.move(from: index, by: -1) } }
            if index < model.photoIDs.count - 1 { Button("Move Later") { model.move(from: index, by: 1) } }
            if model.photoIDs.count > model.range.lowerBound { Button("Remove") { model.removePhoto(at: index) } }
        }
    }

    // MARK: - Actions

    private func removeMissing() {
        let keep = model.photoIDs.filter { !model.missing.contains($0) }
        if keep.count >= model.range.lowerBound {
            withAnimation(animation) { model.setPhotos(keep) }
        } else {
            picker = .edit
        }
    }

    private func save() async {
        let images = CreationImageSource(loader: loader)
        await model.export.save(store: store, analytics: analytics, properties: model.analyticsProperties) {
            let image = try await model.renderExport(using: images)
            return [image]
        }
    }

    private func share() async {
        let images = CreationImageSource(loader: loader)
        await model.export.share(name: "Relive Collage", analytics: analytics, properties: model.analyticsProperties) {
            let image = try await model.renderExport(using: images)
            return [image]
        }
    }
}

/// One of a few curated choices, shown as words rather than a toolbar of icons.
struct StyleChoice: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(isSelected ? Typography.title3.weight(.semibold) : Typography.title3)
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                Capsule()
                    .fill(isSelected ? Palette.textPrimary : Color.clear)
                    .frame(width: 18, height: 2)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Title  Kaş" inside a toggle row.
struct LabeledText: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(Palette.textPrimary)
            Text(value)
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
    }
}
