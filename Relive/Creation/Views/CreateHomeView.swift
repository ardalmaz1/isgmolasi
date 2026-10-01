import ReliveCore
import SwiftUI

/// Navigation targets inside the Create tab.
enum CreateRoute: Hashable {
    case months
    case month(MonthKey)
    case years
    case year(Int)
}

/// Create: Relive's creative hub. Four things, each shown with the user's own photos.
/// "Choose memories. Relive makes something beautiful from them."
struct CreateHomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @State private var path: [CreateRoute] = []

    var body: some View {
        let library = store.creationLibrary
        let months = MonthlyRecapBuilder(library: library).availableMonths()
        let years = YearInReviewBuilder(library: library).availableYears()

        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Create")
                            .font(Typography.display)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose memories. Relive makes something beautiful from them.")
                            .font(Typography.callout)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Spacing.l)

                    if library.visibleMoments.isEmpty {
                        QuietMessageView(
                            title: "Nothing to make from yet",
                            message: "Once your story has memories, you can turn them into collages, stories and recaps here."
                        )
                    } else {
                        collageFeature(library: library)
                        Hairline()
                        storyFeature(library: library)
                        Hairline()
                        monthlyRecapRow(library: library, months: months)
                        Hairline()
                        yearRow(library: library, years: years)
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .reliveBackground()
            .statusBarBackdrop()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CreateRoute.self) { route in
                switch route {
                case .months: MonthlyRecapListView()
                case .month(let month): MonthlyRecapView(month: month)
                case .years: YearListView()
                case .year(let year): OurYearView(year: year)
                }
            }
            .momentDestination()
        }
        .onAppear { analytics.track(.createOpened) }
    }

    // MARK: - Memory Collage

    private func collageFeature(library: CreationLibrary) -> some View {
        let photos = featuredPhotos(library: library, count: 3)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: 4) {
                ForEach(Array(photos.enumerated()), id: \.element) { index, id in
                    Color.clear
                        .aspectRatio(index == 0 ? 0.8 : 0.62, contentMode: .fit)
                        .overlay { AssetImageView(assetID: id) }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                }
            }
            .frame(maxHeight: 240)
            .accessibilityHidden(true)

            FeatureText(title: "Memory Collage", subtitle: "Make something from your favorite photos.")

            HStack(spacing: Spacing.s) {
                Button("Choose Photos") { app.startCreation(.collage, from: .choosePhotos, origin: "create") }
                    .buttonStyle(.reliveOutline)
                    .accessibilityIdentifier("createCollagePhotos")
                Button("Choose a Moment") { app.startCreation(.collage, from: .chooseMoment, origin: "create") }
                    .buttonStyle(.reliveOutline)
                    .accessibilityIdentifier("createCollageMoment")
            }
        }
    }

    // MARK: - Story Maker

    private func storyFeature(library: CreationLibrary) -> some View {
        let cover = library.visibleMoments.last(where: { $0.kind != .undated }).flatMap(library.lead(of:))
        return HStack(alignment: .top, spacing: Spacing.m) {
            Color.clear
                .frame(width: 90, height: 160)
                .overlay { AssetImageView(assetID: cover) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                FeatureText(title: "Story Maker", subtitle: "Turn a moment into a story.")
                Button("Choose a Moment") { app.startCreation(.story, from: .chooseMoment, origin: "create") }
                    .buttonStyle(.reliveOutline)
                    .accessibilityIdentifier("createStoryMoment")
                Button("Choose Photos") { app.startCreation(.story, from: .choosePhotos, origin: "create") }
                    .buttonStyle(.reliveQuiet)
                    .accessibilityIdentifier("createStoryPhotos")
            }
        }
    }

    // MARK: - Monthly Recap

    private func monthlyRecapRow(library: CreationLibrary, months: [MonthKey]) -> some View {
        let latest = months.first
        let cover = latest.flatMap { MonthlyRecapBuilder(library: library).recap(for: $0).highlights(limit: 1).first }
        return NavigationLink(value: CreateRoute.months) {
            FeatureRow(
                title: "Monthly Recap",
                subtitle: "Look back at your month together.",
                detail: latest.map { "Latest: \(CreationText.monthTitle($0))" },
                coverID: cover
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("createMonthlyRecap")
    }

    // MARK: - Our Year

    private func yearRow(library: CreationLibrary, years: [Int]) -> some View {
        let latest = years.first
        let cover = latest.flatMap { YearInReviewBuilder(library: library).review(for: $0).highlights(limit: 1).first }
        return NavigationLink(value: years.count == 1 ? CreateRoute.year(years[0]) : CreateRoute.years) {
            FeatureRow(
                title: "Our Year",
                subtitle: "Your year together, remembered.",
                detail: years.isEmpty ? nil : years.prefix(3).map(String.init).joined(separator: " · "),
                coverID: cover
            )
        }
        .buttonStyle(.plain)
        .disabled(years.isEmpty)
        .accessibilityIdentifier("createOurYear")
    }

    /// A few strong photos from different recent moments, for the collage feature.
    private func featuredPhotos(library: CreationLibrary, count: Int) -> [AssetID] {
        var picked: [AssetID] = []
        for moment in library.visibleMoments.reversed() where moment.kind != .undated {
            if let lead = library.lead(of: moment), !picked.contains(lead) {
                picked.append(lead)
            }
            if picked.count == count { break }
        }
        return picked
    }
}

private struct FeatureText: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typography.title2)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A quiet row that opens a list (months, years).
private struct FeatureRow: View {
    let title: String
    let subtitle: String
    let detail: String?
    let coverID: AssetID?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Color.clear
                .frame(width: 72, height: 90)
                .overlay { AssetImageView(assetID: coverID) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                FeatureText(title: title, subtitle: subtitle)
                if let detail {
                    Text(detail)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
