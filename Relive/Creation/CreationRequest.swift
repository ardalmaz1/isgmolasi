import Foundation
import ReliveCore

/// What is being made.
enum CreationKind: String, Hashable, Sendable {
    case collage
    case story

    /// Photos a creation of this kind works with.
    var photoRange: ClosedRange<Int> {
        switch self {
        case .collage: CreationLimits.collage
        case .story: CreationLimits.story
        }
    }

    var title: String {
        switch self {
        case .collage: "Memory Collage"
        case .story: "Story Maker"
        }
    }
}

/// Where a creation starts: by choosing, or from something the user is already looking at.
enum CreationStart: Hashable, Sendable {
    case choosePhotos
    case chooseMoment
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
