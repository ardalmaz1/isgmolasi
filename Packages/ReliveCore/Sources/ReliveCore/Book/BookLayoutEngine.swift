import Foundation

public enum BookPageKind: String, Hashable, Sendable {
    /// The book's cover: one photo, the title, the dates.
    case cover
    /// The user's own words for the whole book.
    case bookNote
    /// A typographic page introducing a trip inside a longer book.
    case tripTitle
    /// A moment (or a day) begins: its name, date and place, with its first photo.
    case opener
    /// A note the user wrote on a moment.
    case momentNote
    /// One to four photos.
    case photos
    /// The last page: the book's title and dates.
    case closing
}

/// How the photos on a page are arranged.
public enum BookPhotoTemplate: String, Hashable, Sendable {
    /// One photo filling the page (cropped to fill). Used for portrait and square photos.
    case fullBleed
    /// One photo in its own shape, with white space. Used for landscape photos.
    case single
    /// Two photos of the same orientation, side by side (portraits) or stacked (landscapes).
    case pair
    /// A portrait and a landscape: the portrait large, the landscape smaller beside it.
    case feature
    case trio
    case quad
}

public struct BookPhotoSlot: Hashable, Sendable {
    public var assetID: AssetID
    /// Where the photo is drawn, in page design points.
    public var frame: LayoutRect

    public init(assetID: AssetID, frame: LayoutRect) {
        self.assetID = assetID
        self.frame = frame
    }
}

/// One page of a laid-out book. Text is described by facts; the app formats and draws it.
public struct BookPage: Hashable, Sendable, Identifiable {
    public var id: Int
    public var kind: BookPageKind
    public var template: BookPhotoTemplate?
    public var slots: [BookPhotoSlot]
    public var title: CreationTitle?
    public var dateSpan: DateSpan?
    public var place: PlaceName?
    /// The user's own words (book note or moment note).
    public var text: String?
    /// Where the title block goes, for pages that have one.
    public var textFrame: LayoutRect?
    /// The section this page belongs to, for the running footer ("Kekova · August 7").
    public var runningTitle: CreationTitle?
    public var runningDate: DateSpan?
    /// The printed page number; the cover has none.
    public var folio: Int?

    public var photoIDs: [AssetID] { slots.map(\.assetID) }
}

/// A book, paginated.
public struct BookLayout: Hashable, Sendable {
    public var bookID: UUID
    public var style: BookStyle
    public var pageSize: CanvasSize
    public var pages: [BookPage]
    public var facts: CreationFacts
    /// The photos still in the library, in reading order.
    public var photoIDs: [AssetID]
    /// Photos of the book that are no longer in the library (deleted, access removed).
    public var missingAssetIDs: [AssetID]

    /// The cover alone, then facing pairs of pages — the shape a printed book takes.
    public var spreads: [[Int]] {
        guard let first = pages.first else { return [] }
        var result = [[first.id]]
        var index = 1
        while index < pages.count {
            result.append(Array(pages[index..<min(index + 2, pages.count)].map(\.id)))
            index += 2
        }
        return result
    }
}

/// Spacing of each book style, as fractions of the page width.
struct BookStyleMetrics: Sendable {
    var margin: Double
    var gutter: Double
    var footer: Double
    /// Inset of a full-bleed photo from the page edge (0 = edge to edge).
    var bleedInset: Double

    static func metrics(for style: BookStyle) -> BookStyleMetrics {
        switch style {
        case .classic: BookStyleMetrics(margin: 0.1, gutter: 0.024, footer: 0.05, bleedInset: 0.055)
        case .editorial: BookStyleMetrics(margin: 0.065, gutter: 0.012, footer: 0.045, bleedInset: 0)
        case .film: BookStyleMetrics(margin: 0.09, gutter: 0.03, footer: 0.05, bleedInset: 0.09)
        }
    }
}

