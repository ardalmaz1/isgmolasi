import Foundation

/// The curated collage looks. Few, and each with its own arrangement — not a template library.
public enum CollageStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// Natural shapes, nothing cropped, lots of air.
    case minimal
    /// One large photo leads; the rest support it. A big serif title.
    case editorial
    /// Even rows with thin gutters.
    case grid
    /// Frames on strips of 35 mm film.
    case film
    /// Instant prints laid on a table.
    case polaroid
    /// Overlapping prints with tape.
    case scrapbook

    public var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .editorial: "Editorial"
        case .grid: "Grid"
        case .film: "Film"
        case .polaroid: "Polaroid"
        case .scrapbook: "Scrapbook"
        }
    }
}

/// Which caption lines a collage shows. The caption's content comes from `CreationFacts`.
public struct CollageCaptionSpec: Hashable, Sendable {
    public var showsTitle: Bool
    /// The date and/or place line.
    public var showsDetail: Bool

    public init(showsTitle: Bool, showsDetail: Bool) {
        self.showsTitle = showsTitle
        self.showsDetail = showsDetail
    }

    public static let none = CollageCaptionSpec(showsTitle: false, showsDetail: false)
    public var isEmpty: Bool { !showsTitle && !showsDetail }
}

/// Where one photo goes.
public struct CollageSlot: Hashable, Sendable {
    /// Index into the collage's ordered photos.
    public var photoIndex: Int
    /// Outer bounds, including any print border.
    public var frame: LayoutRect
    /// Where the photo itself is drawn (inside the border, if any).
    public var photoFrame: LayoutRect
    /// Degrees, clockwise, around the frame's center.
    public var rotation: Double
    /// A strip of tape across the top edge (Scrapbook).
    public var hasTape: Bool

    public init(photoIndex: Int, frame: LayoutRect, photoFrame: LayoutRect? = nil, rotation: Double = 0, hasTape: Bool = false) {
        self.photoIndex = photoIndex
        self.frame = frame
        self.photoFrame = photoFrame ?? frame
        self.rotation = rotation
        self.hasTape = hasTape
    }
}

/// A strip of film behind its frames.
public struct FilmStrip: Hashable, Sendable {
    public var frame: LayoutRect
    public var isVertical: Bool

    public init(frame: LayoutRect, isVertical: Bool) {
        self.frame = frame
        self.isVertical = isVertical
    }
}

/// A complete arrangement, in design points.
public struct CollageLayout: Hashable, Sendable {
    public var style: CollageStyle
    public var canvas: CanvasSize
    /// In drawing order (later slots are drawn on top).
    public var slots: [CollageSlot]
    public var caption: LayoutRect?
    public var filmStrips: [FilmStrip]
    /// Where the small "Made with Relive" mark goes, clear of photos and caption.
    public var watermark: LayoutRect
    /// The style's outer margin, used to size the caption and watermark type.
    public var margin: Double

    public init(
        style: CollageStyle,
        canvas: CanvasSize,
        slots: [CollageSlot],
        caption: LayoutRect?,
        filmStrips: [FilmStrip] = [],
        watermark: LayoutRect,
        margin: Double
    ) {
        self.style = style
        self.canvas = canvas
        self.slots = slots
        self.caption = caption
        self.filmStrips = filmStrips
        self.watermark = watermark
        self.margin = margin
    }

    /// The slot showing a given photo.
    public func slot(forPhoto index: Int) -> CollageSlot? {
        slots.first { $0.photoIndex == index }
    }
}

/// Spacing for each style, as fractions of the canvas width.
struct CollageStyleMetrics: Sendable {
    var margin: Double
    var gutter: Double
    var titleHeight: Double
    var detailHeight: Double
    var captionGap: Double
    var captionAtTop: Bool

