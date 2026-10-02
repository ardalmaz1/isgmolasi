import Foundation

// Relive Trends: the catalog side.
//
// A *trend* is what the user sees ("B&W Editorial"). A *recipe* is how the app makes it
// ("bw-editorial@1"). Trends live in a catalog — data, not code — so a new trend can be published
// for every installed app that already implements its recipe. A catalog can only *select*
// recipes compiled into the app; it can never carry code.

/// How a trend is made.
public enum TrendExecution: String, Codable, Hashable, Sendable {
    /// Image processing on the iPhone (black & white, film colour…).
    case local
    /// A deterministic Relive layout from the chosen photos (a strip, a cover, a poster…).
    case template
    /// Needs generative image editing by an AI provider. The chosen photos would leave the iPhone.
    case ai
}

/// Where the chosen photos are processed. Shown to the user before creating.
public enum TrendPrivacy: String, Codable, Hashable, Sendable {
    case onDevice
    case aiProvider
}

/// A quiet label on a trend card. Most trends have none.
public enum TrendBadge: String, Codable, Hashable, Sendable {
    case new
    case trending
}

/// Which plan a trend belongs to. Informational in v0.3 — nothing is locked.
public enum TrendTier: String, Codable, Hashable, Sendable {
    case free
    case pro
}

/// A versioned reference to an implementation compiled into the app: "bw-editorial@1".
/// Improving a trend means publishing the same trend with a newer recipe version.
public struct TrendRecipeReference: Codable, Hashable, Sendable, CustomStringConvertible {
    public var id: String
    public var version: Int

    public init(id: String, version: Int) {
        self.id = id
        self.version = version
    }

    public var description: String { "\(id)@\(version)" }
}

public struct TrendPhotoRequirement: Codable, Hashable, Sendable {
    public var minimum: Int
    public var maximum: Int

    public init(minimum: Int, maximum: Int) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public var range: ClosedRange<Int> { minimum...max(minimum, maximum) }
}

/// One trend, as published in a catalog.
public struct TrendDefinition: Codable, Hashable, Sendable, Identifiable {
    /// Stable across recipe versions and catalog revisions.
    public var id: String
    public var name: String
    /// One line for the card.
    public var summary: String
    /// A sentence for the detail screen.
    public var detail: String?
    public var execution: TrendExecution
    public var recipe: TrendRecipeReference
    public var photos: TrendPhotoRequirement
    public var aspectRatios: [CreationAspectRatio]
    /// "Faces clearly visible." Short tips shown before choosing photos.
    public var guidance: [String]
    public var badge: TrendBadge?
    /// Higher shows first.
    public var priority: Int
    public var isActive: Bool
    public var availableFrom: Date?
    public var availableUntil: Date?
    /// The oldest app version that may show this trend ("0.3").
    public var minimumAppVersion: String?
    public var privacy: TrendPrivacy
    public var tier: TrendTier
    /// Plain values a recipe may read (e.g. "grain": "0.4"). Never code.
    public var parameters: [String: String]

    public init(
        id: String,
        name: String,
        summary: String,
        detail: String? = nil,
        execution: TrendExecution,
        recipe: TrendRecipeReference,
        photos: TrendPhotoRequirement,
        aspectRatios: [CreationAspectRatio],
        guidance: [String] = [],
        badge: TrendBadge? = nil,
        priority: Int = 0,
        isActive: Bool = true,
        availableFrom: Date? = nil,
        availableUntil: Date? = nil,
        minimumAppVersion: String? = nil,
        privacy: TrendPrivacy,
        tier: TrendTier = .free,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.detail = detail
        self.execution = execution
        self.recipe = recipe
        self.photos = photos
        self.aspectRatios = aspectRatios
        self.guidance = guidance
        self.badge = badge
        self.priority = priority
        self.isActive = isActive
        self.availableFrom = availableFrom
        self.availableUntil = availableUntil
        self.minimumAppVersion = minimumAppVersion
        self.privacy = privacy
        self.tier = tier
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, detail, execution, recipe, photos, aspectRatios, guidance, badge, priority
        case isActive, availableFrom, availableUntil, minimumAppVersion, privacy, tier, parameters
    }

