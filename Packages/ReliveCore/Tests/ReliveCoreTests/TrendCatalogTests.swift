import Foundation
import Testing
@testable import ReliveCore

@Suite("Trend catalog")
struct TrendCatalogTests {
    let now = date(2026, 10, 2)
    let allLocalRecipes: Set<TrendRecipeReference> = [
        TrendRecipeReference(id: "bw-editorial", version: 1),
        TrendRecipeReference(id: "film-couple", version: 1),
        TrendRecipeReference(id: "photo-booth", version: 1),
        TrendRecipeReference(id: "magazine-cover", version: 1),
        TrendRecipeReference(id: "cinematic-poster", version: 1),
    ]

    func context(recipes: Set<TrendRecipeReference>? = nil, ai: Bool = false, version: String = "0.3", now: Date? = nil) -> TrendContext {
        TrendContext(now: now ?? self.now, appVersion: AppVersion(version), recipes: recipes ?? allLocalRecipes, isAIAvailable: ai)
    }

    func trend(_ id: String = "test", execution: TrendExecution = .local, privacy: TrendPrivacy = .onDevice, recipe: String = "bw-editorial", version: Int = 1, priority: Int = 0) -> TrendDefinition {
        TrendDefinition(
            id: id, name: "Test \(id)", summary: "A test trend.", execution: execution,
            recipe: TrendRecipeReference(id: recipe, version: version),
            photos: TrendPhotoRequirement(minimum: 1, maximum: 2), aspectRatios: [.portrait],
            priority: priority, privacy: privacy
        )
    }

