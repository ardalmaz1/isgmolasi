import Foundation

// Memory Movie V1: a short, automatically edited film of a real period, made from still photos.
// The plan is renderer-independent (no AVFoundation, no pixels) and deterministic; the app's
// preview and its exporter both draw it through `MovieTimeline`, so what plays is what exports.

/// The movie's shape.
public enum MovieAspect: String, CaseIterable, Codable, Hashable, Sendable {
    /// Tall, for phones and Stories. The default.
    case portrait = "9:16"
    /// Wide, for watching on a TV or laptop.
    case landscape = "16:9"

    /// The exported frame size, in pixels.
    public var renderSize: CanvasSize {
        switch self {
        case .portrait: CanvasSize(width: 1080, height: 1920)
        case .landscape: CanvasSize(width: 1920, height: 1080)
        }
    }

    /// Width / height.
    public var ratio: Double { renderSize.aspectRatio }

    public var name: String { rawValue }
}

/// How long the movie is meant to be. The planner never pads to reach a length: a source with
/// eleven good photos stays eleven photos long.
public enum MovieLength: String, CaseIterable, Codable, Hashable, Sendable {
    case short
    case standard
    case long

    /// The duration the movie aims for, in seconds.
    public var seconds: ClosedRange<Double> {
        switch self {
        case .short: 15...25
        case .standard: 30...45
        case .long: 45...60
        }
    }

    /// At most this many photos (scenes) are chosen automatically.
    public var sceneCap: Int {
        switch self {
        case .short: 9
        case .standard: 15
        case .long: 22
        }
    }

    /// A normal photo's time on screen before rhythm adjustments.
    var baseSceneSeconds: Double {
        switch self {
        case .short: 2.4
        case .standard: 2.8
        case .long: 2.9
        }
    }

    public var name: String {
        switch self {
        case .short: "Short"
        case .standard: "Standard"
        case .long: "Long"
        }
    }
}

/// A look for the whole film. Every style draws the same plan and the same facts; a style only
/// changes typography, text placement, rhythm, motion preference and background treatment.
public enum MovieStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// Serif titles, gentle motion, crossfades.
    case classic
    /// Small caps, more stillness, a slower rhythm, text set low.
    case editorial
    /// Warm grade, slow pans, a few hard cuts inside a moment.
    case film
    /// Soft and bright, gentle zooms.
    case warm

    public var name: String {
        switch self {
        case .classic: "Classic"
        case .editorial: "Editorial"
        case .film: "Film"
        case .warm: "Warm"
        }
    }

    /// Scene time multiplier.
    var rhythm: Double {
        switch self {
        case .classic: 1.0
        case .editorial: 1.1
        case .film: 1.0
        case .warm: 1.05
        }
    }
}

/// Restrained movement for a still photo. Slow by design: the photo is the point.
public enum MovieMotion: String, CaseIterable, Codable, Hashable, Sendable {
    case still
    case zoomIn
    case zoomOut
    /// The view travels left across the photo.
    case panLeft
    /// The view travels right across the photo.
    case panRight
    case panUp
    case panDown

    var isPan: Bool { [.panLeft, .panRight, .panUp, .panDown].contains(self) }
    var isZoom: Bool { self == .zoomIn || self == .zoomOut }
}

/// How a scene arrives. Editorial, never a gimmick.
public enum MovieTransition: String, CaseIterable, Codable, Hashable, Sendable {
    case cut
    /// The new photo dissolves over the previous one.
    case crossfade
    /// The previous photo fades to black, the new one fades in (a new day, month or place).
    case fadeThroughBlack
}

/// How a photo sits in the frame.
public enum MovieFraming: String, Codable, Hashable, Sendable {
    /// It fills the frame; only a little of its edges is cropped.
    case fill
    /// The whole photo, over a softened, darkened copy of itself — when filling would crop
    /// too much (a landscape photo in a tall movie). No content is ever invented.
    case fit
}

/// Sound for a movie. V1 is silent: Relive ships no music, downloads none and connects to no
/// music service. Future bundled, properly licensed tracks would add cases here and an audio
/// input to the renderer; the plan and the edit stay the same.
public enum MovieSoundtrack: String, CaseIterable, Codable, Hashable, Sendable {
    case silent
}

/// Words on screen. Facts only, from the factual title system; never a feeling.
public struct MovieText: Hashable, Codable, Sendable {
    public var eyebrow: String?
    public var title: String
    public var detail: String?

