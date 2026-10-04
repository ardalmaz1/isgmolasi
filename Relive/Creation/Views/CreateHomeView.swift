import ReliveCore
import SwiftUI

/// Navigation targets inside the Create tab.
enum CreateRoute: Hashable {
    case months
    case month(MonthKey)
    case years
    case year(Int)
    case trend(String)
}

/// Create: Relive's creative studio, and the couple's own collection.
///
/// In order: Continue Editing (only when there are drafts), Your Creations, Favorites, then the
/// five tools (Create Something), each shown with the couple's own photos, and Trending Now.
/// Every line about the couple is a fact ("You have 8 favorites"), never a judgement.
struct CreateHomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(TrendCatalogStore.self) private var trends
    @Environment(\.analytics) private var analytics
    @State private var path: [CreateRoute] = []
    @State private var choosesBookSource = false

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

                    if let draft = store.drafts.first {
                        continueEditing(draft, count: store.drafts.count)
                    }
                    yourCreations
                    if library.visibleMoments.isEmpty {
                        QuietMessageView(
                            title: "Nothing to make from yet",
                            message: "Once your story has memories, you can turn them into collages, stories and recaps here."
                        )
                    } else {
                        favoritesSection(library: library)
                        Text("Create Something")
                            .eyebrowStyle()
                            .accessibilityAddTraits(.isHeader)
                        collageFeature(library: library)
                        Hairline()
                        storyFeature(library: library)
                        Hairline()
                        bookFeature(library: library, months: months, years: years)
                        Hairline()
                        monthlyRecapRow(library: library, months: months)
                        Hairline()
                        yearRow(library: library, years: years)
                        trendingNow
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
                case .trend(let id): TrendDetailView(trendID: id)
                }
            }
            .momentDestination()
            .collectionDestinations()
        }
        .onAppear { analytics.track(.createOpened) }
        .task { await trends.refresh() }
    }

    // MARK: - Continue Editing

    private func continueEditing(_ draft: SavedCreation, count: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Continue Editing", route: .drafts, linkTitle: count > 1 ? "See All Drafts (\(count))" : "See All Drafts", linkIdentifier: "seeAllDrafts")
            ContinueEditingCard(draft: draft)
        }
    }

    // MARK: - Your Creations

    private var yourCreations: some View {
        let items = store.keptItems
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Your Creations", route: items.isEmpty ? nil : .creations, linkTitle: "See All", linkIdentifier: "seeAllCreations")
            if items.isEmpty {
                Text("Things you make with Relive will appear here.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("creationsEmpty")
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        ForEach(items.prefix(Self.recentCreations)) { item in
                            KeptItemLink(item: item, origin: "create", width: 128)
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Spacing.screenMargin)
                .accessibilityIdentifier("yourCreations")
            }
        }
    }

    /// How many recent creations Create shows before See All.
    private static let recentCreations = 8

    // MARK: - Favorites

    private func favoritesSection(library: CreationLibrary) -> some View {
        let photos = library.favoritePhotos
        let total = store.visibleFavoritesCount
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Favorites", route: total > 0 ? .favorites : nil, linkTitle: "See All", linkIdentifier: "seeAllFavorites")
            if total == 0 {
                Text("Favorite memories to keep them close and create from them later.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !photos.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(photos.suffix(4).reversed(), id: \.self) { id in
                            Color.clear
                                .aspectRatio(0.8, contentMode: .fit)
                                .overlay { AssetImageView(assetID: id) }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                        }
                    }
                    .frame(maxHeight: 120, alignment: .leading)
                    .accessibilityHidden(true)
                }
                Text("You have \(Counted.text(total, "favorite", "favorites")).")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("favoritesCount")
                if !photos.isEmpty {
                    CreateFromFavoritesMenu(origin: "create", style: .button)
                }
            }
        }
    }

    // MARK: - Trending Now

    @ViewBuilder
    private var trendingNow: some View {
        let visible = trends.visibleTrends()
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Trending Now")
                    .eyebrowStyle()
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Spacing.m) {
                        ForEach(visible, id: \.trend.id) { entry in
                            NavigationLink(value: CreateRoute.trend(entry.trend.id)) {
                                TrendCard(trend: entry.trend, availability: entry.availability)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("trendCard-\(entry.trend.id)")
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Spacing.screenMargin)
                .accessibilityIdentifier("trendingRow")
            }
        }
    }

    // MARK: - Memory Book

    private func bookFeature(library: CreationLibrary, months: [MonthKey], years: [Int]) -> some View {
        let cover = library.visibleMoments.last(where: { $0.kind != .undated }).flatMap(library.lead(of:))
        let hasTrips = !library.visibleTrips.isEmpty
        let hasFavorites = library.favoritePhotos.count >= BookLimits.minimumPhotos
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                BookCoverThumbnail(assetID: cover)
                    .frame(width: 96)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FeatureText(title: "Memory Book", subtitle: "Your memories, made into a book.")
                    Button("Start a Book") { choosesBookSource = true }
                        .buttonStyle(.reliveOutline)
                        .accessibilityIdentifier("createBook")
                }
            }
        }
        .confirmationDialog("Start a Memory Book from…", isPresented: $choosesBookSource, titleVisibility: .visible) {
            Button("A Moment") { app.startCreation(.book, from: .chooseMoment, origin: "create") }
            if hasTrips {
                Button("A Trip") { app.startCreation(.book, from: .chooseTrip, origin: "create") }
            }
            if !months.isEmpty {
                Button("A Month") { app.startCreation(.book, from: .chooseMonth, origin: "create") }
            }
            if !years.isEmpty {
                Button("A Year") { app.startCreation(.book, from: .chooseYear, origin: "create") }
            }
            if hasFavorites {
                Button("Favorites") { app.startCreation(.book, from: .source(.favorites), origin: "create") }
            }
            Button("Photos I Choose") { app.startCreation(.book, from: .choosePhotos, origin: "create") }
            Button("Cancel", role: .cancel) {}
        }
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

