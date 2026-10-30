import ReliveCore
import SwiftUI

/// Create → Made for You: one large suggestion and up to three quiet rows. Nothing when there
/// is nothing good to suggest — empty space is better than a weak card.
struct MadeForYouSection: View {
    let suggestions: [MadeForYouSuggestion]
    let onOpen: (MadeForYouSuggestion) -> Void
    let onDismiss: (MadeForYouSuggestion) -> Void

    var body: some View {
        if let hero = suggestions.first {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Made for You")
                    .font(Typography.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                MadeForYouHeroCard(suggestion: hero, onOpen: { onOpen(hero) }, onDismiss: { onDismiss(hero) })
                let rest = Array(suggestions.dropFirst().prefix(3))
                if !rest.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(rest) { suggestion in
                            MadeForYouRow(suggestion: suggestion, onOpen: { onOpen(suggestion) }, onDismiss: { onDismiss(suggestion) })
                            if suggestion.id != rest.last?.id { Hairline() }
                        }
                    }
                }
            }
            // A container: its own identifier must not replace the cards' identifiers.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("madeForYou")
        }
    }
}

/// The lead suggestion: a real cover, the eyebrow, the title, the facts, and what it makes.
struct MadeForYouHeroCard: View {
    let suggestion: MadeForYouSuggestion
    let onOpen: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                FramedAssetImage(assetID: suggestion.coverAssetID, aspectRatio: 4 / 3, cornerRadius: Radius.card)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(suggestion.eyebrow).eyebrowStyle()
                    Text(suggestion.title)
                        .font(Typography.title2)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // Side by side normally; stacked at accessibility text sizes, so neither is squeezed.
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.xs))
                    layout {
                        Text(suggestion.subtitle)
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
                        CreationLabel(creation: suggestion.creation)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .madeForYouAccessibility(suggestion, onDismiss: onDismiss)
        .contextMenu {
            Button("Not now", systemImage: "eye.slash", action: onDismiss)
        }
    }
}

/// A smaller suggestion row.
struct MadeForYouRow: View {
    let suggestion: MadeForYouSuggestion
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.m) {
                Color.clear
                    .frame(width: Thumb.row.width, height: Thumb.row.height)
                    .overlay { AssetImageView(assetID: suggestion.coverAssetID) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.eyebrow).eyebrowStyle()
                    Text(suggestion.title)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suggestion.subtitle)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    CreationLabel(creation: suggestion.creation)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .madeForYouAccessibility(suggestion, onDismiss: onDismiss)
        .contextMenu {
            Button("Not now", systemImage: "eye.slash", action: onDismiss)
        }
    }
}

/// Today's single Made for You card, when one is strong enough.
struct MadeForYouTodayCard: View {
    let suggestion: MadeForYouSuggestion
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Made for You").eyebrowStyle()
            MadeForYouRow(suggestion: suggestion, onOpen: onOpen, onDismiss: onDismiss)
        }
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("madeForYouToday")
    }
}

/// "Memory Book", "Story", … — what opening the suggestion makes or shows.
struct CreationLabel: View {
    let creation: ReliveCore.CreationKind

    var body: some View {
        Label(Self.name(creation), systemImage: Self.symbol(creation))
            .font(Typography.footnote.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
            .labelStyle(.titleAndIcon)
    }

    static func name(_ creation: ReliveCore.CreationKind) -> String {
        switch creation {
        case .collage: String(localized: "Collage")
        case .story: String(localized: "Story")
        case .book: String(localized: "Memory Book")
        case .monthlyRecap: String(localized: "Monthly Recap")
        case .yearInReview: String(localized: "Our Year")
        case .movie: String(localized: "Memory Movie")
        }
    }

    static func symbol(_ creation: ReliveCore.CreationKind) -> String {
        switch creation {
        case .collage: "square.grid.2x2"
        case .story: "rectangle.portrait.on.rectangle.portrait"
        case .book: "book.closed"
        case .monthlyRecap: "calendar"
        case .yearInReview: "calendar.badge.clock"
        case .movie: "film"
        }
    }
}

extension View {
    /// One VoiceOver element per suggestion, with "Not now" as an action.
    fileprivate func madeForYouAccessibility(_ suggestion: MadeForYouSuggestion, onDismiss: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(AccessibilitySentences.join([suggestion.eyebrow, suggestion.title, suggestion.subtitle, CreationLabel.name(suggestion.creation)]))
            .accessibilityHint("Opens it, ready to look at and edit")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Not now", onDismiss)
            .accessibilityValue(suggestion.creation.rawValue)
            .accessibilityIdentifier("madeForYouCard")
    }
}

/// Opening a suggestion: recaps open the immersive recap; creations (including a Memory Movie)
/// open the existing editors with Memory Intelligence's photos. Nothing is saved, and nothing asks for Premium.
@MainActor
enum MadeForYouOpener {
    static func open(_ suggestion: MadeForYouSuggestion, app: AppModel, madeForYou: MadeForYouStore, origin: String) {
        madeForYou.recordOpened(suggestion)
        switch suggestion.creation {
        case .monthlyRecap:
            if case .month(let month) = suggestion.source { app.openRecap(.month(month), origin: origin) }
        case .yearInReview:
            if case .year(let year) = suggestion.source { app.openRecap(.year(year), origin: origin) }
        case .collage:
            app.startCreation(.collage, from: .source(suggestion.source), origin: origin)
        case .story:
            app.startCreation(.story, from: .source(suggestion.source), origin: origin)
        case .book:
            app.startCreation(.book, from: .source(suggestion.source), origin: origin)
        case .movie:
            app.startCreation(.movie, from: .source(suggestion.source), origin: origin)
        }
    }
}

/// Joins phrases into one spoken label, one sentence each, without doubling a full stop the
/// phrase already has ("Four days in Kaş." stays one sentence).
enum AccessibilitySentences {
    static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") || $0.hasSuffix("!") || $0.hasSuffix("?") ? $0 : $0 + "." }
            .joined(separator: " ")
    }
}