    static func metrics(for style: CollageStyle) -> CollageStyleMetrics {
        switch style {
        case .minimal:
            CollageStyleMetrics(margin: 0.09, gutter: 0.022, titleHeight: 0.056, detailHeight: 0.034, captionGap: 0.045, captionAtTop: false)
        case .editorial:
            CollageStyleMetrics(margin: 0.06, gutter: 0.014, titleHeight: 0.1, detailHeight: 0.032, captionGap: 0.032, captionAtTop: true)
        case .grid:
            CollageStyleMetrics(margin: 0.035, gutter: 0.01, titleHeight: 0.05, detailHeight: 0.032, captionGap: 0.026, captionAtTop: false)
        case .film:
            CollageStyleMetrics(margin: 0.055, gutter: 0, titleHeight: 0.036, detailHeight: 0, captionGap: 0.03, captionAtTop: false)
        case .polaroid:
            CollageStyleMetrics(margin: 0.07, gutter: 0.04, titleHeight: 0.056, detailHeight: 0.034, captionGap: 0.03, captionAtTop: false)
        case .scrapbook:
            CollageStyleMetrics(margin: 0.07, gutter: 0, titleHeight: 0.06, detailHeight: 0.034, captionGap: 0.04, captionAtTop: false)
        }
    }
}

/// Arranges 2–12 photos on a canvas. Pure and deterministic: the same photos, style, canvas and
/// caption always give the same layout, which is what lets the preview and the export match.
///
/// Every arrangement accounts for each photo's shape (portrait, square, landscape): Minimal and
/// Polaroid keep natural shapes, Grid, Editorial and Scrapbook choose rows and slots that crop
/// the least, and Film runs its strips in the direction most photos were taken.
public struct CollageLayoutEngine: Sendable {
    public static let photoRange = 2...12

    public init() {}

    /// - Parameter photoAspects: width / height of each photo, in order. Unknown values count as square.
    public func layout(
        photoAspects: [Double],
        style: CollageStyle,
        canvas: CanvasSize,
        caption: CollageCaptionSpec
    ) -> CollageLayout {
        let aspects = photoAspects.map(CropMath.sanitizedAspect)
        let metrics = CollageStyleMetrics.metrics(for: style)
        let unit = canvas.width
        let margin = metrics.margin * unit
        let gutter = metrics.gutter * unit

        var area = LayoutRect(x: margin, y: margin, width: canvas.width - 2 * margin, height: canvas.height - 2 * margin)
        let captionRect = Self.reserveCaption(caption, metrics: metrics, unit: unit, area: &area)

        var strips: [FilmStrip] = []
        let slots: [CollageSlot]
        if aspects.isEmpty {
            slots = []
        } else {
            switch style {
            case .minimal:
                slots = Self.justified(aspects: aspects.map { min(2.4, max(0.5, $0)) }, in: area, gutter: gutter, maxRows: 6)
                    .enumerated().map { CollageSlot(photoIndex: $0.offset, frame: $0.element) }
            case .grid:
                slots = Self.rowGrid(aspects: aspects, in: area, gutter: gutter, maxColumns: 4, maxRows: 6).rects
                    .enumerated().map { CollageSlot(photoIndex: $0.offset, frame: $0.element) }
            case .editorial:
                slots = Self.editorial(aspects: aspects, in: area, gutter: gutter)
            case .film:
                let film = Self.film(aspects: aspects, in: area)
                slots = film.slots
                strips = film.strips
            case .polaroid:
                slots = Self.polaroid(aspects: aspects, in: area, gutter: gutter)
            case .scrapbook:
                slots = Self.scrapbook(aspects: aspects, in: area)
            }
        }

        let markHeight = max(14, min(26, margin * 0.6))
        let watermark = LayoutRect(
            x: canvas.width - margin - 360,
            y: canvas.height - margin / 2 - markHeight / 2,
            width: 360,
            height: markHeight
        )
        return CollageLayout(
            style: style,
            canvas: canvas,
            slots: slots,
            caption: captionRect,
            filmStrips: strips,
            watermark: watermark,
            margin: margin
        )
    }

    // MARK: - Caption

    private static func reserveCaption(
        _ caption: CollageCaptionSpec,
        metrics: CollageStyleMetrics,
        unit: Double,
        area: inout LayoutRect
    ) -> LayoutRect? {
        guard !caption.isEmpty else { return nil }
        var height: Double
        if metrics.detailHeight == 0 {
            // Single-line caption (Film): title and details share one line.
            height = metrics.titleHeight
        } else {
            height = (caption.showsTitle ? metrics.titleHeight : 0) + (caption.showsDetail ? metrics.detailHeight : 0)
            if caption.showsTitle && caption.showsDetail { height += 0.01 }
        }
        height *= unit
        let gap = metrics.captionGap * unit
        if metrics.captionAtTop {
            let rect = LayoutRect(x: area.x, y: area.y, width: area.width, height: height)
            area.y += height + gap
            area.height -= height + gap
            return rect
        } else {
            let rect = LayoutRect(x: area.x, y: area.maxY - height, width: area.width, height: height)
            area.height -= height + gap
            return rect
        }
    }

