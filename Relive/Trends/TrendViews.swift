import Observation
import ReliveCore
import SwiftUI
import UIKit

// MARK: - Studio model

/// One trend being made from chosen photos: preview images processed by the recipe, the chosen
/// variation, and export.
@Observable
@MainActor
final class TrendStudioModel {
    static let previewLongSide: Double = 1400

    let trend: TrendDefinition
    let recipe: any TrendRecipe
    let photoIDs: [AssetID]
    let facts: CreationFacts
    let coupleNames: String?
    private(set) var variation = 0
    private(set) var processed: [AssetID: UIImage] = [:]
    private(set) var missing: Set<AssetID> = []
    private(set) var isProcessing = false
    let export = ExportController()

    @ObservationIgnored private var originals: [AssetID: UIImage] = [:]

    init(trend: TrendDefinition, recipe: any TrendRecipe, photoIDs: [AssetID], library: CreationLibrary, coupleNames: String?) {
        self.trend = trend
        self.recipe = recipe
        self.photoIDs = photoIDs
        self.facts = library.facts(forPhotos: photoIDs)
        self.coupleNames = coupleNames
    }

    func photos(dates: [AssetID: Date]) -> [TrendPhoto] {
        photoIDs.map { TrendPhoto(assetID: $0, image: processed[$0], date: dates[$0]) }
    }

    var context: TrendRenderContext {
        TrendRenderContext(facts: facts, coupleNames: coupleNames, variation: variation)
    }

    var canExport: Bool {
        missing.isEmpty && !export.isBusy && processed.count == photoIDs.count
    }

    /// Saved, and nothing has changed since.
    var isSaved: Bool {
        if case .finished = export.phase { return true }
        return false
    }

    var analyticsProperties: [String: String] {
        ["kind": "trend", "trend": trend.id, "recipe": trend.recipe.description, "variation": String(variation)]
    }

    func load(using images: CreationImageSource, longSide: Double = TrendStudioModel.previewLongSide) async {
        for id in photoIDs where originals[id] == nil && !missing.contains(id) {
            if let image = await images.previewImage(for: id, longSide: longSide) {
                originals[id] = image
            } else {
                missing.insert(id)
            }
        }
        await reprocess()
    }

    func choose(variation: Int) async {
        guard variation != self.variation, recipe.variations.indices.contains(variation) else { return }
        self.variation = variation
        export.clearMessage()
        await reprocess()
    }

    private func reprocess() async {
        isProcessing = true
        defer { isProcessing = false }
        let current = variation
        var result: [AssetID: UIImage] = [:]
        for id in photoIDs {
            guard let original = originals[id] else { continue }
            result[id] = await recipe.process(original, variation: current)
        }
        guard current == variation else { return }
        processed = result
    }

    /// The final image at export size, made from export-size photos.
    func renderExport(using images: CreationImageSource, dates: [AssetID: Date]) async throws -> UIImage {
        let frames = recipe.photoFrames(count: photoIDs.count)
        let requests = zip(photoIDs, frames).map { (id: $0.0, frame: $0.1) }
        let loaded = try await images.exportImages(for: requests)
        var photos: [TrendPhoto] = []
        for id in photoIDs {
            let image: UIImage?
            if let original = loaded[id] {
                image = await recipe.process(original, variation: variation)
            } else {
                image = nil
            }
            photos.append(TrendPhoto(assetID: id, image: image, date: dates[id]))
        }
        guard let rendered = CreationRenderer.render(recipe.canvas(photos: photos, context: context), size: recipe.designSize) else {
            throw CreationExportError.renderFailed
        }
        return rendered
    }
}

// MARK: - Samples and previews

@MainActor
enum TrendSamples {
    /// The user's own photos to preview a trend with: the best photos of the most recent moment
    /// that has enough of them. Deterministic.
    static func photos(for trend: TrendDefinition, library: CreationLibrary) -> [AssetID] {
        let needed = trend.photos.minimum
        for moment in library.visibleMoments.reversed() where moment.kind != .undated {
            let usable = library.usablePhotos(in: moment)
            if usable.count >= needed {
                return library.spreadPick(usable, count: needed, include: library.lead(of: moment))
            }
        }
        return []
    }

    static func coupleNames(_ relationship: RelationshipProfile?) -> String? {
        guard let relationship,
              let user = relationship.userName?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty else { return nil }
        let partner = relationship.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return partner.isEmpty ? nil : "\(user) & \(partner)"
    }
}

/// A trend shown with the user's own photos, processed by its recipe. Never a stock image.
struct TrendPreview: View {
    let trend: TrendDefinition
    var longSide: Double = 800

