import ReliveCore
import SwiftUI

/// "We found something for you." — the first thing Relive shows a new couple: the strongest
/// real result the existing systems found (a trip's movie, a recap, a Made for You creation, a
/// moment), then the way into the whole story.
///
/// Nothing here is new intelligence: Made for You decides what is worth making;
/// `FirstDiscoveryResolver` only picks which result leads. Opening it routes into the existing
/// movie editor, recap, creation or moment — never a copy made for onboarding.
struct FirstDiscoveryView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(MadeForYouStore.self) private var madeForYou
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discovery: FirstDiscovery?
    @State private var resolved = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(headline)
                        .font(Typography.display)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("firstDiscoveryHeadline")

                    if let discovery {
                        result(discovery)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 8)
                    }
                }
                .padding(.top, Spacing.xl)
                .padding(.horizontal, Spacing.screenMargin)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: Spacing.xs) {
                if let discovery {
                    Button(action: { open(discovery) }) {
                        Text(Self.actionTitle(for: discovery))
                    }
                    .buttonStyle(.relivePrimary)
                    .accessibilityIdentifier("firstDiscoveryOpen")
                }
                if discovery == nil {
                    seeStory.buttonStyle(.relivePrimary)
                } else {
                    seeStory.buttonStyle(.reliveQuiet)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.m)
        }
        .reliveBackground()
        .task {
            guard !resolved else { return }
            resolved = true
            madeForYou.refresh(from: store)
            discovery = FirstDiscoveryResolver().resolve(suggestions: madeForYou.suggestions, library: store.creationLibrary)
            if let suggestion = discovery?.suggestion {
                madeForYou.recordShown([suggestion])
            }
            analytics.track(.firstDiscoveryShown, ["result": discovery?.kind.rawValue ?? "none", "path": app.photoStartPath?.rawValue ?? "unknown"])
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.5).delay(0.2)) { appeared = true }
            }
        }
    }

    private var seeStory: some View {
        Button("See Our Story") {
            analytics.track(.firstDiscoveryOpened, ["result": discovery?.kind.rawValue ?? "none", "action": "story"])
            app.completeOnboarding(result: discovery?.kind.rawValue ?? "none")
        }
        .accessibilityIdentifier("seeOurStory")
    }

    private var headline: String {
        guard resolved else { return "" }
        guard let discovery else { return String(localized: "Your story has started.") }
        return discovery.kind == .smallStory ? String(localized: "Your story has started.") : String(localized: "We found something for you.")
    }

    // MARK: - The result

    @ViewBuilder
    private func result(_ discovery: FirstDiscovery) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // Short enough that the title stays above the buttons on every iPhone.
            FramedAssetImage(assetID: discovery.coverAssetID, aspectRatio: 4 / 3)
                .frame(maxHeight: 300)
                .accessibilityHidden(true)
            if let eyebrow = eyebrow(discovery) {
                Text(eyebrow).eyebrowStyle()
            }
            Text(title(discovery))
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = subtitle(discovery) {
                Text(subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("firstDiscoveryResult")
        .accessibilityValue(discovery.kind.rawValue)
    }

    private func moment(_ discovery: FirstDiscovery) -> Moment? {
        discovery.momentID.flatMap { store.moment(id: $0) }
    }

    private func eyebrow(_ discovery: FirstDiscovery) -> String? {
        switch discovery.kind {
        case .movie: String(localized: "Memory Movie")
        case .recap: discovery.suggestion?.creation == .yearInReview ? String(localized: "Our Year") : String(localized: "Monthly Recap")
        case .suggestion: discovery.suggestion.map { CreationLabel.name($0.creation) }
        case .moment, .smallStory: String(localized: "From your story")
        }
    }

    private func title(_ discovery: FirstDiscovery) -> String {
        if let suggestion = discovery.suggestion { return suggestion.title }
        return moment(discovery)?.title.primary ?? String(localized: "A moment")
    }

    private func subtitle(_ discovery: FirstDiscovery) -> String? {
        if let suggestion = discovery.suggestion { return suggestion.subtitle }
        guard let moment = moment(discovery) else { return nil }
        let date = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true)
        return [date, Counted.text(moment.memoryCount, "memory", "memories")].compactMap { $0 }.joined(separator: " · ")
    }

    static func actionTitle(for discovery: FirstDiscovery) -> String {
        switch discovery.kind {
        case .movie: String(localized: "Watch Your Movie")
        case .recap: String(localized: "See Your Recap")
        case .suggestion:
            switch discovery.suggestion?.creation {
            case .book: String(localized: "Open Your Book")
            case .story: String(localized: "See Your Story")
            case .collage: String(localized: "See Your Collage")
            default: String(localized: "Open It")
            }
        case .moment, .smallStory: String(localized: "Open This Memory")
        }
    }

    // MARK: - Opening

    /// Onboarding ends and the result opens in the app's existing editor, recap or moment.
    private func open(_ discovery: FirstDiscovery) {
        analytics.track(.firstDiscoveryOpened, ["result": discovery.kind.rawValue, "action": "open"])
        app.completeOnboarding(result: discovery.kind.rawValue)
        if let suggestion = discovery.suggestion {
            MadeForYouOpener.open(suggestion, app: app, madeForYou: madeForYou, origin: RecapRequest.firstDiscoveryOrigin)
        } else if let momentID = discovery.momentID {
            app.pendingMomentID = momentID
        }
    }
}
