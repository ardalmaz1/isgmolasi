import Foundation

/// Product events. Names are stable strings so they can be forwarded to any provider later.
public enum AnalyticsEventName: String, CaseIterable, Sendable {
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case photosSelected = "photos_selected"
    case memoryProcessingCompleted = "memory_processing_completed"
    case storyRevealed = "story_revealed"
    case timelineOpened = "timeline_opened"
    case momentOpened = "moment_opened"
    case memoryShared = "memory_shared"
    case noteAdded = "note_added"
    case memoryHidden = "memory_hidden"
    // Real Device Polish V1. Properties are kinds and counts only — never a place, date or name.
    case memoryNotSuggested = "memory_not_suggested"
    case memorySuggestedAgain = "memory_suggested_again"
    case archiveOpened = "archive_opened"
    case storyYearJumped = "story_year_jumped"
    case todayDiscoveryOpened = "today_discovery_opened"
    case foundForYouOpened = "found_for_you_opened"
    case memoriesAdded = "memories_added"
    case validationSmileYes = "validation_smile_yes"
    case validationSmileNo = "validation_smile_no"
    case createOpened = "create_opened"
    case creationStarted = "creation_started"
    case creationExported = "creation_exported"
    case recapOpened = "recap_opened"
    case surpriseMemoryShown = "surprise_memory_shown"
    case surpriseMemoryOpened = "surprise_memory_opened"
    case memoryBookCreated = "memory_book_created"
    case memoryBookOpened = "memory_book_opened"
    case trendOpened = "trend_opened"
    /// Photos picked from the photo library for a creation (counts only).
    case photoLibraryPicked = "photo_library_picked"
    // v0.4 personal collection (kinds and counts only — never identifiers, titles or places).
    case favoriteAdded = "favorite_added"
    case favoriteRemoved = "favorite_removed"
    case creationSaved = "creation_saved"
    case creationReopened = "creation_reopened"
    case creationDeleted = "creation_deleted"
    case draftCreated = "draft_created"
    case draftResumed = "draft_resumed"
    case draftDeleted = "draft_deleted"
    case createFromFavorites = "create_from_favorites"
    // Commercial v1 (entry point, feature and product role only — never content).
    case paywallViewed = "paywall_viewed"
    case paywallClosed = "paywall_closed"
    case premiumPurchaseStarted = "premium_purchase_started"
    case premiumPurchaseCompleted = "premium_purchase_completed"
    case premiumPurchaseCancelled = "premium_purchase_cancelled"
    case premiumPurchasePending = "premium_purchase_pending"
    case premiumPurchaseFailed = "premium_purchase_failed"
    case premiumRestoreStarted = "premium_restore_started"
    case premiumRestoreCompleted = "premium_restore_completed"
    case freeExportUsed = "free_export_used"
    case premiumFeatureTapped = "premium_feature_tapped"
    // Intelligence v1 phase 3: immersive recaps (period kind, chapter kind and counts only).
    case recapChapterViewed = "recap_chapter_viewed"
    case recapCompleted = "recap_completed"
    case recapCreationStarted = "recap_creation_started"
    case recapShareStarted = "recap_share_started"
    case recapShareCompleted = "recap_share_completed"
    // Intelligence v1 phase 4: Memory Movie (source kind, style, aspect, length, result only).
    case movieStarted = "movie_started"
    case moviePreviewed = "movie_previewed"
    case movieStyleChanged = "movie_style_changed"
    case movieRegenerated = "movie_regenerated"
    case movieExportStarted = "movie_export_started"
    case movieExportCompleted = "movie_export_completed"
    case movieExportFailed = "movie_export_failed"
    case movieShared = "movie_shared"
    // Intelligence v1 phase 5: editorial intelligence (surface, kind, provider, codes only —
    // never the words, places, dates or names).
    case editorialRequested = "editorial_requested"
    case editorialCandidateAccepted = "editorial_candidate_accepted"
    case editorialCandidateRejected = "editorial_candidate_rejected"
    case editorialFallbackUsed = "editorial_fallback_used"
    case editorialVariantChanged = "editorial_variant_changed"
    case editorialUserEdited = "editorial_user_edited"
    // First Experience V2 (path, counts/buckets, result type, duration bucket — no content).
    case photoStartChoice = "photo_start_choice"
    case discoveryStarted = "discovery_started"
    case discoveryCompleted = "discovery_completed"
    case discoveryCancelled = "discovery_cancelled"
    case candidateMomentKept = "candidate_moment_kept"
    case candidateMomentRejected = "candidate_moment_rejected"
    case manualSelectionCompleted = "manual_selection_completed"
    case firstDiscoveryShown = "first_discovery_shown"
    case firstDiscoveryOpened = "first_discovery_opened"
    // Phase B — partner connection. Properties: role and outcome codes only.
    case partnerConnectStarted = "partner_connect_started"
    case partnerInvitationCreated = "partner_invitation_created"
    case partnerJoined = "partner_joined"
    case partnerConnectFailed = "partner_connect_failed"
    case partnerDisconnected = "partner_disconnected"
    case partnerConnectionEnded = "partner_connection_ended"
}

/// Coarse buckets, so analytics never carry exact library sizes or timings.
public enum AnalyticsBucket {
    public static func count(_ value: Int) -> String {
        switch value {
        case ..<1: "0"
        case 1..<5: "1-4"
        case 5..<20: "5-19"
        case 20..<50: "20-49"
        case 50..<200: "50-199"
        case 200..<1_000: "200-999"
        case 1_000..<10_000: "1000-9999"
        default: "10000+"
        }
    }

    public static func seconds(_ value: Double) -> String {
        switch value {
        case ..<5: "<5s"
        case 5..<15: "5-15s"
        case 15..<60: "15-60s"
        case 60..<180: "1-3m"
        default: "3m+"
        }
    }
}

public struct AnalyticsEvent: Equatable, Sendable {
    public var name: AnalyticsEventName
    /// Non-identifying context only (counts, durations, flags) — never names, notes or places.
    public var properties: [String: String]
    public var timestamp: Date

    public init(_ name: AnalyticsEventName, properties: [String: String] = [:], timestamp: Date = Date()) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

/// Destination for analytics events. Prototype 0.1 only logs locally; a provider can be plugged
/// in later without touching call sites.
public protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
}

extension AnalyticsTracking {
    public func track(_ name: AnalyticsEventName, _ properties: [String: String] = [:]) {
        track(AnalyticsEvent(name, properties: properties))
    }
}

/// Collects events in memory. Useful for tests and debugging.
public final class InMemoryAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []

    public init() {}

    public func track(_ event: AnalyticsEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    public var events: [AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
