import Foundation

// The integration point for AI trends. No provider ships in v0.3: there is no implementation of
// `AITrendProvider` in the app, no API key and no network call. The types exist so a provider can
// be added later — after comparing quality, identity preservation, latency, price, privacy,
// availability and terms — without changing the trend engine or the privacy flow.

/// One photo the user explicitly chose for an AI creation.
public struct AITrendInputImage: Sendable, Hashable {
    public var assetID: AssetID
    /// JPEG, already downscaled for upload.
    public var jpegData: Data

    public init(assetID: AssetID, jpegData: Data) {
        self.assetID = assetID
        self.jpegData = jpegData
    }
}

public struct AITrendRequest: Sendable, Hashable {
    public var trendID: String
    public var recipe: TrendRecipeReference
    /// Only the photos chosen for this creation — never the rest of the library.
    public var images: [AITrendInputImage]
    public var aspectRatio: CreationAspectRatio
    public var parameters: [String: String]

    public init(trendID: String, recipe: TrendRecipeReference, images: [AITrendInputImage], aspectRatio: CreationAspectRatio, parameters: [String: String]) {
        self.trendID = trendID
        self.recipe = recipe
        self.images = images
        self.aspectRatio = aspectRatio
        self.parameters = parameters
    }
}

public struct AITrendResult: Sendable, Hashable {
    public var imageData: Data
    /// The provider's job id, for support; never shown to the user.
    public var providerReference: String?

    public init(imageData: Data, providerReference: String? = nil) {
        self.imageData = imageData
        self.providerReference = providerReference
    }
}

public enum AITrendError: Error, Equatable, Sendable {
    /// No provider is configured in this build (always the case in v0.3).
    case providerNotConfigured
    /// The user hasn't agreed to send these photos to the provider.
    case consentRequired
    /// A future plan or credit check said no.
    case notEntitled(EntitlementDecision)
    case wrongPhotoCount(expected: ClosedRange<Int>, actual: Int)
    case notAnAITrend
    /// The provider refused or failed; the message is for logs, not users.
    case providerFailed(String)
}

/// A generative image service. Implementations live in the app (or a backend proxy) and are
/// chosen later; ReliveCore only defines the shape.
public protocol AITrendProvider: Sendable {
    var name: String { get }
    func generate(_ request: AITrendRequest) async throws -> AITrendResult
}

// MARK: - Entitlements (future plans and credits)

/// What a future plan or credit check decides. v0.3 has no paywall, so everything is allowed.
public enum EntitlementDecision: Hashable, Sendable {
    case allowed
    case requiresPro
    /// AI generations will cost money per image; credits make that explicit.
    case outOfCredits
}

/// The single place a future subscription or credit system plugs into creation.
public protocol CreationEntitlements: Sendable {
    func decision(forTrend trend: TrendDefinition) -> EntitlementDecision
    func decisionForMemoryBook() -> EntitlementDecision
}

/// v0.3: no plans, no limits.
public struct OpenAccess: CreationEntitlements {
    public init() {}
    public func decision(forTrend trend: TrendDefinition) -> EntitlementDecision { .allowed }
    public func decisionForMemoryBook() -> EntitlementDecision { .allowed }
}

// MARK: - Privacy and the request path

public enum TrendPrivacyGate {
    /// AI trends need the explicit disclosure; on-device trends never show it.
    public static func requiresDisclosure(_ trend: TrendDefinition) -> Bool {
        trend.execution == .ai || trend.privacy == .aiProvider
    }
}

/// The only path from an AI trend to a provider. It checks, in order: that this is an AI trend,
/// that a provider exists, that the user agreed, the photo count, and entitlements — then sends
/// exactly the chosen photos.
public struct AITrendCoordinator: Sendable {
    public var provider: (any AITrendProvider)?
    public var entitlements: any CreationEntitlements

    public init(provider: (any AITrendProvider)?, entitlements: any CreationEntitlements = OpenAccess()) {
        self.provider = provider
        self.entitlements = entitlements
    }

    public var isAvailable: Bool { provider != nil }

    public func generate(
        trend: TrendDefinition,
        images: [AITrendInputImage],
        aspectRatio: CreationAspectRatio,
        userConsented: Bool
    ) async throws -> AITrendResult {
        guard trend.execution == .ai else { throw AITrendError.notAnAITrend }
        guard let provider else { throw AITrendError.providerNotConfigured }
        guard userConsented else { throw AITrendError.consentRequired }
        guard trend.photos.range.contains(images.count) else {
            throw AITrendError.wrongPhotoCount(expected: trend.photos.range, actual: images.count)
        }
        let decision = entitlements.decision(forTrend: trend)
        guard decision == .allowed else { throw AITrendError.notEntitled(decision) }
        return try await provider.generate(AITrendRequest(
            trendID: trend.id,
            recipe: trend.recipe,
            images: images,
            aspectRatio: aspectRatio,
            parameters: trend.parameters
        ))
    }
}