    @Environment(StoryStore.self) private var store
    @Environment(AppModel.self) private var app
    @Environment(\.photoImageLoader) private var loader
    @State private var model: TrendStudioModel?

    var body: some View {
        Group {
            if let recipe = TrendRecipeRegistry.recipe(for: trend.recipe), trend.execution != .ai {
                ScaledCanvas(designSize: recipe.designSize) {
                    if let model {
                        recipe.canvas(photos: model.photos(dates: dates(model.photoIDs)), context: model.context)
                    } else {
                        Palette.placeholder
                    }
                }
            } else {
                AITrendTile()
            }
        }
        .task(id: trend) {
            guard let recipe = TrendRecipeRegistry.recipe(for: trend.recipe), trend.execution != .ai else { return }
            let photos = TrendSamples.photos(for: trend, library: store.creationLibrary)
            guard !photos.isEmpty else { return }
            let model = TrendStudioModel(
                trend: trend, recipe: recipe, photoIDs: photos,
                library: store.creationLibrary, coupleNames: TrendSamples.coupleNames(app.relationship)
            )
            await model.load(using: CreationImageSource(loader: loader), longSide: longSide)
            self.model = model
        }
    }

    private func dates(_ ids: [AssetID]) -> [AssetID: Date] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in store.assets[id]?.creationDate.map { (id, $0) } })
    }
}

/// An AI trend can't be previewed honestly without generating it, so it gets a quiet tile.
struct AITrendTile: View {
    var body: some View {
        ZStack {
            Palette.surface
            VStack(spacing: Spacing.s) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34, weight: .light))
                Text("Made with AI")
                    .font(Typography.footnote.weight(.semibold))
                Text("Coming soon")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .foregroundStyle(Palette.textPrimary)
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card

/// A Trending Now card: the trend shown with the user's photos, its name and one line.
struct TrendCard: View {
    let trend: TrendDefinition
    let availability: TrendAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TrendPreview(trend: trend, longSide: 700)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
            if let label = TrendCard.label(trend: trend, availability: availability) {
                Text(label).eyebrowStyle()
            }
            Text(trend.name)
                .font(Typography.title3)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(trend.summary)
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 224, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([trend.name, TrendCard.label(trend: trend, availability: availability), trend.summary].compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint("Opens the trend")
        .accessibilityAddTraits(.isButton)
    }

    /// One quiet word at most.
    static func label(trend: TrendDefinition, availability: TrendAvailability) -> String? {
        if availability == .comingSoon { return "Coming soon" }
        switch trend.badge {
        case .new?: return "New"
        case .trending?: return "Trending"
        case nil: return nil
        }
    }
}

// MARK: - Detail

struct TrendDetailView: View {
    let trendID: String

    @Environment(TrendCatalogStore.self) private var trends
    @Environment(\.analytics) private var analytics
    @State private var isCreating = false

    var body: some View {
        Group {
            if let trend = trends.trend(id: trendID) {
                content(trend, availability: TrendCatalogFilter.availability(of: trend, in: trends.context()))
            } else {
                QuietMessageView(title: "This trend isn’t available", message: "Trends come and go. Have a look at the others in Create.")
                    .frame(maxHeight: .infinity)
            }
        }
        .reliveBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { analytics.track(.trendOpened, ["trend": trendID]) }
    }

    private func content(_ trend: TrendDefinition, availability: TrendAvailability) -> some View {
        let action = TrendFlowPolicy.primaryAction(for: trend, availability: availability)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                TrendPreview(trend: trend, longSide: 1200)
                    .frame(maxWidth: .infinity, maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .accessibilityLabel("Preview of \(trend.name) with your photos")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let label = TrendCard.label(trend: trend, availability: availability) {
                        Text(label).eyebrowStyle()
                    }
                    Text(trend.name)
                        .font(Typography.display)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(trend.detail ?? trend.summary)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("You’ll need").eyebrowStyle()
                    Text(photoNeed(trend))
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                    if !trend.guidance.isEmpty {
                        Text("Best results").eyebrowStyle().padding(.top, Spacing.xs)
                        ForEach(trend.guidance, id: \.self) { tip in
                            Text(tip)
                                .font(Typography.body)
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                }

                if TrendFlowPolicy.needsDisclosure(trend) {
                    AICreationDisclosure()
                } else {
                    Label(TrendFlowPolicy.privacyLine(for: trend), systemImage: "lock")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }

                switch action {
                case .choosePhotos:
                    Button("Choose Photos") { isCreating = true }
                        .buttonStyle(.relivePrimary)
                        .accessibilityIdentifier("trendChoosePhotos")
                case .unavailable(let reason):
                    Button(reason) {}
                        .buttonStyle(.relivePrimary)
                        .disabled(true)
                        .accessibilityIdentifier("trendUnavailable")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isCreating) {
            TrendCreationFlow(trend: trend)
        }
    }

    private func photoNeed(_ trend: TrendDefinition) -> String {
        let range = trend.photos.range
        let count = range.lowerBound == range.upperBound
            ? Counted.text(range.lowerBound, "photo", "photos")
            : "\(range.lowerBound)–\(range.upperBound) photos"
        return "\(count) of the two of you."
    }
}

/// "About AI creations" — shown before (and only for) creations that need an AI provider.
struct AICreationDisclosure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("About AI creations", systemImage: "info.circle")
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("This creation requires the photos you select to be processed by an AI provider.")
            Text("Only the photos selected for this creation will be sent. The rest of your Relive library is not uploaded.")
            Text("AI creations aren’t available yet, so nothing is sent today.")
                .foregroundStyle(Palette.textTertiary)
        }
        .font(Typography.footnote)
        .foregroundStyle(Palette.textSecondary)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aiDisclosure")
    }
}