    // MARK: - Justified rows (no cropping)

    /// Rows that keep each photo's shape; the block is scaled to fit and centered. The number
    /// of rows is the one that makes the photos largest.
    static func justified(aspects: [Double], in area: LayoutRect, gutter: Double, maxRows: Int) -> [LayoutRect] {
        let count = aspects.count
        guard count > 0, area.width > 0, area.height > 0 else { return [] }

        var best: (rows: [[Double]], scale: Double, heights: [Double], coverage: Double)?
        for rowCount in 1...min(count, maxRows) {
            let rows = partition(aspects, into: rowCount)
            let heights = rows.map { row in
                (area.width - Double(row.count - 1) * gutter) / row.reduce(0, +)
            }
            let total = heights.reduce(0, +) + Double(rowCount - 1) * gutter
            let scale = min(1, area.height / total)
            var coverage = 0.0
            for (row, height) in zip(rows, heights) {
                for aspect in row {
                    let photoHeight = height * scale
                    coverage += photoHeight * photoHeight * aspect
                }
            }
            if best == nil || coverage > best!.coverage + 1e-6 {
                best = (rows, scale, heights, coverage)
            }
        }
        guard let chosen = best else { return [] }

        let scaledGutter = gutter * chosen.scale
        let blockWidth = area.width * chosen.scale
        let blockHeight = chosen.heights.reduce(0) { $0 + $1 * chosen.scale } + Double(chosen.rows.count - 1) * scaledGutter
        let originX = area.x + (area.width - blockWidth) / 2
        var y = area.y + (area.height - blockHeight) / 2

        var rects: [LayoutRect] = []
        for (row, height) in zip(chosen.rows, chosen.heights) {
            let rowHeight = height * chosen.scale
            var x = originX
            for aspect in row {
                let width = rowHeight * aspect
                rects.append(LayoutRect(x: x, y: y, width: width, height: rowHeight))
                x += width + scaledGutter
            }
            y += rowHeight + scaledGutter
        }
        return rects
    }

    /// Splits `values` into `parts` consecutive groups whose sums are as even as possible.
    static func partition(_ values: [Double], into parts: Int) -> [[Double]] {
        let count = values.count
        let parts = max(1, min(parts, count))
        guard parts > 1 else { return [values] }
        let target = values.reduce(0, +) / Double(parts)

        var prefix = [0.0]
        for value in values { prefix.append(prefix.last! + value) }
        func cost(_ start: Int, _ end: Int) -> Double {
            let sum = prefix[end] - prefix[start]
            return (sum - target) * (sum - target)
        }

        // best[k][i]: minimal cost of splitting the first i values into k groups.
        let infinity = Double.greatestFiniteMagnitude
        var best = Array(repeating: Array(repeating: infinity, count: count + 1), count: parts + 1)
        var split = Array(repeating: Array(repeating: 0, count: count + 1), count: parts + 1)
        best[0][0] = 0
        for k in 1...parts {
            for i in k...count {
                for j in (k - 1)..<i where best[k - 1][j] < infinity {
                    let candidate = best[k - 1][j] + cost(j, i)
                    if candidate < best[k][i] - 1e-12 {
                        best[k][i] = candidate
                        split[k][i] = j
                    }
                }
            }
        }

        var groups: [[Double]] = []
        var end = count
        for k in stride(from: parts, to: 0, by: -1) {
            let start = split[k][end]
            groups.insert(Array(values[start..<end]), at: 0)
            end = start
        }
        return groups
    }

    // MARK: - Rows of equal height (cropping as little as possible)