    func json(_ trends: [String], schema: Int = 1, revision: Int = 3) -> Data {
        Data(#"{"schemaVersion": \#(schema), "revision": \#(revision), "trends": [\#(trends.joined(separator: ","))]}"#.utf8)
    }

    let validEntry = #"{"id": "remote-one", "name": "Remote One", "summary": "From a remote catalog.", "execution": "template", "recipe": {"id": "photo-booth", "version": 1}, "photos": {"minimum": 3, "maximum": 4}, "aspectRatios": ["story"], "privacy": "onDevice"}"#

    // MARK: - Parsing

    @Test("The starter catalog parses completely and is small and curated")
    func starter() throws {
        let parsed = try TrendCatalogParser.parse(Data(StarterTrendCatalog.json.utf8)).get()
        #expect(parsed.rejected.isEmpty)
        #expect((4...7).contains(parsed.catalog.trends.count))
        let executions = Set(parsed.catalog.trends.map(\.execution))
        #expect(executions == [.local, .template, .ai])
        #expect(StarterTrendCatalog.catalog == parsed.catalog)
        // Every on-device trend is implemented by a recipe this app ships.
        for trend in parsed.catalog.trends where trend.execution != .ai {
            #expect(allLocalRecipes.contains(trend.recipe), "\(trend.id)")
        }
    }

    @Test("Optional fields may be left out")
    func defaults() throws {
        let parsed = try TrendCatalogParser.parse(json([validEntry])).get()
        let trend = try #require(parsed.catalog.trends.first)
        #expect(trend.isActive && trend.priority == 0 && trend.tier == .free && trend.guidance.isEmpty && trend.badge == nil)
        #expect(parsed.catalog.revision == 3)
    }

    @Test("A malformed document is rejected as a whole")
    func malformed() {
        #expect(TrendCatalogParser.parse(Data("not json".utf8)).failureValue == .malformed)
        #expect(TrendCatalogParser.parse(Data(#"{"trends": []}"#.utf8)).failureValue == .malformed)
        #expect(TrendCatalogParser.parse(Data(#"{"schemaVersion": 1, "revision": 1, "trends": {}}"#.utf8)).failureValue == .malformed)
        #expect(TrendCatalogParser.parse(Data(repeating: 0x20, count: 600 * 1024)).failureValue == .malformed)
    }

    @Test("A catalog from a newer format is not guessed at")
    func newerSchema() {
        #expect(TrendCatalogParser.parse(json([validEntry], schema: 2)).failureValue == .unsupportedSchema(2))
    }

    @Test("Bad entries are dropped, good ones kept")
    func lossyEntries() throws {
        let entries = [
            validEntry,
            #"{"id": "Not A Slug!", "name": "x", "summary": "x", "execution": "local", "recipe": {"id": "bw-editorial", "version": 1}, "photos": {"minimum": 1, "maximum": 1}, "aspectRatios": ["portrait"], "privacy": "onDevice"}"#,
            #"{"id": "missing-fields", "name": "x"}"#,
            #"{"id": "ai-pretending-local", "name": "x", "summary": "x", "execution": "ai", "recipe": {"id": "golden-hour", "version": 1}, "photos": {"minimum": 1, "maximum": 1}, "aspectRatios": ["portrait"], "privacy": "onDevice"}"#,
            #"{"id": "too-many-photos", "name": "x", "summary": "x", "execution": "template", "recipe": {"id": "photo-booth", "version": 1}, "photos": {"minimum": 1, "maximum": 40}, "aspectRatios": ["story"], "privacy": "onDevice"}"#,
            #"{"id": "unknown-execution", "name": "x", "summary": "x", "execution": "script", "recipe": {"id": "x", "version": 1}, "photos": {"minimum": 1, "maximum": 1}, "aspectRatios": ["story"], "privacy": "onDevice"}"#,
            #"{"id": "bad-dates", "name": "x", "summary": "x", "execution": "local", "recipe": {"id": "bw-editorial", "version": 1}, "photos": {"minimum": 1, "maximum": 1}, "aspectRatios": ["portrait"], "privacy": "onDevice", "availableFrom": "2026-12-01T00:00:00Z", "availableUntil": "2026-11-01T00:00:00Z"}"#,
            validEntry, // duplicate id
        ]
        let parsed = try TrendCatalogParser.parse(json(entries)).get()
        #expect(parsed.catalog.trends.map(\.id) == ["remote-one"])
        #expect(Set(parsed.rejected) == ["Not A Slug!", "missing-fields", "ai-pretending-local", "too-many-photos", "unknown-execution", "bad-dates", "remote-one"])
    }

    @Test("Parameters are plain, bounded values")
    func parameters() {
        var trend = trend()
        trend.parameters = ["grain": "0.4"]
        #expect(TrendCatalogParser.validate(trend))
        trend.parameters = ["Bad Key": "x"]
        #expect(!TrendCatalogParser.validate(trend))
        trend.parameters = ["grain": String(repeating: "x", count: 300)]
        #expect(!TrendCatalogParser.validate(trend))
    }

    // MARK: - Choosing a catalog

    @Test("Offline or after a failure, the bundled catalog is used; a newer download wins")
    func resolver() {
        let bundled = TrendCatalog(revision: 1, trends: [trend("bundled")])
        let cached = TrendCatalog(revision: 4, trends: [trend("cached")])
        let fetched = TrendCatalog(revision: 5, trends: [trend("fetched")])
        let older = TrendCatalog(revision: 0, trends: [trend("older")])
        #expect(TrendCatalogResolver.choose(bundled: bundled, cached: nil, fetched: nil) == bundled)
        #expect(TrendCatalogResolver.choose(bundled: bundled, cached: cached, fetched: nil) == cached)
        #expect(TrendCatalogResolver.choose(bundled: bundled, cached: cached, fetched: fetched) == fetched)
        #expect(TrendCatalogResolver.choose(bundled: bundled, cached: nil, fetched: older) == bundled, "an older remote catalog never replaces the bundled one")
    }

    // MARK: - What shows

    @Test("Active, scheduled, supported trends show, by priority")
    func visibility() {
        var inactive = trend("inactive", priority: 50)
        inactive.isActive = false
        var future = trend("future", priority: 50)
        future.availableFrom = date(2026, 12, 1)
        var past = trend("past", priority: 50)
        past.availableUntil = date(2026, 9, 1)
        var newerApp = trend("newer-app", priority: 50)
        newerApp.minimumAppVersion = "0.10"
        let unsupported = trend("unsupported", recipe: "bw-editorial", version: 2, priority: 50)
        let low = trend("low", priority: 1)
        let high = trend("high", recipe: "film-couple", priority: 9)
        let ai = trend("ai", execution: .ai, privacy: .aiProvider, recipe: "golden-hour", priority: 5)
        let catalog = TrendCatalog(revision: 1, trends: [inactive, future, past, newerApp, unsupported, low, high, ai])

        let visible = TrendCatalogFilter.visibleTrends(in: catalog, context: context())
        #expect(visible.map(\.trend.id) == ["high", "ai", "low"])
        #expect(visible.first { $0.trend.id == "ai" }?.availability == .comingSoon)

        #expect(TrendCatalogFilter.availability(of: inactive, in: context()) == .hidden(.inactive))
        #expect(TrendCatalogFilter.availability(of: future, in: context()) == .hidden(.notYetAvailable))
        #expect(TrendCatalogFilter.availability(of: past, in: context()) == .hidden(.expired))
        #expect(TrendCatalogFilter.availability(of: newerApp, in: context()) == .hidden(.requiresNewerApp))
        #expect(TrendCatalogFilter.availability(of: newerApp, in: context(version: "0.10")) == .available)
        #expect(TrendCatalogFilter.availability(of: unsupported, in: context()) == .hidden(.unsupportedRecipe), "recipe v2 needs an app that has it")
        #expect(TrendCatalogFilter.availability(of: future, in: context(now: date(2026, 12, 2))) == .available)
    }

    @Test("An AI trend becomes available only with a provider")
    func aiAvailability() {
        let ai = trend("ai", execution: .ai, privacy: .aiProvider, recipe: "golden-hour")
        #expect(TrendCatalogFilter.availability(of: ai, in: context(ai: false)) == .comingSoon)
        #expect(TrendCatalogFilter.availability(of: ai, in: context(ai: true)) == .available)
    }

    @Test("Versions compare numerically")
    func versions() throws {
        #expect(try #require(AppVersion("0.3")) < #require(AppVersion("0.10")))
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1")))
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("") == nil)
    }