// MARK: - Creation

/// Choose photos, then the studio — in one sheet.
struct TrendCreationFlow: View {
    let trend: TrendDefinition

    @Environment(StoryStore.self) private var store
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var studio: TrendStudioModel?

    var body: some View {
        NavigationStack {
            if let studio {
                TrendStudioView(model: studio, onClose: { dismiss() })
            } else if let recipe = TrendRecipeRegistry.recipe(for: trend.recipe), trend.execution != .ai {
                MemoryPickerView(
                    title: "Choose Photos",
                    range: trend.photos.range,
                    onDone: { ids in
                        studio = TrendStudioModel(
                            trend: trend, recipe: recipe, photoIDs: ids,
                            library: store.creationLibrary, coupleNames: TrendSamples.coupleNames(app.relationship)
                        )
                    },
                    onCancel: { dismiss() }
                )
            } else {
                QuietMessageView(title: "Not available yet", message: "This creation isn’t available in this version of Relive.")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
            }
        }
        .tint(Palette.accent)
    }
}

struct TrendStudioView: View {
    @Bindable var model: TrendStudioModel
    let onClose: () -> Void

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScaledCanvas(designSize: model.recipe.designSize) {
                model.recipe.canvas(photos: model.photos(dates: dates), context: model.context)
            }
            .frame(maxHeight: .infinity)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .overlay {
                if model.isProcessing && model.processed.isEmpty { ProgressView() }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.trend.name) preview, \(model.recipe.variations[model.variation])")
            .accessibilityIdentifier("trendPreview")

            if !model.missing.isEmpty {
                Text("A photo is no longer in your library. Close and choose again.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }

            if model.recipe.variations.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.l) {
                        ForEach(Array(model.recipe.variations.enumerated()), id: \.offset) { index, name in
                            StyleChoice(title: name, isSelected: model.variation == index) {
                                Task { await model.choose(variation: index) }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("trendVariations")
            }

            VStack(spacing: Spacing.xs) {
                ExportStatusView(controller: model.export)
                HStack(spacing: Spacing.s) {
                    Button {
                        Task { await share() }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.reliveOutline)
                    .disabled(!model.canExport)
                    .accessibilityIdentifier("trendShare")
                    Button("Save to Photos") { Task { await save() } }
                        .buttonStyle(.relivePrimary)
                        .disabled(!model.canExport || model.isSaved)
                        .accessibilityIdentifier("trendSave")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.s)
        }
        .padding(.top, Spacing.s)
        .reliveBackground()
        .navigationTitle(model.trend.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .task {
            await model.load(using: CreationImageSource(loader: loader))
        }
    }

    private var dates: [AssetID: Date] {
        Dictionary(uniqueKeysWithValues: model.photoIDs.compactMap { id in store.assets[id]?.creationDate.map { (id, $0) } })
    }

    private func save() async {
        let images = CreationImageSource(loader: loader)
        let dates = self.dates
        await model.export.save(store: store, analytics: analytics, properties: model.analyticsProperties) {
            let image = try await model.renderExport(using: images, dates: dates)
            return [image]
        }
    }

    private func share() async {
        let images = CreationImageSource(loader: loader)
        let dates = self.dates
        await model.export.share(name: model.trend.name, analytics: analytics, properties: model.analyticsProperties) {
            let image = try await model.renderExport(using: images, dates: dates)
            return [image]
        }
    }
}