    /// Optional fields may be omitted in catalog JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        execution = try container.decode(TrendExecution.self, forKey: .execution)
        recipe = try container.decode(TrendRecipeReference.self, forKey: .recipe)
        photos = try container.decode(TrendPhotoRequirement.self, forKey: .photos)
        aspectRatios = try container.decode([CreationAspectRatio].self, forKey: .aspectRatios)
        guidance = try container.decodeIfPresent([String].self, forKey: .guidance) ?? []
        badge = try container.decodeIfPresent(TrendBadge.self, forKey: .badge)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        availableFrom = try container.decodeIfPresent(Date.self, forKey: .availableFrom)
        availableUntil = try container.decodeIfPresent(Date.self, forKey: .availableUntil)
        minimumAppVersion = try container.decodeIfPresent(String.self, forKey: .minimumAppVersion)
        privacy = try container.decode(TrendPrivacy.self, forKey: .privacy)
        tier = try container.decodeIfPresent(TrendTier.self, forKey: .tier) ?? .free
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
    }
}

/// A published set of trends.
public struct TrendCatalog: Codable, Hashable, Sendable {
    /// The JSON format's version. The app rejects formats newer than it understands.
    public var schemaVersion: Int
    /// Increases with every publication; the newest valid catalog wins.
    public var revision: Int
    public var trends: [TrendDefinition]

    public init(schemaVersion: Int = TrendCatalogParser.supportedSchemaVersion, revision: Int, trends: [TrendDefinition]) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.trends = trends
    }
}

public enum TrendCatalogError: Error, Equatable, Sendable {
    /// Not JSON, or not a catalog.
    case malformed
    /// Written for a newer app than this one.
    case unsupportedSchema(Int)
}

/// Reads catalog JSON defensively. A malformed document is rejected as a whole; a single bad
/// trend is dropped and the rest are kept.
public enum TrendCatalogParser {
    public static let supportedSchemaVersion = 1

    public struct Parsed: Sendable {
        public var catalog: TrendCatalog
        /// Entries that were present but failed validation (by id, when it could be read).
        public var rejected: [String]
    }

    public static func parse(_ data: Data) -> Result<Parsed, TrendCatalogError> {
        guard data.count <= 512 * 1024 else { return .failure(.malformed) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return .failure(.malformed)
        }
        guard envelope.schemaVersion >= 1, envelope.revision >= 0 else { return .failure(.malformed) }
        guard envelope.schemaVersion <= supportedSchemaVersion else {
            return .failure(.unsupportedSchema(envelope.schemaVersion))
        }

        var trends: [TrendDefinition] = []
        var rejected: [String] = []
        var seen = Set<String>()
        for entry in envelope.trends {
            guard let trend = entry.trend else {
                rejected.append(entry.idHint ?? "?")
                continue
            }
            guard validate(trend), seen.insert(trend.id).inserted else {
                rejected.append(trend.id)
                continue
            }
            trends.append(trend)
        }
        return .success(Parsed(catalog: TrendCatalog(schemaVersion: envelope.schemaVersion, revision: envelope.revision, trends: trends), rejected: rejected))
    }

    /// Rules every published trend must meet before it can be shown.
    public static func validate(_ trend: TrendDefinition) -> Bool {
        guard isSlug(trend.id), isSlug(trend.recipe.id), trend.recipe.version >= 1 else { return false }
        guard (1...40).contains(trend.name.trimmingCharacters(in: .whitespacesAndNewlines).count) else { return false }
        guard (1...140).contains(trend.summary.trimmingCharacters(in: .whitespacesAndNewlines).count) else { return false }
        if let detail = trend.detail, detail.count > 400 { return false }
        guard trend.photos.minimum >= 1, trend.photos.maximum >= trend.photos.minimum, trend.photos.maximum <= 12 else { return false }
        guard !trend.aspectRatios.isEmpty else { return false }
        guard trend.guidance.count <= 4, trend.guidance.allSatisfy({ !$0.isEmpty && $0.count <= 120 }) else { return false }
        guard trend.parameters.count <= 16,
              trend.parameters.allSatisfy({ isSlug($0.key) && $0.value.count <= 256 }) else { return false }
        if let from = trend.availableFrom, let until = trend.availableUntil, from > until { return false }
        if let version = trend.minimumAppVersion, AppVersion(version) == nil { return false }
        // The privacy promise must match how the trend is made: AI is never "on device".
        switch trend.execution {
        case .ai: guard trend.privacy == .aiProvider else { return false }
        case .local, .template: guard trend.privacy == .onDevice else { return false }
        }
        return true
    }

