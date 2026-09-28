import Foundation
import Observation
import ReliveCore

/// App-level state: who the story is about, where the user is in onboarding, navigation, and
/// the handful of product signals Prototype 0.1 exists to measure.
@Observable
@MainActor
final class AppModel {
    enum OnboardingStep: Int, Comparable {
        case welcome
        case partner
        case startDate
        case photos
        case processing
        case reveal

        static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Tab: Hashable {
        case today
        case story
        case us
    }

    private(set) var profile: AppProfile
    private(set) var isOnboarding: Bool
    var onboardingStep: OnboardingStep
    var selectedTab: Tab = .today
    /// Set to make the Story tab scroll to a moment ("Continue your story").
    var storyScrollTarget: MomentID?
    /// Today's Found for You, chosen once per day.
    private(set) var foundMemory: FoundMemory?
    /// Shown briefly after hiding a moment, with an undo.
    var recentlyHiddenMomentID: MomentID?

    let storyStore: StoryStore
    private let repository: any StoryRepository
    private let analytics: any AnalyticsTracking

    init(storyStore: StoryStore, repository: any StoryRepository, analytics: any AnalyticsTracking) {
        self.storyStore = storyStore
        self.repository = repository
        self.analytics = analytics
        let profile = repository.loadProfile()
        self.profile = profile
        let step = AppModel.resumeStep(profile: profile, store: storyStore)
        self.onboardingStep = step ?? .welcome
        self.isOnboarding = step != nil
    }

    /// Where to resume onboarding after a relaunch, or nil when the story has been revealed.
    private static func resumeStep(profile: AppProfile, store: StoryStore) -> OnboardingStep? {
        if profile.storyRevealedAt != nil { return nil }
        guard let relationship = profile.relationship, !relationship.partnerName.isEmpty else { return .welcome }
        if relationship.start == nil { return .startDate }
        if !store.hasSelection { return .photos }
        if !store.hasStory { return .processing }
        return .reveal
    }

    var relationship: RelationshipProfile? { profile.relationship }

    var coupleName: String {
        profile.relationship?.coupleDisplayName ?? "Your story"
    }

    // MARK: - Onboarding

    func beginOnboarding() {
        if profile.onboardingStartedAt == nil {
            profile.onboardingStartedAt = Date()
            repository.saveProfile(profile)
            analytics.track(.onboardingStarted)
        }
        onboardingStep = .partner
    }

    func setPartnerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var relationship = profile.relationship ?? RelationshipProfile(partnerName: trimmed)
        relationship.partnerName = trimmed
        profile.relationship = relationship
        repository.saveProfile(profile)
    }

    func setUserName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var relationship = profile.relationship else { return }
        relationship.userName = trimmed.isEmpty ? nil : trimmed
        profile.relationship = relationship
        repository.saveProfile(profile)
    }

    func setRelationshipStart(_ start: RelationshipStart) {
        guard var relationship = profile.relationship else { return }
        relationship.start = start
        profile.relationship = relationship
        repository.saveProfile(profile)
    }

    func advance(to step: OnboardingStep) {
        onboardingStep = step
    }

    /// "See Our Story": onboarding is over.
    func completeReveal() {
        profile.storyRevealedAt = Date()
        repository.saveProfile(profile)
        analytics.track(.onboardingCompleted)
        selectedTab = .story
        isOnboarding = false
    }

    // MARK: - Moments

    func recordMomentOpened(_ id: MomentID, source: String) {
        profile.momentsOpenedCount += 1
        profile.lastViewedMomentID = id
        repository.saveProfile(profile)
        storyStore.markOpened(id)
        analytics.track(.momentOpened, ["source": source])
    }

    func hideMoment(_ id: MomentID) {
        storyStore.setHidden(true, for: id)
        recentlyHiddenMomentID = id
        if foundMemory?.momentID == id {
            refreshFoundMemory(force: true)
        }
    }

    func undoHide() {
        guard let id = recentlyHiddenMomentID else { return }
        storyStore.setHidden(false, for: id)
        recentlyHiddenMomentID = nil
    }

    func continueStory() {
        let target = storyStore.nextMoment(after: profile.lastViewedMomentID)
        storyScrollTarget = target?.id
        selectedTab = .story
    }

    var nextMomentToContinue: Moment? {
        storyStore.nextMoment(after: profile.lastViewedMomentID)
    }

    // MARK: - Found for You

    /// Picks today's memory (or restores the one already chosen today) and records it as surfaced.
    func refreshFoundMemory(now: Date = Date(), force: Bool = false) {
        let calendar = storyStore.calendar
        if !force, let record = profile.foundForYou, calendar.isDate(record.day, inSameDayAs: now),
           let memory = storyStore.foundMemory(from: record, now: now) {
            foundMemory = memory
            return
        }
        guard let memory = storyStore.selectFoundMemory(now: now) else {
            foundMemory = nil
            return
        }
        foundMemory = memory
        profile.foundForYou = FoundForYouRecord(momentID: memory.momentID, assetID: memory.assetID, day: calendar.startOfDay(for: now))
        repository.saveProfile(profile)
        storyStore.markSurfaced(memory.momentID, at: now)
    }

    func dontShowFoundMemoryAgain() {
        guard let memory = foundMemory else { return }
        storyStore.excludeFromSurfacing(memory.momentID)
        refreshFoundMemory(force: true)
    }

    func openFoundMemory() {
        analytics.track(.foundForYouOpened, ["age": foundMemory?.ageDescription ?? ""])
    }

    // MARK: - Validation question

    /// Ask once, only after the user has actually explored a few moments.
    var shouldAskSmileQuestion: Bool {
        profile.smileResponse == nil && profile.storyRevealedAt != nil && profile.momentsOpenedCount >= 2
    }

    func answerSmileQuestion(_ response: SmileResponse) {
        guard profile.smileResponse == nil else { return }
        profile.smileResponse = response
        profile.smileRespondedAt = Date()
        repository.saveProfile(profile)
        analytics.track(response == .yes ? .validationSmileYes : .validationSmileNo, [
            "moments_opened": String(profile.momentsOpenedCount),
        ])
    }

    // MARK: - Reset

    func startOver() {
        storyStore.resetAll()
        profile = .empty
        foundMemory = nil
        recentlyHiddenMomentID = nil
        storyScrollTarget = nil
        onboardingStep = .welcome
        isOnboarding = true
    }
}
