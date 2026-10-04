import Foundation
import ReliveCore

/// What is being made.
enum CreationKind: String, Hashable, Sendable {
    case collage
    case story
    case book

    /// Photos a creation of this kind works with.
    var photoRange: ClosedRange<Int> {
        switch self {
        case .collage: CreationLimits.collage
        case .story: CreationLimits.story
        case .book: BookLimits.minimumPhotos...BookLimits.maximumPhotos
        }
    }

    var title: String {
        switch self {
        case .collage: "Memory Collage"
        case .story: "Story Maker"
        case .book: "Memory Book"
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