/// Paginates a `MemoryBook` deterministically.
///
/// - Photos stay in the book's order. A new moment (or day) gets an opening page with its real
///   name, date and place; a trip inside a longer book gets a title page. Photos from outside the
///   story are grouped by their own capture day. Nothing is inherited from a neighbouring photo.
/// - Which photos share a page depends on the photos: the section's strongest photo gets a page
///   of its own, landscapes pair up, portraits gather in threes and fours, and no lone photo is
///   left over when another split avoids it. Portrait photos alone fill the page; landscapes keep
///   their shape; a portrait and a landscape make an asymmetric spread.
/// - Each page's footer carries the dates of the photos on that page.
/// - The pagination doesn't depend on the style; only the geometry does. Changing the style
///   never moves a photo to another page.
public struct BookLayoutEngine: Sendable {
    public static let pageSize = CreationAspectRatio.portrait.designSize
    /// A section this long gets one photo on a page of its own.
    static let heroThreshold = 5

    public var library: CreationLibrary

    public init(library: CreationLibrary) {
        self.library = library
    }

    public func layout(_ book: MemoryBook) -> BookLayout {
        var seen = Set<AssetID>()
        let unique = book.photoIDs.filter { seen.insert($0).inserted }
        let usable = unique.filter(library.isUsable)
        let missing = unique.filter { !library.isUsable($0) }
        let facts = library.facts(for: book.source, photos: usable)
        let metrics = BookStyleMetrics.metrics(for: book.style)
        let size = Self.pageSize

        var pages: [BookPage] = []
        func add(_ page: BookPage) {
            var page = page
            page.id = pages.count
            page.folio = page.kind == .cover ? nil : pages.count
            pages.append(page)
        }

        // Cover
        let coverID = book.coverAssetID.flatMap { usable.contains($0) ? $0 : nil } ?? library.best(usable)
        var cover = BookPage(id: 0, kind: .cover, slots: [], title: facts.title, dateSpan: facts.dateSpan, place: facts.place)
        if let coverID {
            let geometry = coverGeometry(style: book.style, aspect: aspect(of: coverID), metrics: metrics)
            cover.slots = [BookPhotoSlot(assetID: coverID, frame: geometry.photo)]
            cover.textFrame = geometry.text
        }
        add(cover)

        if let note = book.trimmedNote {
            add(BookPage(id: 0, kind: .bookNote, slots: [], text: note, textFrame: textPageFrame(metrics)))
        }

        let sections = self.sections(for: book, photos: usable)
        let isSingleSection = sections.count <= 1
        var previousCount = 0
        var announcedTrips = Set<UUID>()
        let sectionsPerTrip = Dictionary(grouping: sections.compactMap(\.tripID), by: { $0 }).mapValues(\.count)

        if isSingleSection, book.includesMomentNotes, let note = sections.first?.note {
            add(BookPage(id: 0, kind: .momentNote, slots: [], title: sections.first?.title, text: note, textFrame: textPageFrame(metrics)))
        }

        for section in sections {
            var photos = section.photos
            guard !photos.isEmpty else { continue }
            // The book's title covers every page of a one-section book; otherwise the section's.
            let running = isSingleSection ? facts.title : section.title

            // A trip inside a longer book gets its own title page, once.
            if let tripID = section.tripID, !isTripBook(book), (sectionsPerTrip[tripID] ?? 0) > 1,
               announcedTrips.insert(tripID).inserted, let chapter = library.story.chapter(id: tripID) {
                let tripFacts = library.facts(for: chapter)
                add(BookPage(
                    id: 0, kind: .tripTitle, slots: [], title: tripFacts.title, dateSpan: tripFacts.dateSpan,
                    place: tripFacts.place, textFrame: textPageFrame(metrics)
                ))
            }

            // An opening page only when there is something true to say about the section.
            if !isSingleSection, section.title != nil || section.dateSpan != nil {
                let first = photos.removeFirst()
                let geometry = openerGeometry(aspect: aspect(of: first), metrics: metrics)
                add(BookPage(
                    id: 0, kind: .opener, template: .single,
                    slots: [BookPhotoSlot(assetID: first, frame: geometry.photo)],
                    title: section.title, dateSpan: section.dateSpan, place: section.place,
                    textFrame: geometry.text, runningTitle: running, runningDate: library.metadata(of: [first]).dateSpan
                ))
                if book.includesMomentNotes, let note = section.note {
                    add(BookPage(id: 0, kind: .momentNote, slots: [], title: section.title, text: note, textFrame: textPageFrame(metrics)))
                }
            }

            for chunk in pagePlan(photos, previousCount: &previousCount) {
                let arranged = photoPage(chunk, style: book.style, metrics: metrics)
                add(BookPage(
                    id: 0, kind: .photos, template: arranged.template, slots: arranged.slots,
                    runningTitle: running, runningDate: library.metadata(of: chunk).dateSpan
                ))
            }
        }

        add(BookPage(id: 0, kind: .closing, slots: [], title: facts.title, dateSpan: facts.dateSpan, place: facts.place, textFrame: textPageFrame(metrics)))

        return BookLayout(
            bookID: book.id,
            style: book.style,
            pageSize: size,
            pages: pages,
            facts: facts,
            photoIDs: usable,
            missingAssetIDs: missing
        )
    }

