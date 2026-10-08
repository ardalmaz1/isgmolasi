import Foundation

// Relive's commercial rule: memories are free; creating more from them is Premium.
//
// Nothing here gates a memory, a moment, a place, a note, a hidden memory, a favorite or the
// story itself — those are never Premium capabilities. Premium is asked for only when the user
// keeps (saves or shares) something Relive made, or opens the full version of a recap.

/// Something Premium unlocks. New features add a case; nothing else in the StoreKit layer
/// changes.
public enum PremiumCapability: String, CaseIterable, Codable, Sendable {
    /// Saving or sharing a Memory Collage.
    case collageExport = "collage_export"
    /// Saving or sharing Story Maker cards.
    case storyExport = "story_export"
    /// Saving or sharing a trend creation.
    case trendExport = "trend_export"
    /// Saving or sharing Memory Book pages, or the whole book.
    case memoryBookExport = "memory_book_export"
    /// A month's full recap: every highlight, its trips, and the shareable card.
    case fullMonthlyRecap = "full_monthly_recap"
    /// Our Year in full: every month, the closing, and the shareable card.
    case fullYearInReview = "full_year_in_review"
    /// Reserved for designs that become Premium-only (today every design is previewable and
    /// exportable with the export rules above).
    case premiumStyles = "premium_styles"
    /// Reserved for future passes; listed so the entitlement check already covers them.
    case madeForYou = "made_for_you"
    case memoryMovie = "memory_movie"
    case reliveAI = "relive_ai"
    case anniversaryCreations = "anniversary_creations"

    /// The first successful save or share of one of these is free, once per install.
    public var isCoveredByFreeCreation: Bool {
        switch self {
        case .collageExport, .storyExport, .trendExport: true
        default: false
        }
    }
}

/// What may happen when the user asks to keep a creation.
public enum ExportDecision: Equatable, Sendable {
    /// Premium: go ahead.
    case allowed
    /// Not Premium, but the one free creation is still available: go ahead, and record it only
    /// once the save or share succeeds.
    case allowedAsFreeCreation
    /// Show the paywall.
    case requiresPremium
}

/// The one free creation. Persisted locally; it is never reset by backgrounding, relaunching
/// or Start Over (only by deleting the app, which clears everything).
public struct FreeCreationAllowance: Codable, Equatable, Sendable {
    public var usedAt: Date?
    public var usedFor: PremiumCapability?

    public init(usedAt: Date? = nil, usedFor: PremiumCapability? = nil) {
        self.usedAt = usedAt
        self.usedFor = usedFor
    }

    public var isAvailable: Bool { usedAt == nil }

    /// Records a successful export. Only a free creation consumes the allowance: Premium
    /// exports, previews and failed exports never call this with `.allowedAsFreeCreation`.
    /// Returns true if this export used the allowance.
    @discardableResult
    public mutating func recordSuccessfulExport(of capability: PremiumCapability, decision: ExportDecision, at date: Date) -> Bool {
        guard decision == .allowedAsFreeCreation, isAvailable, capability.isCoveredByFreeCreation else { return false }
        usedAt = date
        usedFor = capability
        return true
    }
}

public enum PremiumPolicy {
    /// May the user see this in full? (Previews never ask.)
    public static func hasAccess(to capability: PremiumCapability, isPremium: Bool) -> Bool {
        isPremium
    }

    /// May the user keep (save or share) this creation now?
    public static func exportDecision(for capability: PremiumCapability, isPremium: Bool, allowance: FreeCreationAllowance) -> ExportDecision {
        if isPremium { return .allowed }
        if capability.isCoveredByFreeCreation, allowance.isAvailable { return .allowedAsFreeCreation }
        return .requiresPremium
    }
}
