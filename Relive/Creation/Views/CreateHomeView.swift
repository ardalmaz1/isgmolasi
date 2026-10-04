import ReliveCore
import SwiftUI

/// Navigation targets inside the Create tab.
enum CreateRoute: Hashable {
    case months
    case month(MonthKey)
    case years
    case year(Int)
    case trend(String)
    case book(UUID)
}

/// Create: Relive's creative studio. Trending Now (current, from the trend catalog) above the
/// permanent tools, each shown with the user's own photos.
/// "Choose memories. Relive makes something beautiful from them."
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

                    if library.visibleMoments.isEmpty {
                        QuietMessageView(
                            title: "Nothing to make from yet",
                            message: "Once your story has memories, you can turn them into collages, stories and recaps here."
                        )
                    } else {
                        trendingNow
                        Text("Create")
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
                case .book(let id): MemoryBookReaderView(bookID: id)
                }
            }
            .momentDestination()
        }
        .onAppear { analytics.track(.createOpened) }
        .task { await trends.refresh() }
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
            if !store.books.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Your books").eyebrowStyle()
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: Spacing.m) {
                            ForEach(store.books) { book in
                                NavigationLink(value: CreateRoute.book(book.id)) {
                                    BookShelfItem(book: book)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("savedBook")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
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

/// A saved book on the shelf.
private struct BookShelfItem: View {
    let book: MemoryBook

    @Environment(StoryStore.self) private var store

    var body: some View {
        let layout = BookLayoutEngine(library: store.creationLibrary(for: book)).layout(book)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            BookCoverThumbnail(assetID: layout.pages.first?.slots.first?.assetID)
                .frame(width: 110)
            Text(CreationText.title(layout.facts.title) ?? CreationText.periodLine(layout.facts.dateSpan) ?? "Memory Book")
                .font(Typography.footnote.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text("\(Counted.text(layout.photoIDs.count, "photo", "photos")) · \(book.style.displayName)")
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(width: 110, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the book")
    }
}