    // MARK: - Sections

    struct Section {
        var title: CreationTitle?
        var dateSpan: DateSpan?
        var place: PlaceName?
        var note: String?
        var tripID: UUID?
        var photos: [AssetID]
    }

    private func isTripBook(_ book: MemoryBook) -> Bool {
        if case .trip = book.source { return true }
        return false
    }

    /// Consecutive photos of the same moment form a section; in a book of one moment, each day
    /// does. Photos from outside the story form sections by their own capture day. Every value
    /// comes from the section's own photos — a photo never takes on its neighbour's name or date.
    func sections(for book: MemoryBook, photos: [AssetID]) -> [Section] {
        let byDay: Bool
        if case .moment = book.source { byDay = true } else { byDay = false }

        var sections: [Section] = []
        var currentKey: String?
        for id in photos {
            let asset = library.creationAsset(id)
            let moment = asset?.momentID.flatMap { library.story.moment(id: $0) }
            let dayKey = asset?.creationDate.map { date -> String in
                let day = library.calendar.dateComponents([.year, .month, .day], from: date)
                return "day-\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
            } ?? "undated"
            let key: String
            if let moment, !byDay {
                key = "moment-\(moment.id.uuidString)"
            } else {
                key = dayKey
            }

            if key != currentKey || sections.isEmpty {
                currentKey = key
                var section = Section(photos: [])
                if let moment {
                    if byDay {
                        section.place = asset?.place
                        section.note = note(of: moment)
                    } else {
                        let facts = library.facts(for: moment)
                        section.title = facts.title
                        section.place = facts.place
                        section.note = note(of: moment)
                        section.tripID = moment.chapterID
                    }
                }
                sections.append(section)
            }
            sections[sections.count - 1].photos.append(id)
        }

        for index in sections.indices {
            // Dates span the photos actually in each section, and only when they all have one.
            sections[index].dateSpan = library.metadata(of: sections[index].photos).dateSpan
        }
        // A name already used earlier in the book ("September Evening" twice) gives way to the
        // section's own date, so generic titles don't repeat.
        var usedTitles = Set<CreationTitle>()
        for index in sections.indices {
            if let title = sections[index].title, !usedTitles.insert(title).inserted {
                sections[index].title = nil
            }
        }
        // In a one-moment book every day shares the moment's note; print it once (single-section
        // books print it after the cover).
        if byDay, sections.count > 1 {
            for index in sections.indices.dropFirst() { sections[index].note = nil }
        }
        return sections
    }

    // MARK: - Pages

    /// Splits a section's photos into pages, keeping their order:
    /// - in a long section, its strongest photo gets a page of its own (chosen where it leaves
    ///   no lone photo beside it);
    /// - two landscapes share a page (they stack well on a tall page);
    /// - portraits gather in fours, or threes, varying with the page before;
    /// - no single photo is left over when another split avoids it.
    func pagePlan(_ photos: [AssetID], previousCount: inout Int) -> [[AssetID]] {
        let hero = heroCandidate(in: photos)
        var pages: [[AssetID]] = []
        var queue = photos[...]
        while let first = queue.first {
            if first == hero {
                pages.append([first])
                queue = queue.dropFirst()
                previousCount = 1
                continue
            }
            let run = Array(queue.prefix { $0 != hero })
            let shapes = run.prefix(4).map { PhotoOrientation(aspectRatio: aspect(of: $0)) }
            let count = Self.photosPerPage(shapes: shapes, remaining: run.count, previous: previousCount)
            pages.append(Array(queue.prefix(count)))
            queue = queue.dropFirst(count)
            previousCount = count
        }
        return pages
    }

