import ReliveCore
import SwiftUI

/// The Memory Movie editor: watch the film Relive made, change a few simple things, keep it.
///
/// Not a video editor: a preview, Make it for me, style, shape, length, titles, and a strip of
/// scenes to reorder, remove, replace or choose the opening. Previewing and editing are free;
/// Save Video and Share use the Premium gate (a movie isn't part of the one free creation).
struct MovieEditorView: View {
    @Bindable var model: MovieEditorModel
    let onClose: () -> Void

    @Environment(StoryStore.self) private var store
    @Environment(PremiumStore.self) private var premium
    @Environment(MadeForYouStore.self) private var madeForYou
    @Environment(\.analytics) private var analytics
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var gate = PremiumGate()
    @State private var isPlaying = false
    @State private var position: Double = 0
    @State private var hasPreviewed = false
    @State private var replacing: AssetID?
    @State private var confirmsDelete = false
    @State private var editsTitle = false
    @State private var draftTitle = ""
    @State private var confirmsRemake = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                previewSection
                Button {
                    // Explicit permission to replace the user's own cut — asked for, not assumed.
                    if model.remakeReplacesUserEdits {
                        confirmsRemake = true
                    } else {
                        remake()
                    }
                } label: {
                    Label("Make it for me", systemImage: "wand.and.stars")
                }
                .buttonStyle(.reliveOutline)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Yuvi chooses photos again and makes a new cut. Your style, shape and length stay.")
                .accessibilityIdentifier("movieMakeItForMe")
                .confirmationDialog("Make a new cut?", isPresented: $confirmsRemake, titleVisibility: .visible) {
                    Button("Make a New Cut") { remake() }
                        .accessibilityIdentifier("movieRemakeConfirm")
                    Button("Keep My Changes", role: .cancel) {}
                } message: {
                    Text("Yuvi will choose the photos again. The photos and order you changed will be replaced; your style, shape, length and title stay.")
                }

