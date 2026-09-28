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
    case foundForYouOpened = "found_for_you_opened"
    case memoriesAdded = "memories_added"
    case validationSmileYes = "validation_smile_yes"
    case validationSmileNo = "validation_smile_no"
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