    /// Fills `area` with rows of equal height; rows may hold different numbers of photos.
    /// Chooses the row arrangement that crops the photos least (in their given order).
    static func rowGrid(
        aspects: [Double],
        in area: LayoutRect,
        gutter: Double,
        maxColumns: Int,
        maxRows: Int
    ) -> (rects: [LayoutRect], cost: Double) {
        let count = aspects.count
        guard count > 0, area.width > 0, area.height > 0 else { return ([], 0) }

        func evaluate(_ counts: [Int]) -> (rects: [LayoutRect], cost: Double) {
            let rowCount = counts.count
            let rowHeight = (area.height - Double(rowCount - 1) * gutter) / Double(rowCount)
            var rects: [LayoutRect] = []
            var cost = 0.0
            var index = 0
            var y = area.y
            for columns in counts {
                let cellWidth = (area.width - Double(columns - 1) * gutter) / Double(columns)
                var x = area.x
                for _ in 0..<columns {
                    let rect = LayoutRect(x: x, y: y, width: cellWidth, height: rowHeight)
                    cost += CropMath.cropLoss(imageAspect: aspects[index], frameAspect: rect.aspectRatio)
                    // Very thin slots read as slivers whatever the photo.
                    if rect.aspectRatio > 2.6 || rect.aspectRatio < 0.38 { cost += 0.5 }
                    rects.append(rect)
                    x += cellWidth + gutter
                    index += 1
                }
                y += rowHeight + gutter
            }
            return (rects, cost / Double(count))
        }

        var best: (rects: [LayoutRect], cost: Double)?
        for rowCount in 1...count {
            let counts = distribute(count, into: rowCount)
            guard counts.max()! <= maxColumns, rowCount <= maxRows else { continue }
            let candidate = evaluate(counts)
            if best == nil || candidate.cost < best!.cost - 1e-9 {
                best = candidate
            }
        }
        if let best { return best }
        let rowCount = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return evaluate(distribute(count, into: rowCount))
    }

    /// `count` items over `rows` rows, as evenly as possible; extra items go to the later rows so
    /// the first photos get the most room.
    static func distribute(_ count: Int, into rows: Int) -> [Int] {
        let rows = max(1, min(rows, count))
        let base = count / rows
        let extra = count % rows
        return (0..<rows).map { $0 >= rows - extra ? base + 1 : base }
    }

    // MARK: - Editorial

    /// The first photo leads, either as a tall column on the left or across the top — whichever
    /// crops it and the supporting photos least.
    static func editorial(aspects: [Double], in area: LayoutRect, gutter: Double) -> [CollageSlot] {
        let count = aspects.count
        if count == 1 {
            return [CollageSlot(photoIndex: 0, frame: area)]
        }
        let hero = aspects[0]
        let supports = Array(aspects.dropFirst())

        func arrangement(_ heroRect: LayoutRect, _ supportArea: LayoutRect, maxColumns: Int, maxRows: Int) -> (slots: [CollageSlot], cost: Double) {
            let grid = rowGrid(aspects: supports, in: supportArea, gutter: gutter, maxColumns: maxColumns, maxRows: maxRows)
            let heroCost = CropMath.cropLoss(imageAspect: hero, frameAspect: heroRect.aspectRatio)
            var slots = [CollageSlot(photoIndex: 0, frame: heroRect)]
            slots += grid.rects.enumerated().map { CollageSlot(photoIndex: $0.offset + 1, frame: $0.element) }
            return (slots, 1.6 * heroCost + grid.cost)
        }

        // Hero as a column on the left.
        let sideShare = count == 2 ? 0.56 : 0.6
        let heroWidth = (area.width - gutter) * sideShare
        let side = arrangement(
            LayoutRect(x: area.x, y: area.y, width: heroWidth, height: area.height),
            LayoutRect(x: area.x + heroWidth + gutter, y: area.y, width: area.width - heroWidth - gutter, height: area.height),
            maxColumns: 2,
            maxRows: 6
        )

        // Hero across the top.
        let topShare = count == 2 ? 0.56 : (count <= 4 ? 0.62 : 0.55)
        let heroHeight = (area.height - gutter) * topShare
        let top = arrangement(
            LayoutRect(x: area.x, y: area.y, width: area.width, height: heroHeight),
            LayoutRect(x: area.x, y: area.y + heroHeight + gutter, width: area.width, height: area.height - heroHeight - gutter),
            maxColumns: 4,
            maxRows: 3
        )

        return side.cost < top.cost - 1e-9 ? side.slots : top.slots
    }