    /// How many of the next photos share a page.
    static func photosPerPage(shapes: [PhotoOrientation], remaining: Int, previous: Int) -> Int {
        guard remaining > 2, shapes.count >= 3 else { return remaining }
        var count: Int
        if shapes[0].isLandscape && shapes[1].isLandscape {
            count = 2
        } else if remaining >= 4, shapes.prefix(4).allSatisfy({ !$0.isLandscape }), previous != 4 {
            count = 4
        } else if previous != 3, shapes.prefix(3).filter(\.isLandscape).count <= 1 {
            count = 3
        } else {
            count = 2
        }
        // Never leave one photo on its own at the end.
        if remaining - count == 1 { count = count > 2 ? count - 1 : count + 1 }
        return min(count, remaining)
    }

    /// The section's strongest photo, where giving it a page leaves no lone photo before or
    /// after it.
    private func heroCandidate(in photos: [AssetID]) -> AssetID? {
        guard photos.count >= Self.heroThreshold else { return nil }
        let allowed = photos.indices.filter { index in
            let before = index, after = photos.count - index - 1
            return before != 1 && after != 1
        }
        return library.best(allowed.map { photos[$0] }) ?? library.best(photos)
    }

    private func note(of moment: Moment) -> String? {
        guard let note = library.userStates[moment.id]?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }

    // MARK: - Geometry

    func aspect(of id: AssetID) -> Double {
        CropMath.sanitizedAspect(library.assets[id]?.aspectRatio ?? 1)
    }

    private func contentArea(_ metrics: BookStyleMetrics) -> LayoutRect {
        let size = Self.pageSize
        let margin = metrics.margin * size.width
        let footer = metrics.footer * size.width
        return LayoutRect(x: margin, y: margin, width: size.width - 2 * margin, height: size.height - 2 * margin - footer)
    }

    private func textPageFrame(_ metrics: BookStyleMetrics) -> LayoutRect {
        let size = Self.pageSize
        let margin = metrics.margin * size.width * 1.4
        return LayoutRect(x: margin, y: margin, width: size.width - 2 * margin, height: size.height - 2 * margin)
    }

    func photoPage(_ photos: [AssetID], style: BookStyle, metrics: BookStyleMetrics) -> (template: BookPhotoTemplate, slots: [BookPhotoSlot]) {
        let area = contentArea(metrics)
        let gutter = metrics.gutter * Self.pageSize.width
        let aspects = photos.map(aspect(of:))
        let template: BookPhotoTemplate
        let frames: [LayoutRect]
        switch photos.count {
        case 1:
            if aspects[0] <= 1.05 {
                template = .fullBleed
                let inset = metrics.bleedInset * Self.pageSize.width
                // Edge to edge when the style bleeds; otherwise a large print that leaves the
                // running footer clear.
                let footer = inset > 0 ? metrics.footer * Self.pageSize.width : 0
                frames = [LayoutRect(x: inset, y: inset, width: Self.pageSize.width - 2 * inset, height: Self.pageSize.height - 2 * inset - footer)]
            } else {
                template = .single
                frames = CollageLayoutEngine.justified(aspects: aspects.map { min(2.4, $0) }, in: area, gutter: gutter, maxRows: 1)
            }
        case 2 where PhotoOrientation(aspectRatio: aspects[0]).isLandscape != PhotoOrientation(aspectRatio: aspects[1]).isLandscape:
            template = .feature
            frames = featureFrames(aspects: aspects, in: area, gutter: gutter)
        case 2:
            template = .pair
            frames = CollageLayoutEngine.justified(aspects: aspects.map { min(2.4, max(0.5, $0)) }, in: area, gutter: gutter, maxRows: 2)
        case 3:
            template = .trio
            frames = CollageLayoutEngine.editorial(aspects: aspects, in: area, gutter: gutter)
                .sorted { $0.photoIndex < $1.photoIndex }
                .map(\.frame)
        default:
            template = .quad
            frames = CollageLayoutEngine.rowGrid(aspects: aspects, in: area, gutter: gutter, maxColumns: 2, maxRows: 3).rects
        }
        return (template, zip(photos, frames).map { BookPhotoSlot(assetID: $0, frame: $1) })
    }

