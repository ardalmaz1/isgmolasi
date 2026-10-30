import PhotosUI
import ReliveCore
import SwiftUI

/// Where a creation's photos come from: the memories already in Relive, or any photo in the
/// iPhone's library. Library photos keep their own date and place and are never added to the
/// story.
struct PhotoSourceChooserView: View {
    let kind: CreationKind
    let onRelive: () -> Void
    let onPhotoLibrary: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Choose photos for your \(kind.noun)")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Spacing.m)

                VStack(spacing: Spacing.s) {
                    SourceRow(
                        title: String(localized: "From Yuvi"),
                        detail: String(localized: "Memories already in your story."),
                        systemImage: "book.closed",
                        action: onRelive
                    )
                    .accessibilityIdentifier("sourceRelive")
                    SourceRow(
                        title: String(localized: "From Photo Library"),
                        detail: String(localized: "Any photo on this iPhone. Its own date and place are used, and it isn’t added to your story."),
                        systemImage: "photo.on.rectangle",
                        action: onPhotoLibrary
                    )
                    .accessibilityIdentifier("sourcePhotoLibrary")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xl)
        }
        .reliveBackground()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}

/// What a Memory Movie is made from: something Relive already understands (a moment, a trip, a
/// month, a year), or photos chosen by hand.
struct MovieSourceChooserView: View {
    let onMoment: () -> Void
    let onTrip: () -> Void
    let onMonth: () -> Void
    let onYear: () -> Void
    let onPhotos: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Make a Memory Movie")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Yuvi chooses the photos, the order and the rhythm. You can change anything after.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.m)

                VStack(spacing: Spacing.s) {
                    SourceRow(title: String(localized: "Choose a Moment"), detail: String(localized: "One afternoon, one evening, one day."), systemImage: "sparkles", action: onMoment)
                        .accessibilityIdentifier("movieSourceMoment")
                    SourceRow(title: String(localized: "Choose a Trip"), detail: String(localized: "Every day of it, in order."), systemImage: "airplane", action: onTrip)
                        .accessibilityIdentifier("movieSourceTrip")
                    SourceRow(title: String(localized: "Choose a Month"), detail: String(localized: "A month of your story."), systemImage: "calendar", action: onMonth)
                        .accessibilityIdentifier("movieSourceMonth")
                    SourceRow(title: String(localized: "Choose a Year"), detail: String(localized: "Your year, as a short film."), systemImage: "calendar.badge.clock", action: onYear)
                        .accessibilityIdentifier("movieSourceYear")
                    SourceRow(title: String(localized: "Choose Photos"), detail: String(localized: "Pick the photos yourself; Yuvi keeps them as you chose."), systemImage: "photo.on.rectangle", action: onPhotos)
                        .accessibilityIdentifier("movieSourcePhotos")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.xl)
        }
        .reliveBackground()
        .navigationTitle("Memory Movie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}

private struct SourceRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 32

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension CreationKind {
    /// "collage", "story", "book" — for sentences.
    var noun: String {
        switch self {
        case .collage: String(localized: "collage")
        case .story: String(localized: "story")
        case .book: String(localized: "book")
        case .movie: String(localized: "movie")
        }
    }
}

// MARK: - System picker

/// Presents Apple's photo picker for a creation and hands back the chosen photos' identifiers,
/// in the order they were picked. Only still photos (no screenshots) can be picked.
private struct PhotoLibraryPicker: ViewModifier {
    @Binding var isPresented: Bool
    let maximum: Int
    let onPicked: ([AssetID]) -> Void

    @Environment(StoryStore.self) private var store
    @State private var items: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: isPresentedForSystem,
                selection: $items,
                maxSelectionCount: maximum,
                selectionBehavior: .ordered,
                matching: .all(of: [.images, .not(.screenshots)]),
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            )
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty else { return }
                let identifiers = picked.compactMap(\.itemIdentifier)
                items = []
                onPicked(identifiers)
            }
            .onChange(of: isPresented) { _, presented in
                #if DEBUG
                if presented, UITestPhotoLibraryPicks.isEnabled {
                    isPresented = false
                    Task { onPicked(await UITestPhotoLibraryPicks.identifiers(from: store, maximum: maximum)) }
                }
                #endif
            }
    }

    private var isPresentedForSystem: Binding<Bool> {
        #if DEBUG
        if UITestPhotoLibraryPicks.isEnabled { return .constant(false) }
        #endif
        return $isPresented
    }
}

extension View {
    func photoLibraryPicker(isPresented: Binding<Bool>, maximum: Int, onPicked: @escaping ([AssetID]) -> Void) -> some View {
        modifier(PhotoLibraryPicker(isPresented: isPresented, maximum: maximum, onPicked: onPicked))
    }
}

#if DEBUG
/// UI tests can't drive Apple's out-of-process picker reliably; with this launch argument the
/// "picker" returns the oldest photos Relive can read, so the rest of the flow is exercised.
enum UITestPhotoLibraryPicks {
    static let argument = "-ReliveUITestPhotoLibraryPicks"

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    @MainActor
    static func identifiers(from store: StoryStore, maximum: Int) async -> [AssetID] {
        let photos = await store.photoLibrary.allAccessibleAssets()
            .filter { $0.kind == .photo && !$0.isScreenshot }
            .sorted { ($0.creationDate ?? .distantFuture, $0.id) < ($1.creationDate ?? .distantFuture, $1.id) }
        return Array(photos.prefix(min(maximum, 6)).map(\.id))
    }
}
#endif

/// Shown when picked photos can't be read (with limited access, photos not shared with Relive).
struct PhotoLibraryUnavailableView: View {
    let count: Int
    let onChooseAgain: () -> Void
    let onCancel: () -> Void

    var body: some View {
        QuietMessageView(
            title: count == 1 ? String(localized: "Yuvi can’t open that photo") : String(localized: "Yuvi can’t open those photos"),
            message: String(localized: "Yuvi can only use photos you’ve shared with it. You can share more in Us → Photo Access, or choose others."),
            actionTitle: String(localized: "Choose Again"),
            action: onChooseAgain
        )
        .frame(maxHeight: .infinity)
        .reliveBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