    // MARK: - Privacy and AI

    @Test("Only AI trends need the AI disclosure")
    func disclosure() throws {
        for trend in StarterTrendCatalog.catalog.trends {
            #expect(TrendPrivacyGate.requiresDisclosure(trend) == (trend.execution == .ai), "\(trend.id)")
        }
    }

    @Test("Without a provider, AI generation fails honestly")
    func noProvider() async {
        let ai = trend("ai", execution: .ai, privacy: .aiProvider, recipe: "golden-hour")
        let coordinator = AITrendCoordinator(provider: nil)
        #expect(!coordinator.isAvailable)
        await #expect(throws: AITrendError.providerNotConfigured) {
            _ = try await coordinator.generate(trend: ai, images: [image("a")], aspectRatio: .portrait, userConsented: true)
        }
    }

    @Test("A provider is never called without consent, and gets only the chosen photos")
    func consentAndScope() async throws {
        var ai = trend("ai", execution: .ai, privacy: .aiProvider, recipe: "golden-hour")
        ai.photos = TrendPhotoRequirement(minimum: 2, maximum: 2)
        let provider = RecordingProvider()
        let coordinator = AITrendCoordinator(provider: provider)

        await #expect(throws: AITrendError.consentRequired) {
            _ = try await coordinator.generate(trend: ai, images: [image("a"), image("b")], aspectRatio: .portrait, userConsented: false)
        }
        #expect(provider.requests.isEmpty)

        await #expect(throws: AITrendError.wrongPhotoCount(expected: 2...2, actual: 1)) {
            _ = try await coordinator.generate(trend: ai, images: [image("a")], aspectRatio: .portrait, userConsented: true)
        }
        await #expect(throws: AITrendError.notAnAITrend) {
            _ = try await coordinator.generate(trend: trend(), images: [image("a")], aspectRatio: .portrait, userConsented: true)
        }
        #expect(provider.requests.isEmpty)

        _ = try await coordinator.generate(trend: ai, images: [image("a"), image("b")], aspectRatio: .portrait, userConsented: true)
        #expect(provider.requests.count == 1)
        #expect(provider.requests.first?.images.map(\.assetID) == ["a", "b"])
        #expect(provider.requests.first?.recipe == ai.recipe)
    }

    @Test("Future plans can say no without changing the engine")
    func entitlements() async {
        let ai = trend("ai", execution: .ai, privacy: .aiProvider, recipe: "golden-hour")
        let provider = RecordingProvider()
        let coordinator = AITrendCoordinator(provider: provider, entitlements: NoCredits())
        await #expect(throws: AITrendError.notEntitled(.outOfCredits)) {
            _ = try await coordinator.generate(trend: ai, images: [image("a")], aspectRatio: .portrait, userConsented: true)
        }
        #expect(provider.requests.isEmpty)
        #expect(OpenAccess().decision(forTrend: ai) == .allowed)
        #expect(OpenAccess().decisionForMemoryBook() == .allowed)
    }

    func image(_ id: String) -> AITrendInputImage {
        AITrendInputImage(assetID: id, jpegData: Data([0xFF, 0xD8]))
    }
}

/// Test-only provider: records requests and returns a fixed result. Never used by the app.
final class RecordingProvider: AITrendProvider, @unchecked Sendable {
    let name = "Recording"
    private let lock = NSLock()
    private var log: [AITrendRequest] = []

    var requests: [AITrendRequest] { lock.withLock { log } }

    func generate(_ request: AITrendRequest) async throws -> AITrendResult {
        lock.withLock { log.append(request) }
        return AITrendResult(imageData: Data([1, 2, 3]))
    }
}

struct NoCredits: CreationEntitlements {
    func decision(forTrend trend: TrendDefinition) -> EntitlementDecision { .outOfCredits }
    func decisionForMemoryBook() -> EntitlementDecision { .allowed }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