                if let note = noteText {
                    Text(note)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.screenMargin)
                        .accessibilityIdentifier("movieNote")
                }

                titleSection
                styleSection
                shapeSection
                scenesSection
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .navigationTitle("Memory Movie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    isPlaying = false
                    if model.export.isBusy { model.export.cancel() }
                    onClose()
                }
                .accessibilityIdentifier("movieClose")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await share() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.canExport || model.export.isBusy)
                .accessibilityIdentifier("movieShare")
                CreationMoreMenu(keeper: model.keeper) { confirmsDelete = true }
            }
        }
        .confirmsCreationDelete(isPresented: $confirmsDelete, keeper: model.keeper, store: store, onDeleted: onClose)
        .alert("Movie Title", isPresented: $editsTitle) {
            TextField("Title", text: $draftTitle)
                .accessibilityIdentifier("movieTitleField")
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.setOwnTitle(draftTitle) }
        } message: {
            Text("Your own words, shown just as you write them.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .overlay { exportOverlay }
        .premiumPaywall(gate)
        .sheet(item: Binding(get: { replacing.map(ReplaceRequest.init) }, set: { replacing = $0?.id })) { request in
            NavigationStack {
                MemoryPickerView(
                    title: "Replace Photo",
                    range: 1...1,
                    excluded: Set(model.plan.photoIDs),
                    limitedTo: Set(model.replacementCandidates),
                    onDone: { ids in
                        if let id = ids.first { model.replace(request.id, with: id) }
                        replacing = nil
                    },
                    onCancel: { replacing = nil }
                )
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing, !hasPreviewed {
                hasPreviewed = true
                analytics.track(.moviePreviewed, model.analyticsProperties)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isPlaying = false }
        }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    private struct ReplaceRequest: Identifiable {
        let id: AssetID
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(spacing: Spacing.s) {
            MoviePreviewView(plan: model.plan, isPlaying: $isPlaying, position: $position)
                .frame(maxWidth: .infinity, maxHeight: model.settings.aspect == .portrait ? 460 : 260)
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                .overlay(alignment: .bottomLeading) {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.s)
                    .disabled(model.plan.scenes.isEmpty)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier("moviePlay")
                }
            VStack(spacing: 2) {
                Text(model.plan.title.combined)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(Counted.text(model.plan.scenes.count, "photo", "photos")) · \(MovieText.durationLabel(model.plan.duration))")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("movieSummary")
        }
        .padding(.horizontal, Spacing.screenMargin)
    }

    private var noteText: String? {
        if case .insufficient(let available, let required) = model.plan.status {
            return available == 0
                ? "There are no photos here that can go into a movie."
                : "A movie needs at least \(required) different photos, and there \(available == 1 ? "is 1" : "are \(available)") here. Choose a few more to make one."
        }
        if !model.missing.isEmpty {
            return model.missing.count == 1
                ? "One photo is no longer in your library and was left out."
                : "\(model.missing.count) photos are no longer in your library and were left out."
        }
        return nil
    }

    // MARK: - Choices

    /// Relive's words for the opening — never more than a few, all true of these photos — and
    /// the user's own. No sparkles, no prompt box: a title, and three plain choices.
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Title").eyebrowStyle()
            Text(model.openingTitle ?? "No title")
                .font(Typography.title3)
                .foregroundStyle(model.openingTitle == nil ? Palette.textSecondary : Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.openingTitle.map { "Title: \($0)" } ?? "No title")
                .accessibilityIdentifier("movieTitleText")
            FlowLayout {
                Button("Try another") {
                    withAnimation(animation) { model.tryAnotherTitle() }
                }
                .disabled(!model.canTryAnotherTitle)
                .opacity(model.canTryAnotherTitle ? 1 : 0.4)
                .accessibilityLabel("Try another title")
                .accessibilityHint("Shows another title made from this movie's dates and places")
                .accessibilityIdentifier("movieTitleTryAnother")
                Button("Edit") {
                    draftTitle = model.openingTitle ?? ""
                    editsTitle = true
                }
                .accessibilityLabel("Edit title")
                .accessibilityIdentifier("movieTitleEdit")
                if model.titleChoice.isDefault {
                    Button("Remove") {
                        withAnimation(animation) { model.removeTitle() }
                    }
                    .accessibilityLabel("Remove title")
                    .accessibilityIdentifier("movieTitleRemove")
                } else {
                    Button("Reset") {
                        withAnimation(animation) { model.resetTitle() }
                    }
                    .accessibilityLabel("Reset title")
                    .accessibilityHint("Goes back to Yuvi's title")
                    .accessibilityIdentifier("movieTitleReset")
                }
            }
            .buttonStyle(.reliveOutline)
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, Spacing.screenMargin)
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Style").eyebrowStyle()
            FlowLayout {
                ForEach(MovieStyle.allCases, id: \.self) { style in
                    StyleChoice(title: style.name, isSelected: model.settings.style == style) {
                        withAnimation(animation) { model.setStyle(style) }
                    }
                    .accessibilityIdentifier("movieStyle-\(style.rawValue)")
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, Spacing.screenMargin)
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Shape").eyebrowStyle()
                Picker("Shape", selection: Binding(get: { model.settings.aspect }, set: { model.setAspect($0) })) {
                    Text("9:16 Tall").tag(MovieAspect.portrait)
                    Text("16:9 Wide").tag(MovieAspect.landscape)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("movieAspect")
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Length").eyebrowStyle()
                Picker("Length", selection: Binding(get: { model.settings.length }, set: { model.setLength($0) })) {
                    ForEach(MovieLength.allCases, id: \.self) { length in
                        Text(length.name).tag(length)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("movieLength")
            }
            Toggle(isOn: Binding(get: { model.settings.showsText }, set: { model.setShowsText($0) })) {
                LabeledText(label: "Titles", value: "The title, places and dates")
            }
            .tint(Palette.accent)
            .accessibilityIdentifier("movieTitles")
        }
        .padding(.horizontal, Spacing.screenMargin)
    }

    // MARK: - Scenes

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Scenes").eyebrowStyle()
                .padding(.horizontal, Spacing.screenMargin)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(Array(model.plan.scenes.enumerated()), id: \.element.id) { index, scene in
                            sceneThumbnail(scene, index: index)
                                .id(scene.id)
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selectedSceneID) { _, id in
                    guard let id else { return }
                    withAnimation(animation) { reader.scrollTo(id, anchor: .center) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("movieScenes")

            if let id = model.selectedSceneID, let index = model.plan.photoIDs.firstIndex(of: id) {
                sceneActions(id: id, index: index)
                    .padding(.horizontal, Spacing.screenMargin)
            } else {
                Text("Tap a scene to move, replace or remove it.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.screenMargin)
            }
        }
    }

    private func sceneThumbnail(_ scene: MovieScene, index: Int) -> some View {
        let isSelected = model.selectedSceneID == scene.id
        return Button {
            isPlaying = false
            model.selectedSceneID = isSelected ? nil : scene.id
            let timeline = MovieTimeline(plan: model.plan)
            if timeline.starts.indices.contains(index) {
                position = min(timeline.duration, timeline.starts[index] + scene.duration * 0.55)
            }
        } label: {
            Color.clear
                .frame(width: 60, height: 84)
                .overlay { AssetImageView(assetID: scene.assetID) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.photo, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(index == 0 ? "Opening" : "\(index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .padding(4)
                }
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(index == 0 ? "Opening scene" : "Scene \(index + 1) of \(model.plan.scenes.count)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("movieScene")
    }

    private func sceneActions(id: AssetID, index: Int) -> some View {
        let count = model.plan.scenes.count
        return FlowLayout {
            actionButton("Earlier", systemImage: "arrow.left", identifier: "movieSceneEarlier", disabled: index == 0) {
                model.move(id, by: -1)
            }
            actionButton("Later", systemImage: "arrow.right", identifier: "movieSceneLater", disabled: index >= count - 1) {
                model.move(id, by: 1)
            }
            actionButton("Make Opening", systemImage: "star", identifier: "movieSceneOpening", disabled: index == 0) {
                model.makeOpening(id)
            }
            actionButton("Replace", systemImage: "arrow.triangle.2.circlepath", identifier: "movieSceneReplace", disabled: model.replacementCandidates.isEmpty) {
                replacing = id
            }
            actionButton("Remove", systemImage: "trash", identifier: "movieSceneRemove", disabled: count <= MovieEligibility.minimumPhotos) {
                model.remove(id)
            }
            // A photo that shouldn't be in an automatic movie: out of this one, and never
            // suggested again (it stays in the story).
            actionButton("Don’t Suggest", systemImage: "eye.slash", identifier: "movieSceneDontSuggest", disabled: count <= MovieEligibility.minimumPhotos) {
                model.removeAndDontSuggest(id, store: store)
            }
        }
    }

    private func remake() {
        isPlaying = false
        position = 0
        withAnimation(animation) { model.makeItForMe() }
    }

    private func actionButton(_ title: String, systemImage: String, identifier: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            isPlaying = false
            withAnimation(animation) { action() }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.reliveOutline)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Keeping it

    private var saveBar: some View {
        VStack(spacing: Spacing.xs) {
            Hairline()
            if case .finished(let message) = model.export.phase {
                Label(message, systemImage: "checkmark")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityIdentifier("movieExportFinished")
            } else if case .failed(let message) = model.export.phase {
                VStack(spacing: Spacing.xs) {
                    Text(message)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    if model.export.offersSettings {
                        Button("Open Settings") { SystemPresenter.openSettings() }
                            .font(Typography.footnote.weight(.semibold))
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("movieExportFailed")
            }
            Button {
                Task { await save() }
            } label: {
                Label("Save Video", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.relivePrimary)
            .disabled(!model.canExport || model.export.isBusy)
            .padding(.horizontal, Spacing.screenMargin)
            .accessibilityIdentifier("movieSave")
        }
        .padding(.bottom, Spacing.xs)
        .background(Palette.background, ignoresSafeAreaEdges: .bottom)
    }

    @ViewBuilder
    private var exportOverlay: some View {
        switch model.export.phase {
        case .rendering(let progress):
            progressCard(title: "Creating your movie…", progress: progress, cancellable: true)
        case .saving:
            progressCard(title: "Saving to Photos…", progress: nil, cancellable: false)
        default:
            EmptyView()
        }
    }

    private func progressCard(title: String, progress: Double?, cancellable: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                Text(title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                if let progress {
                    ProgressView(value: progress)
                        .tint(Palette.textPrimary)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(Typography.callout.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ProgressView()
                }
                if cancellable {
                    Button("Cancel") { model.export.cancel() }
                        .buttonStyle(.reliveOutline)
                        .accessibilityIdentifier("movieExportCancel")
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.background))
            .padding(Spacing.screenMargin)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("movieExportProgress")
        }
    }

    /// Save and Share go through the Premium gate. Previewing and editing never do; a movie is
    /// not part of the one free creation.
    private func save() async {
        isPlaying = false
        let plan = model.plan
        await gate.export(.memoryMovie, entry: .memoryMovie, premium: premium, heroAssetID: plan.cover) { succeeded in
            await model.export.save(plan: plan, loader: loader, store: store, analytics: analytics, properties: model.analyticsProperties, onSaved: {
                model.keeper.markExported()
                madeForYou.recordMade(source: model.source, creation: .movie)
                succeeded()
            })
        }
    }

    private func share() async {
        isPlaying = false
        let plan = model.plan
        await gate.export(.memoryMovie, entry: .memoryMovie, premium: premium, heroAssetID: plan.cover) { succeeded in
            await model.export.share(plan: plan, loader: loader, analytics: analytics, properties: model.analyticsProperties, onShared: {
                model.keeper.markExported()
                madeForYou.recordMade(source: model.source, creation: .movie)
                succeeded()
            })
        }
    }
}