    // MARK: - Film

    /// Contact-sheet strips. Strips run horizontally (landscape frames) unless most photos are
    /// portrait, in which case they run vertically (portrait frames).
    static func film(aspects: [Double], in area: LayoutRect) -> (slots: [CollageSlot], strips: [FilmStrip]) {
        let portraits = aspects.filter { PhotoOrientation(aspectRatio: $0).isPortrait }.count
        let landscapes = aspects.filter { PhotoOrientation(aspectRatio: $0).isLandscape }.count
        let vertical = portraits > landscapes
        if vertical {
            let transposed = LayoutRect(x: area.y, y: area.x, width: area.height, height: area.width)
            let result = horizontalFilm(count: aspects.count, in: transposed)
            func flip(_ rect: LayoutRect) -> LayoutRect {
                LayoutRect(x: rect.y, y: rect.x, width: rect.height, height: rect.width)
            }
            return (
                result.frames.enumerated().map { CollageSlot(photoIndex: $0.offset, frame: flip($0.element)) },
                result.strips.map { FilmStrip(frame: flip($0), isVertical: true) }
            )
        }
        let result = horizontalFilm(count: aspects.count, in: area)
        return (
            result.frames.enumerated().map { CollageSlot(photoIndex: $0.offset, frame: $0.element) },
            result.strips.map { FilmStrip(frame: $0, isVertical: false) }
        )
    }

    /// Proportions of 35 mm film, in units of the frame's short side.
    enum FilmProportions {
        static let frameLength = 1.5
        static let frameGap = 0.08
        static let stripEndPadding = 0.12
        static let sprocketBand = 0.17
        static let stripGap = 0.16
    }

    private static func horizontalFilm(count: Int, in area: LayoutRect) -> (frames: [LayoutRect], strips: [LayoutRect]) {
        typealias P = FilmProportions
        func length(_ frames: Int) -> Double {
            Double(frames) * P.frameLength + Double(max(0, frames - 1)) * P.frameGap + 2 * P.stripEndPadding
        }
        let thickness = 1 + 2 * P.sprocketBand

        var best: (strips: Int, perStrip: Int, unit: Double)?
        for strips in 1...count {
            let perStrip = Int((Double(count) / Double(strips)).rounded(.up))
            guard (strips - 1) * perStrip < count else { continue }
            let byWidth = area.width / length(perStrip)
            let byHeight = area.height / (Double(strips) * thickness + Double(strips - 1) * P.stripGap)
            let unit = min(byWidth, byHeight)
            if best == nil || unit > best!.unit + 1e-9 {
                best = (strips, perStrip, unit)
            }
        }
        guard let layout = best else { return ([], []) }

        let unit = layout.unit
        let blockWidth = length(layout.perStrip) * unit
        let blockHeight = (Double(layout.strips) * thickness + Double(layout.strips - 1) * P.stripGap) * unit
        let originX = area.x + (area.width - blockWidth) / 2
        var y = area.y + (area.height - blockHeight) / 2

        var frames: [LayoutRect] = []
        var strips: [LayoutRect] = []
        var remaining = count
        for _ in 0..<layout.strips {
            let inStrip = min(layout.perStrip, remaining)
            remaining -= inStrip
            strips.append(LayoutRect(x: originX, y: y, width: length(inStrip) * unit, height: thickness * unit))
            var x = originX + P.stripEndPadding * unit
            for _ in 0..<inStrip {
                frames.append(LayoutRect(x: x, y: y + P.sprocketBand * unit, width: P.frameLength * unit, height: unit))
                x += (P.frameLength + P.frameGap) * unit
            }
            y += (thickness + P.stripGap) * unit
        }
        return (frames, strips)
    }

    // MARK: - Polaroid

    /// Window shape of an instant print for a photo of the given shape.
    static func polaroidWindowAspect(for aspect: Double) -> Double {
        switch PhotoOrientation(aspectRatio: aspect) {
        case .portrait: 0.78
        case .square: 1
        case .landscape, .panorama: 1.42
        }
    }

    /// Border widths of a print, as fractions of the window's shorter side.
    enum PolaroidProportions {
        static let side = 0.075
        static let bottom = 0.3
    }

