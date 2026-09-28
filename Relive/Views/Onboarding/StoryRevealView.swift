import ReliveCore
import SwiftUI

/// "Emma + Jake · 1,568 days · 197 memories · 24 moments · 11 places"
/// Every number is computed from the story; lines without data are left out.
struct StoryRevealView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleLines = 0

    var body: some View {
        VStack(spacing: 0) {
            HeroMosaic(assetIDs: store.representativeHeroIDs(limit: 9))
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(app.coupleName)
                    .font(Typography.display)
                    .foregroundStyle(Palette.textPrimary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(Array(statLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(Typography.title2)
                            .foregroundStyle(Palette.textPrimary)
                            .opacity(index < visibleLines ? 1 : 0)
                            .offset(y: index < visibleLines ? 0 : 6)
                    }
                }
                .accessibilityElement(children: .combine)

                Text("Look how much you’ve lived together.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Spacing.xs)
                    .opacity(visibleLines >= statLines.count ? 1 : 0)

                Button("See Our Story") {
                    app.completeReveal()
                }
                .buttonStyle(.relivePrimary)
                .padding(.top, Spacing.m)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.m)
        }
        .reliveBackground()
        .task {
            analytics.track(.storyRevealed, [
                "moments": String(store.statistics.momentCount),
                "places": String(store.statistics.placeCount),
            ])
            if reduceMotion {
                visibleLines = statLines.count
                return
            }
            for line in 1...max(1, statLines.count) {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.5)) { visibleLines = line }
            }
        }
    }

    private var statLines: [String] {
        let stats = store.statistics
        var lines: [String] = []
        if let start = app.relationship?.start {
            let days = start.daysTogether(until: Date(), calendar: .current)
            if days > 0 {
                let text = Counted.text(days, "day", "days")
                lines.append(start.isApproximate ? "About \(text)" : text)
            }
        }
        if stats.memoryCount > 0 { lines.append(Counted.text(stats.memoryCount, "memory", "memories")) }
        if stats.momentCount > 0 { lines.append(Counted.text(stats.momentCount, "moment", "moments")) }
        if stats.placeCount > 0 { lines.append(Counted.text(stats.placeCount, "place", "places")) }
        return lines
    }
}

/// A quiet grid of covers from across the story, fading into the page.
struct HeroMosaic: View {
    let assetIDs: [AssetID]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        GeometryReader { proxy in
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assetIDs, id: \.self) { id in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { AssetImageView(assetID: id) }
                        .clipped()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }
}
