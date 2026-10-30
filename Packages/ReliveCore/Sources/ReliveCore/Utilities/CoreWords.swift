import Foundation

/// Relive's short generated words in one language: card labels, counts, fixed phrases. Turkish
/// keeps the noun singular after a number ("12 anı").
public struct CoreWords: Sendable {
    public let language: EditorialLanguage

    public init(language: EditorialLanguage = .current) {
        self.language = language
    }

    public init(locale: Locale) {
        self.language = EditorialLanguage(locale: locale)
    }

    public var isTurkish: Bool { language == .turkish }

    public func pick(_ english: String, _ turkish: String) -> String {
        isTurkish ? turkish : english
    }

    /// "1 memory", "12 memories" / "12 anı".
    public func count(_ value: Int, _ one: String, _ many: String) -> String {
        guard isTurkish else { return "\(value) \(value == 1 ? one : many)" }
        return "\(value) \(Self.turkishNouns[one] ?? one)"
    }

    private static let turkishNouns: [String: String] = [
        "memory": "anı", "moment": "an", "month": "ay", "day": "gün", "different day": "farklı gün",
        "place": "yer", "photo": "fotoğraf", "trip": "gezi", "video": "video", "page": "sayfa",
    ]
}