/// A small closed book: the cover photo with a spine shadow.
struct BookCoverThumbnail: View {
    let assetID: AssetID?

    var body: some View {
        Color.clear
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay { AssetImageView(assetID: assetID) }
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 6, x: 2, y: 4)
    }
}

/// "Continue Editing" / "Your Creations": a section title with an optional See All link.
private struct SectionHeader: View {
    let title: String
    let route: CollectionRoute?
    let linkTitle: String
    let linkIdentifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typography.title2)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.s)
            if let route {
                NavigationLink(value: route) {
                    Text(linkTitle)
                        .font(Typography.callout.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier(linkIdentifier)
            }
        }
    }
}

/// The latest draft, ready to pick up: its picture, "Story · Edited 12 minutes ago", Continue.
private struct ContinueEditingCard: View {
    let draft: SavedCreation

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @State private var confirmsDelete = false

    var body: some View {
        let summary = KeptSummary(item: .creation(draft), store: store)
        HStack(alignment: .top, spacing: Spacing.m) {
            Palette.surface
                .frame(width: 96, height: 120)
                .overlay { CreationPreview(item: .creation(draft)).padding(4) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(summary.title)
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                TimelineView(.everyMinute) { context in
                    Text("\(summary.kind.name) · \(EditedText.edited(draft.updatedAt, now: context.date))")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                if summary.missingCount > 0 {
                    Text(Counted.text(summary.missingCount, "photo is missing", "photos are missing"))
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
                Button("Continue") { app.resumeCreation(draft, origin: "create") }
                    .buttonStyle(.reliveOutline)
                    .accessibilityLabel("Continue editing \(summary.kind.name.lowercased()), \(summary.title)")
                    .accessibilityIdentifier("continueEditing")
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contextMenu {
            Button { app.resumeCreation(draft, origin: "create") } label: { Label("Continue Editing", systemImage: "pencil") }
            Button(role: .destructive) { confirmsDelete = true } label: { Label("Delete Draft", systemImage: "trash") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Delete Draft") { confirmsDelete = true }
        .confirmationDialog("Delete this draft?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Draft", role: .destructive) { store.deleteCreation(id: draft.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photos stay in Relive and in the Photos app.")
        }
    }
}