    static func isSlug(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    private struct Envelope: Decodable {
        var schemaVersion: Int
        var revision: Int
        var trends: [LossyTrend]
    }

    /// Decodes one trend without failing the whole catalog.
    private struct LossyTrend: Decodable {
        var trend: TrendDefinition?
        var idHint: String?

        private struct IDOnly: Decodable { var id: String? }

        init(from decoder: Decoder) throws {
            trend = try? TrendDefinition(from: decoder)
            idHint = (try? IDOnly(from: decoder))?.id
        }
    }
}

/// A dotted version ("0.3", "1.2.1"), compared numerically.
public struct AppVersion: Comparable, Sendable {
    public var components: [Int]

    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var components: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Picks the catalog to use: the newest valid one among the bundled catalog (always there), a
/// previously downloaded copy and a fresh download.
public enum TrendCatalogResolver {
    public static func choose(bundled: TrendCatalog, cached: TrendCatalog?, fetched: TrendCatalog?) -> TrendCatalog {
        [fetched, cached].compactMap { $0 }.reduce(bundled) { best, candidate in
            candidate.revision > best.revision ? candidate : best
        }
    }
}

/// What the running app can do, for deciding which trends to show.
public struct TrendContext: Sendable {
    public var now: Date
    public var appVersion: AppVersion?
    /// Recipes compiled into this app.
    public var recipes: Set<TrendRecipeReference>
    /// An AI provider is configured (none is, in v0.3).
    public var isAIAvailable: Bool

    public init(now: Date, appVersion: AppVersion?, recipes: Set<TrendRecipeReference>, isAIAvailable: Bool) {
        self.now = now
        self.appVersion = appVersion
        self.recipes = recipes
        self.isAIAvailable = isAIAvailable
    }
}

public enum TrendAvailability: Hashable, Sendable {
    case available
    /// Shown honestly as not available yet (an AI trend without a provider).
    case comingSoon
    case hidden(HiddenReason)

    public enum HiddenReason: Hashable, Sendable {
        case inactive
        case notYetAvailable
        case expired
        case requiresNewerApp
        case unsupportedRecipe
    }

    public var isVisible: Bool {
        if case .hidden = self { return false }
        return true
    }
}

public enum TrendCatalogFilter {
    public static func availability(of trend: TrendDefinition, in context: TrendContext) -> TrendAvailability {
        guard trend.isActive else { return .hidden(.inactive) }
        if let from = trend.availableFrom, context.now < from { return .hidden(.notYetAvailable) }
        if let until = trend.availableUntil, context.now > until { return .hidden(.expired) }
        if let required = trend.minimumAppVersion.flatMap(AppVersion.init) {
            guard let app = context.appVersion, !(app < required) else { return .hidden(.requiresNewerApp) }
        }
        switch trend.execution {
        case .ai:
            // AI recipes run at the provider; without one, the trend is honestly unavailable.
            return context.isAIAvailable ? .available : .comingSoon
        case .local, .template:
            return context.recipes.contains(trend.recipe) ? .available : .hidden(.unsupportedRecipe)
        }
    }

    /// Trends to show, highest priority first (then by name), with their availability.
    public static func visibleTrends(in catalog: TrendCatalog, context: TrendContext) -> [(trend: TrendDefinition, availability: TrendAvailability)] {
        catalog.trends
            .map { ($0, availability(of: $0, in: context)) }
            .filter { $0.1.isVisible }
            .sorted { lhs, rhs in
                if lhs.0.priority != rhs.0.priority { return lhs.0.priority > rhs.0.priority }
                return lhs.0.name < rhs.0.name
            }
            .map { (trend: $0.0, availability: $0.1) }
    }
}
