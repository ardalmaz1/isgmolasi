import Foundation
import Observation
import os
import ReliveCore

/// The app's Made for You: the current suggestions and what the couple did with them.
///
/// Suggestions are worked out from metadata only (never pixels) and only again when something
/// that matters changed — the story, favorites, hidden moments, available photos, kept
/// creations, the day, or the history. History lives in UserDefaults on this iPhone.
@Observable
@MainActor
final class MadeForYouStore {
    /// Best first: the first is Create's hero, the next ones its smaller cards.
    private(set) var suggestions: [MadeForYouSuggestion] = []
    private(set) var history: SuggestionHistory

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var signature: Signature?

    static let historyKey = "relive.madeForYou.history"
    static let limit = 4

    /// What, if it changes, means the suggestions should be worked out again.
    struct Signature: Hashable {
        var storyGeneratedAt: Date
        var momentCount: Int
        var assetCount: Int
        var favoriteMemories: Set<AssetID>
        var favoriteMoments: Set<MomentID>
        var hiddenMoments: Set<MomentID>
        var unavailable: Int
        var keptCount: Int
        var day: DayKey
        var history: SuggestionHistory
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        history = defaults.data(forKey: Self.historyKey).flatMap { try? JSONDecoder().decode(SuggestionHistory.self, from: $0) } ?? SuggestionHistory()
    }

    /// Works the suggestions out again if anything that matters changed. Cheap when nothing did.
    func refresh(from store: StoryStore) {
        guard store.hasStory else {
            suggestions = []
            signature = nil
            return
        }
        let current = signature(of: store)
        guard current != signature else { return }
        let library = store.creationLibrary
        var found = MadeForYouEngine(library: library, now: now(), history: history).suggestions(limit: Self.limit)
        if recordCreations(for: found, in: store) {
            found = MadeForYouEngine(library: library, now: now(), history: history).suggestions(limit: Self.limit)
        }
        suggestions = found
        signature = signature(of: store)
        #if DEBUG
        // Kinds and counts only — no titles, places or identifiers.
        Logger(subsystem: "app.relive", category: "intelligence")
            .notice("made_for_you suggestions=\(found.count, privacy: .public) kinds=[\(found.map { "\($0.kind.rawValue):\($0.creation.rawValue)" }.joined(separator: ","), privacy: .public)]")
        #endif
    }

    /// The single Today card, if one is strong enough (and isn't the surprise already shown).
    func todaySuggestion(excluding momentID: MomentID?) -> MadeForYouSuggestion? {
        suggestions.first { $0.isStrongEnoughForToday && ($0.momentID == nil || $0.momentID != momentID) }
    }

    func recordShown(_ shown: [MadeForYouSuggestion]) {
        let calendar = Calendar.current
        let before = history
        for suggestion in shown { history.recordShown(suggestion.id, now: now(), calendar: calendar) }
        if history != before { save(refreshing: false) }
    }

    func recordOpened(_ suggestion: MadeForYouSuggestion) {
        history.recordOpened(suggestion.id, now: now())
        save(refreshing: false)
    }

    /// A recap of `source` was shared: its recap suggestion has been made, so it steps away
    /// (for `SuggestionHistory.createdDays`) like any suggestion something was made from.
    func recordMade(source: CreationSource) {
        let made = suggestions.filter { $0.source == source && ($0.creation == .monthlyRecap || $0.creation == .yearInReview) }
        guard !made.isEmpty else { return }
        for suggestion in made { history.recordCreated(suggestion.id, now: now()) }
        save(refreshing: true)
    }

    /// "Not now": it goes away (for a while), and the next best takes its place.
    func dismiss(_ suggestion: MadeForYouSuggestion, store: StoryStore) {
        history.recordDismissed(suggestion.id, now: now())
        save(refreshing: true)
        refresh(from: store)
    }

    // MARK: - Private

    private func signature(of store: StoryStore) -> Signature {
        Signature(
            storyGeneratedAt: store.story.generatedAt,
            momentCount: store.story.moments.count,
            assetCount: store.assets.count,
            favoriteMemories: store.favorites.memoryIDs,
            favoriteMoments: store.favorites.momentIDs,
            hiddenMoments: Set(store.userStates.filter { $0.value.isHidden }.keys),
            unavailable: store.unavailableAssetIDs.count,
            keptCount: store.keptItems.count,
            day: DayKey(date: now(), calendar: .current),
            history: history
        )
    }

    /// A suggestion counts as made once a creation from the same source was kept after it was
    /// first shown. Returns true if anything was recorded.
    private func recordCreations(for found: [MadeForYouSuggestion], in store: StoryStore) -> Bool {
        var changed = false
        let kept: [(CreationSource, Date)] = store.keptItems.map { item in
            switch item {
            case .creation(let creation): (creation.source, creation.createdAt)
            case .book(let book): (book.source, book.createdAt)
            }
        }
        for suggestion in found {
            guard let shown = history.entries[suggestion.id]?.firstShownAt,
                  history.entries[suggestion.id]?.createdAt == nil,
                  kept.contains(where: { $0.0 == suggestion.source && $0.1 >= shown }) else { continue }
            history.recordCreated(suggestion.id, now: now())
            changed = true
        }
        if changed { save(refreshing: false) }
        return changed
    }

    private func save(refreshing: Bool) {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
        if refreshing { signature = nil }
    }

    #if DEBUG
    /// UI tests only (`-ReliveUITestStartFresh`).
    static func eraseLocalState(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: historyKey)
    }
    #endif
}