    /// A portrait and a landscape, neither cropped: the portrait large in one column, the
    /// landscape smaller in the other, aligned to the portrait's foot (or head, when it comes
    /// first in the book), leaving deliberate white space.
    func featureFrames(aspects: [Double], in area: LayoutRect, gutter: Double) -> [LayoutRect] {
        let portraitIndex = PhotoOrientation(aspectRatio: aspects[0]).isLandscape ? 1 : 0
        let portraitAspect = min(1.0, max(0.5, aspects[portraitIndex]))
        let landscapeAspect = min(2.4, max(1.0, aspects[1 - portraitIndex]))

        var bigWidth = area.width * 0.6
        var bigHeight = bigWidth / portraitAspect
        if bigHeight > area.height {
            bigHeight = area.height
            bigWidth = bigHeight * portraitAspect
        }
        let smallWidth = area.width - bigWidth - gutter
        let smallHeight = smallWidth / landscapeAspect
        let bigY = area.y + (area.height - bigHeight) / 2

        let big: LayoutRect
        let small: LayoutRect
        if portraitIndex == 0 {
            // Portrait first: on the left; the landscape follows, low on the right.
            big = LayoutRect(x: area.x, y: bigY, width: bigWidth, height: bigHeight)
            small = LayoutRect(x: big.maxX + gutter, y: big.maxY - smallHeight, width: smallWidth, height: smallHeight)
        } else {
            // Landscape first: high on the left; the portrait follows on the right.
            small = LayoutRect(x: area.x, y: bigY, width: smallWidth, height: smallHeight)
            big = LayoutRect(x: small.maxX + gutter, y: bigY, width: bigWidth, height: bigHeight)
        }
        return portraitIndex == 0 ? [big, small] : [small, big]
    }

    private func openerGeometry(aspect: Double, metrics: BookStyleMetrics) -> (photo: LayoutRect, text: LayoutRect) {
        let area = contentArea(metrics)
        let textHeight = Self.pageSize.width * 0.24
        let gap = Self.pageSize.width * 0.04
        let text = LayoutRect(x: area.x, y: area.y, width: area.width, height: textHeight)
        let photoArea = LayoutRect(x: area.x, y: area.y + textHeight + gap, width: area.width, height: area.height - textHeight - gap)
        let photo = CollageLayoutEngine.justified(aspects: [min(2.4, max(0.5, aspect))], in: photoArea, gutter: 0, maxRows: 1).first ?? photoArea
        return (photo, text)
    }

    private func coverGeometry(style: BookStyle, aspect: Double, metrics: BookStyleMetrics) -> (photo: LayoutRect, text: LayoutRect) {
        let size = Self.pageSize
        let margin = metrics.margin * size.width
        switch style {
        case .editorial:
            // The photo fills the cover; the title sits over its top.
            return (
                LayoutRect(x: 0, y: 0, width: size.width, height: size.height),
                LayoutRect(x: margin, y: margin, width: size.width - 2 * margin, height: size.height * 0.3)
            )
        case .classic, .film:
            let photoArea = LayoutRect(x: margin, y: margin * 1.2, width: size.width - 2 * margin, height: size.height * 0.6)
            let photo: LayoutRect
            if style == .classic {
                photo = CollageLayoutEngine.justified(aspects: [min(2.4, max(0.5, aspect))], in: photoArea, gutter: 0, maxRows: 1).first ?? photoArea
            } else {
                photo = photoArea
            }
            let textTop = photoArea.maxY + size.width * 0.05
            return (photo, LayoutRect(x: margin, y: textTop, width: size.width - 2 * margin, height: size.height - textTop - margin))
        }
    }
}
