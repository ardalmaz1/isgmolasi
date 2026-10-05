import Foundation
import os
import ReliveCore
import SwiftData

/// Local persistence for Relive. Stores and views depend on this protocol, not on SwiftData, so
/// storage (or a future sync layer) can change without touching them.
@MainActor
protocol StoryRepository: AnyObject {
    func loadProfile() -> AppProfile
    func saveProfile(_ profile: AppProfile)

    func loadAssets() -> [MemoryAsset]
    func saveAssets(_ assets: [MemoryAsset])

    func loadStory() -> Story?
    func saveStory(_ story: Story)

    func loadMomentStates() -> [MomentID: MomentUserState]
    func saveMomentState(_ state: MomentUserState, for id: MomentID)

    /// Images Relive saved to the photo library itself (see `StoredCreatedAsset`).
    func loadCreatedAssetIDs() -> Set<AssetID>
    func recordCreatedAssets(_ ids: [AssetID])

    /// Saved Memory Books (definitions only).
    func loadBooks() -> [MemoryBook]
    func saveBook(_ book: MemoryBook)
    func deleteBook(id: UUID)

    /// Favorites (v0.4).
    func loadFavorites() -> [FavoriteRecord]
    func saveFavorite(_ favorite: FavoriteRecord)
    func removeFavorite(kind: FavoriteKind, identifier: String)

    /// Collages and stories kept in Relive, drafts and finished (v0.4).
    func loadCreations() -> [SavedCreation]
    func saveCreation(_ creation: SavedCreation)
    func deleteCreation(id: UUID)

    /// Start Over: removes the relationship story — profile and onboarding, the selection, the
    /// story, notes and hidden moments. Photos in the library are never touched. What the couple
    /// made or chose is kept: books, collages, stories and drafts, favorites, and the list of
    /// images Relive created (so they still can't come back as memories).
    func deleteAll()
}