    static func polaroidFrameAspect(window: Double) -> Double {
        let width = 1.0
        let height = 1 / window
        let border = PolaroidProportions.side * min(width, height)
        let bottom = PolaroidProportions.bottom * min(width, height)
        return (width + 2 * border) / (height + border + bottom)
    }

    static let gentleRotations: [Double] = [-2.4, 1.8, -1.1, 2.6, -2.9, 0.9, 2.1, -1.7, 0.7, -2.2, 3.0, -0.8]

    static func polaroid(aspects: [Double], in area: LayoutRect, gutter: Double) -> [CollageSlot] {
        let windows = aspects.map(polaroidWindowAspect(for:))
        let frames = justified(aspects: windows.map(polaroidFrameAspect(window:)), in: area, gutter: gutter, maxRows: 5)
        return frames.enumerated().map { index, rect in
            let frame = rect.scaled(by: 0.9)
            let window = windows[index]
            let windowWidth = frame.width / (1 + 2 * PolaroidProportions.side * min(1, 1 / window))
            let border = (frame.width - windowWidth) / 2
            let photo = LayoutRect(x: frame.x + border, y: frame.y + border, width: windowWidth, height: windowWidth / window)
            return CollageSlot(
                photoIndex: index,
                frame: frame,
                photoFrame: photo,
                rotation: gentleRotations[index % gentleRotations.count]
            )
        }
    }

    // MARK: - Scrapbook

    static let scrapbookRotations: [Double] = [-4.5, 3.5, -2.0, 5.0, -3.5, 2.5, -5.0, 1.5, 4.0, -1.5, 3.0, -4.0]
    static let scrapbookJitter: [(Double, Double)] = [
        (0.4, -0.3), (-0.5, 0.4), (0.3, 0.5), (-0.2, -0.5), (0.5, 0.2), (-0.4, -0.2),
        (0.2, 0.4), (-0.3, 0.3), (0.4, -0.4), (-0.5, -0.1), (0.1, 0.5), (-0.2, 0.2),
    ]

    /// Prints in a loose grid, enlarged so neighbours overlap a little, turned and taped. The
    /// first photo is drawn last so it sits on top.
    static func scrapbook(aspects: [Double], in area: LayoutRect) -> [CollageSlot] {
        let cells = rowGrid(aspects: aspects, in: area, gutter: 0, maxColumns: 3, maxRows: 5).rects
        var slots: [CollageSlot] = []
        for (index, cell) in cells.enumerated() {
            let jitter = scrapbookJitter[index % scrapbookJitter.count]
            let rotation = scrapbookRotations[index % scrapbookRotations.count]
            var frame = cell.scaled(by: 0.94).offsetBy(dx: jitter.0 * cell.width * 0.06, dy: jitter.1 * cell.height * 0.06)
            frame = fit(frame, rotation: rotation, inside: area)
            let border = 0.035 * min(frame.width, frame.height)
            slots.append(CollageSlot(
                photoIndex: index,
                frame: frame,
                photoFrame: frame.insetBy(dx: border, dy: border),
                rotation: rotation,
                hasTape: index.isMultiple(of: 2) || aspects.count <= 3
            ))
        }
        return slots.reversed()
    }

    /// Moves (and if necessary shrinks) `rect` so that, rotated, it stays inside `bounds`.
    static func fit(_ rect: LayoutRect, rotation: Double, inside bounds: LayoutRect) -> LayoutRect {
        var result = rect
        var rotated = result.rotatedBounds(degrees: rotation)
        if rotated.width > bounds.width || rotated.height > bounds.height {
            let factor = min(bounds.width / rotated.width, bounds.height / rotated.height)
            result = result.scaled(by: factor)
            rotated = result.rotatedBounds(degrees: rotation)
        }
        var dx = 0.0, dy = 0.0
        if rotated.minX < bounds.minX { dx = bounds.minX - rotated.minX }
        if rotated.maxX > bounds.maxX { dx = bounds.maxX - rotated.maxX }
        if rotated.minY < bounds.minY { dy = bounds.minY - rotated.minY }
        if rotated.maxY > bounds.maxY { dy = bounds.maxY - rotated.maxY }
        return result.offsetBy(dx: dx, dy: dy)
    }
}
