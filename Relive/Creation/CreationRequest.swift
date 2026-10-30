import Foundation
import ReliveCore

/// What is being made.
enum CreationKind: String, Hashable, Sendable {
    case collage
    case story
    case book
    case movie

    /// Photos a creation of this kind works with.
    var photoRange: ClosedRange<Int> {
        switch self {
        case .collage: CreationLimits.collage
        case .story: CreationLimits.story
        case .book: BookLimits.minimumPhotos...BookLimits.maximumPhotos
        case .movie: MovieEligibility.minimumPhotos...MovieEligibility.maximumPhotos
        }
    }

    var title: String {
        switch self {
        case .collage: String(localized: "Memory Collage")
        case .story: String(localized: "Story Maker")
        case .book: String(localized: "Memory Book")
        case .movie: String(localized: "Memory Movie")
        }
    }
}

/// Where a creation starts: by choosing, or from something the user is already looking at.
enum CreationStart: Hashable, Sendable {
    /// Choose photos: from Relive, or from the photo library.
    case choosePhotos
    /// Straight to the system photo picker.
    case choosePhotoLibrary
    case chooseMoment
    case chooseTrip
    case chooseMonth
    case chooseYear
    case source(CreationSource)
    /// Reopen a kept collage, story or book (a draft or a finished one) by its identifier.
    case resume(UUID)
}

/// A request to watch a Monthly Recap or Our Year.
struct RecapRequest: Identifiable, Hashable, Sendable {
    let id = UUID()
    var period: RecapPeriod
    /// Non-identifying label of the entry point ("monthly_recap", "made_for_you"…).
    var origin: String

    /// First Experience V2, first-session protection: the recap a brand-new couple opens from
    /// "We found something for you" is shown in full that one time — every chapter, no Premium
    /// page in the middle. Keeping or sharing it still follows the Premium rules; opening it again
    /// later (from Today, Create…) is the usual preview.
    static let firstDiscoveryOrigin = "first_discovery"
    var isFirstDiscovery: Bool { origin == Self.firstDiscoveryOrigin }
}

/// A request to open the collage or story maker. Any screen can make one through `AppModel`;
/// the main tab view presents it over everything.
struct CreationRequest: Identifiable, Hashable, Sendable {
    let id = UUID()
    var kind: CreationKind
    var start: CreationStart
    /// Non-identifying label of the entry point ("create", "moment", "recap"…), for analytics.
    var origin: String
}