/// SwiftData implementation. Runs on the main actor with the container's main context; the data
/// volume (hundreds of records) is small enough that this never blocks noticeably.
@MainActor
final class SwiftDataStoryRepository: StoryRepository {
    private static let logger = Logger(subsystem: "app.relive", category: "persistence")

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
    }

    /// Opens the on-disk store, falling back to memory so the app still launches if the store
    /// can't be opened (the user would then see onboarding again rather than a crash).
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(PersistenceSchema.models)
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.fault("Persistent store unavailable, using memory: \(error.localizedDescription, privacy: .public)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Could not create even an in-memory store: \(error)")
            }
        }
    }

    // MARK: - Profile

    func loadProfile() -> AppProfile {
        guard let stored = fetchAll(StoredProfile.self).first else { return .empty }
        var profile = AppProfile()
        if !stored.partnerName.isEmpty {
            let start = stored.relationshipStart.map { date in
                RelationshipStart(
                    date: date,
                    precision: stored.relationshipStartPrecision.flatMap(RelationshipStart.Precision.init(rawValue:)) ?? .month
                )
            }
            profile.relationship = RelationshipProfile(partnerName: stored.partnerName, userName: stored.userName, start: start)
        }
        profile.onboardingStartedAt = stored.onboardingStartedAt
        profile.storyRevealedAt = stored.storyRevealedAt
        profile.smileResponse = stored.smileResponse.flatMap(SmileResponse.init(rawValue:))
        profile.smileRespondedAt = stored.smileRespondedAt
        profile.momentsOpenedCount = stored.momentsOpenedCount
        profile.lastViewedMomentID = stored.lastViewedMomentID
        if let momentID = stored.foundMomentID, let assetID = stored.foundAssetID, let day = stored.foundOnDay {
            profile.foundForYou = FoundForYouRecord(momentID: momentID, assetID: assetID, day: day)
        }
        if let momentID = stored.surpriseMomentID, let assetID = stored.surpriseAssetID, let day = stored.surpriseOnDay {
            profile.surprise = SurpriseRecord(momentID: momentID, assetID: assetID, day: day, isDismissed: stored.surpriseDismissed)
        }
        return profile
    }

    func saveProfile(_ profile: AppProfile) {
        let stored = fetchAll(StoredProfile.self).first ?? {
            let created = StoredProfile()
            context.insert(created)
            return created
        }()
        stored.partnerName = profile.relationship?.partnerName ?? ""
        stored.userName = profile.relationship?.userName
        stored.relationshipStart = profile.relationship?.start?.date
        stored.relationshipStartPrecision = profile.relationship?.start?.precision.rawValue
        stored.onboardingStartedAt = profile.onboardingStartedAt
        stored.storyRevealedAt = profile.storyRevealedAt
        stored.smileResponse = profile.smileResponse?.rawValue
        stored.smileRespondedAt = profile.smileRespondedAt
        stored.momentsOpenedCount = profile.momentsOpenedCount
        stored.lastViewedMomentID = profile.lastViewedMomentID
        stored.foundMomentID = profile.foundForYou?.momentID
        stored.foundAssetID = profile.foundForYou?.assetID
        stored.foundOnDay = profile.foundForYou?.day
        stored.surpriseMomentID = profile.surprise?.momentID
        stored.surpriseAssetID = profile.surprise?.assetID
        stored.surpriseOnDay = profile.surprise?.day
        stored.surpriseDismissed = profile.surprise?.isDismissed ?? false
        save()
    }

    // MARK: - Assets

    func loadAssets() -> [MemoryAsset] {
        fetchAll(StoredAsset.self).compactMap { stored in
            do {
                return try decoder.decode(MemoryAsset.self, from: stored.payload)
            } catch {
                Self.logger.error("Dropping unreadable asset record: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func saveAssets(_ assets: [MemoryAsset]) {
        var existing: [String: StoredAsset] = [:]
        for stored in fetchAll(StoredAsset.self) {
            if existing[stored.localIdentifier] != nil {
                context.delete(stored) // stray duplicate
            } else {
                existing[stored.localIdentifier] = stored
            }
        }

        let keep = Set(assets.map(\.id))
        for (identifier, stored) in existing where !keep.contains(identifier) {
            context.delete(stored)
        }
        let now = Date()
        for asset in assets {
            guard let payload = try? encoder.encode(asset) else { continue }
            if let stored = existing[asset.id] {
                if stored.payload != payload { stored.payload = payload }
            } else {
                context.insert(StoredAsset(localIdentifier: asset.id, payload: payload, selectedAt: now))
            }
        }
        save()
    }

    // MARK: - Story

    func loadStory() -> Story? {
        guard let snapshot = fetchAll(StoredStorySnapshot.self).max(by: { $0.generatedAt < $1.generatedAt }) else {
            return nil
        }
        do {
            let story = try decoder.decode(Story.self, from: snapshot.payload)
            return story.version == Story.currentVersion ? story : nil
        } catch {
            Self.logger.error("Stored story unreadable, it will be regenerated: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveStory(_ story: Story) {
        guard let payload = try? encoder.encode(story) else { return }
        for snapshot in fetchAll(StoredStorySnapshot.self) {
            context.delete(snapshot)
        }
        context.insert(StoredStorySnapshot(version: story.version, payload: payload, generatedAt: story.generatedAt))
        save()
    }

    // MARK: - Moment state

    func loadMomentStates() -> [MomentID: MomentUserState] {
        var states: [MomentID: MomentUserState] = [:]
        for stored in fetchAll(StoredMomentState.self) {
            states[stored.momentID] = MomentUserState(
                note: stored.note,
                noteUpdatedAt: stored.noteUpdatedAt,
                isHidden: stored.isHidden,
                isExcludedFromSurfacing: stored.isExcludedFromSurfacing,
                heroOverrideAssetID: stored.heroOverrideAssetID,
                lastSurfacedAt: stored.lastSurfacedAt,
                surfacedCount: stored.surfacedCount,
                lastOpenedAt: stored.lastOpenedAt
            )
        }
        return states
    }

    func saveMomentState(_ state: MomentUserState, for id: MomentID) {
        let stored = fetchAll(StoredMomentState.self).first { $0.momentID == id } ?? {
            let created = StoredMomentState(momentID: id)
            context.insert(created)
            return created
        }()
        stored.note = state.note
        stored.noteUpdatedAt = state.noteUpdatedAt
        stored.isHidden = state.isHidden
        stored.isExcludedFromSurfacing = state.isExcludedFromSurfacing
        stored.heroOverrideAssetID = state.heroOverrideAssetID
        stored.lastSurfacedAt = state.lastSurfacedAt
        stored.surfacedCount = state.surfacedCount
        stored.lastOpenedAt = state.lastOpenedAt
        save()
    }

    // MARK: - Created images

    func loadCreatedAssetIDs() -> Set<AssetID> {
        Set(fetchAll(StoredCreatedAsset.self).map(\.localIdentifier))
    }

    func recordCreatedAssets(_ ids: [AssetID]) {
        let known = loadCreatedAssetIDs()
        let now = Date()
        for id in ids where !known.contains(id) {
            context.insert(StoredCreatedAsset(localIdentifier: id, createdAt: now))
        }
        save()
    }

    // MARK: - Memory Books

    func loadBooks() -> [MemoryBook] {
        fetchAll(StoredMemoryBook.self).compactMap { stored in
            do {
                return try decoder.decode(MemoryBook.self, from: stored.payload)
            } catch {
                Self.logger.error("Dropping unreadable book: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func saveBook(_ book: MemoryBook) {
        guard let payload = try? encoder.encode(book) else { return }
        let matches = fetchAll(StoredMemoryBook.self).filter { $0.bookID == book.id }
        if let stored = matches.first {
            stored.payload = payload
            stored.updatedAt = book.updatedAt
            matches.dropFirst().forEach(context.delete)
        } else {
            context.insert(StoredMemoryBook(bookID: book.id, payload: payload, updatedAt: book.updatedAt))
        }
        save()
    }

    func deleteBook(id: UUID) {
        fetchAll(StoredMemoryBook.self).filter { $0.bookID == id }.forEach(context.delete)
        save()
    }

    // MARK: - Favorites

    func loadFavorites() -> [FavoriteRecord] {
        fetchAll(StoredFavorite.self).compactMap { stored in
            FavoriteKind(rawValue: stored.kind).map { FavoriteRecord(kind: $0, identifier: stored.identifier, favoritedAt: stored.favoritedAt) }
        }
    }

    func saveFavorite(_ favorite: FavoriteRecord) {
        let matches = fetchAll(StoredFavorite.self).filter { $0.kind == favorite.kind.rawValue && $0.identifier == favorite.identifier }
        if let stored = matches.first {
            stored.favoritedAt = favorite.favoritedAt
            matches.dropFirst().forEach(context.delete)
        } else {
            context.insert(StoredFavorite(kind: favorite.kind.rawValue, identifier: favorite.identifier, favoritedAt: favorite.favoritedAt))
        }
        save()
    }

    func removeFavorite(kind: FavoriteKind, identifier: String) {
        fetchAll(StoredFavorite.self).filter { $0.kind == kind.rawValue && $0.identifier == identifier }.forEach(context.delete)
        save()
    }

    // MARK: - Creations

    func loadCreations() -> [SavedCreation] {
        let stored = fetchAll(StoredCreation.self)
        let creations = stored.compactMap { stored -> SavedCreation? in
            do {
                return try decoder.decode(SavedCreation.self, from: stored.payload)
            } catch {
                Self.logger.error("Dropping unreadable creation: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        #if DEBUG
        Self.logger.notice("creations_loaded records=\(stored.count, privacy: .public) drafts=\(creations.filter(\.isDraft).count, privacy: .public) saved=\(creations.filter { !$0.isDraft }.count, privacy: .public)")
        #endif
        return creations
    }

    func saveCreation(_ creation: SavedCreation) {
        let payload: Data
        do {
            payload = try encoder.encode(creation)
        } catch {
            Self.logger.error("draft_encode_failed kind=\(creation.kind.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return
        }
        let matches = fetchAll(StoredCreation.self).filter { $0.creationID == creation.id }
        if let stored = matches.first {
            stored.payload = payload
            stored.status = creation.status.rawValue
            stored.updatedAt = creation.updatedAt
            matches.dropFirst().forEach(context.delete)
        } else {
            context.insert(StoredCreation(
                creationID: creation.id, kind: creation.kind.rawValue, status: creation.status.rawValue,
                payload: payload, updatedAt: creation.updatedAt
            ))
        }
        save()
    }

    func deleteCreation(id: UUID) {
        fetchAll(StoredCreation.self).filter { $0.creationID == id }.forEach(context.delete)
        save()
    }

    // MARK: - Reset

    func deleteAll() {
        do {
            try context.delete(model: StoredProfile.self)
            try context.delete(model: StoredAsset.self)
            try context.delete(model: StoredStorySnapshot.self)
            try context.delete(model: StoredMomentState.self)
        } catch {
            Self.logger.error("Reset failed: \(error.localizedDescription, privacy: .public)")
        }
        save()
    }

    #if DEBUG
    /// UI tests only (`-ReliveUITestStartFresh`): a truly empty store, creations and favorites
    /// included, so one test run can't see another's.
    func eraseEverything() {
        deleteAll()
        do {
            try context.delete(model: StoredCreatedAsset.self)
            try context.delete(model: StoredMemoryBook.self)
            try context.delete(model: StoredFavorite.self)
            try context.delete(model: StoredCreation.self)
        } catch {
            Self.logger.error("Erase failed: \(error.localizedDescription, privacy: .public)")
        }
        save()
    }
    #endif

    // MARK: - Helpers

    private func fetchAll<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
        do {
            return try context.fetch(FetchDescriptor<Model>())
        } catch {
            Self.logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
