import Foundation
import ReliveCore

/// Answer to "Did you find something that made you smile?"
enum SmileResponse: String, Codable, Sendable {
    case yes
    case notYet
}

/// Local app state that isn't part of the story: who the story is about, onboarding progress,
/// and a few product signals. Value type mirror of `StoredProfile`.
struct AppProfile: Equatable, Sendable {
    var relationship: RelationshipProfile?
    var onboardingStartedAt: Date?
    var storyRevealedAt: Date?
    var smileResponse: SmileResponse?
    var smileRespondedAt: Date?
    var momentsOpenedCount: Int = 0
    var lastViewedMomentID: MomentID?
    var foundForYou: FoundForYouRecord?
    var surprise: SurpriseRecord?

    static let empty = AppProfile()
}

/// Today's Found for You choice, kept stable for the whole day.
struct FoundForYouRecord: Equatable, Sendable {
    var momentID: MomentID
    var assetID: AssetID
    var day: Date
}

/// The most recent Surprise Memory: kept for its day, and used to rest between surprises.
struct SurpriseRecord: Equatable, Sendable {
    var momentID: MomentID
    var assetID: AssetID
    var day: Date
    /// "Not now": hidden for the rest of the day.
    var isDismissed: Bool
}