    public init(eyebrow: String? = nil, title: String, detail: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var all: [String] { [eyebrow, title, detail].compactMap { $0 } }
}

/// One photo on screen.
public struct MovieScene: Hashable, Codable, Sendable, Identifiable {
    public enum Role: String, Codable, Hashable, Sendable {
        /// The first photo, under the title.
        case opening
        case body
        /// The first photo of a new section (day, place, month, year).
        case sectionOpener
        /// The last photo, under the closing words.
        case closing
    }

    /// The photo's identifier (one scene per photo).
    public var id: AssetID { assetID }
    public var assetID: AssetID
    public var role: Role
    /// Seconds on screen, including the part that overlaps a crossfade.
    public var duration: Double
    public var motion: MovieMotion
    public var framing: MovieFraming
    /// The point kept in view when filling (faces sit in the upper middle of most photos).
    public var focus: FocusPoint
    /// The photo's own width / height (1 when unknown).
    public var imageAspect: Double
    /// How this scene arrives. The first scene always fades in from black.
    public var transition: MovieTransition
    public var transitionDuration: Double
    public var text: MovieText?
    /// Which section of the film it belongs to (0 = the opening).
    public var sectionIndex: Int
}

/// The choices a person can make about a movie. Everything else follows from the plan.
public struct MovieSettings: Hashable, Codable, Sendable {
    public var aspect: MovieAspect
    public var length: MovieLength
    public var style: MovieStyle
    public var showsText: Bool
    /// "Make it for me" again: a different but still reasonable cut (0 = Relive's first choice).
    public var variation: Int

    public init(aspect: MovieAspect = .portrait, length: MovieLength = .standard, style: MovieStyle = .classic, showsText: Bool = true, variation: Int = 0) {
        self.aspect = aspect
        self.length = length
        self.style = style
        self.showsText = showsText
        self.variation = variation
    }
}

/// The edit: which photos, in what order, for how long, how they move and arrive, and the few
/// words on screen. Identifiers and facts only — no pixels, notes or coordinates.
public struct MoviePlan: Hashable, Codable, Sendable {
    public enum Status: Hashable, Codable, Sendable {
        case ready
        /// Fewer distinct, usable photos than a movie needs.
        case insufficient(available: Int, required: Int)
    }

    public var source: CreationSource
    public var status: Status
    public var settings: MovieSettings
    /// What the movie may call itself (a moment, a trip, a place, a period — or "Our Memories").
    public var title: FactualTitle
    /// "August 2025", when every photo is dated.
    public var periodLabel: String?
    public var scenes: [MovieScene]
    /// The user chose these photos (or edited the cut): they are kept as they are.
    public var isUserCut: Bool
    public var limitations: [MemorySelectionPlan.Limitation]
    /// Always silent in V1.
    public var soundtrack: MovieSoundtrack = .silent
    /// Memories considered.
    public var sourceCount: Int
    public var duplicatesRemoved: Int
    public var similarCollapsed: Int

    public var isReady: Bool { status == .ready }
    public var photoIDs: [AssetID] { scenes.map(\.assetID) }
    /// The opening photo.
    public var cover: AssetID? { scenes.first?.assetID }
    /// Running time in seconds (crossfades overlap neighbouring scenes).
    public var duration: Double { MovieTimeline(plan: self).duration }

    /// One DEBUG line: counts, kinds and settings — no identifiers, titles, places or dates.
    public var diagnosticsLine: String {
        "movie_plan source=\(source.kindCode) sourceCount=\(sourceCount) selected=\(scenes.count)"
            + " duration=\(String(format: "%.1f", duration)) aspect=\(settings.aspect.rawValue) style=\(settings.style.rawValue)"
            + " length=\(settings.length.rawValue) scenes=\(scenes.count) sections=\(Set(scenes.map(\.sectionIndex)).count)"
            + " duplicatesRemoved=\(duplicatesRemoved) similarCollapsed=\(similarCollapsed)"
            + " fit=\(scenes.filter { $0.framing == .fit }.count) userCut=\(isUserCut)"
            + (isReady ? "" : " status=insufficient")
    }
}

/// When a movie can be made, and when Relive would suggest one.
public enum MovieEligibility {
    /// Fewer distinct, usable photos than this can't make a movie.
    public static let minimumPhotos = 5
    /// A suggestion needs at least this many distinct photos, over more than one day or moment.
    public static let recommendedPhotos = 10
    /// A hand-picked movie keeps at most this many photos.
    public static let maximumPhotos = 30
}

extension CreationSource {
    /// Non-identifying kind, for diagnostics and analytics.
    public var kindCode: String {
        switch self {
        case .moment: "moment"
        case .trip: "trip"
        case .photos: "photos"
        case .month: "month"
        case .year: "year"
        case .favorites: "favorites"
        }
    }
}
