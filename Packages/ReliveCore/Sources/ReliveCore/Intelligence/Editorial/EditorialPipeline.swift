import Foundation

// MARK: - Relive's own words

/// Relive's deterministic editorial voice: warm, restrained, concise, factual. Every template
/// states only what the context holds; a template whose facts are missing is simply skipped.
/// Offline fallback, test oracle and the words shown first.
public struct DeterministicEditorialWriter: Sendable {
    public init() {}

    /// Up to a few candidate texts, best first (unvalidated: the pipeline validates them).
    public func candidates(for request: EditorialRequest) -> [String] {
        let c = request.context
        let words = Words(language: c.language)
        let name = c.tripName ?? c.singlePlace ?? c.momentName
        var result: [String] = []

        switch request.kind {
        case .title, .chapterTitle:
            if let name, let days = c.dayCount, days >= 2 {
                result.append(words.daysIn(days, name))
            }
            if let name, let month = c.months.first, c.months.count == 1 {
                result.append("\(name) · \(words.month(month.month)) \(month.year)")
            }
            if let name, let memories = c.counts.memories, memories >= 2 {
                result.append(words.memoriesFrom(memories, name))
            }
            if name == nil, let month = c.months.first, c.months.count == 1 {
                result.append(words.together(words.month(month.month)))
                result.append("\(words.month(month.month)) \(month.year)")
            }
            if name == nil, c.months.count > 1, let first = c.months.first, let last = c.months.last {
                if first.year == last.year, Set(c.months.map(\.year)).count == 1, c.months.count >= 6 {
                    result.append(words.together(String(first.year)))
                    result.append(words.our(first.year))
                } else if first.year == last.year {
                    result.append(words.fromTo(words.month(first.month), words.month(last.month)))
                }
            }
        case .subtitle, .shareCardLine:
            if let memories = c.counts.memories {
                var parts = [words.count(memories, .memory)]
                if let days = c.dayCount, days >= 2 { parts.append(words.count(days, .day)) }
                if let label = c.periodLabel { parts.append(label) }
                result.append(parts.joined(separator: " · "))
                if let label = c.periodLabel { result.append("\(words.count(memories, .memory)) · \(label)") }
            }
        case .closingLine:
            if let name { result.append(words.thatWas(name)) }
            if let month = c.months.first, c.months.count == 1 { result.append(words.thatWasYour(words.month(month.month))) }
            if let label = c.periodLabel { result.append(label) }
        case .transition:
            if let place = c.singlePlace { result.append(words.then(place)) }
            if let month = c.months.first, c.months.count == 1 { result.append(words.month(month.month)) }
        case .shortCaption:
            if let name, let label = c.periodLabel { result.append("\(name) · \(label)") }
            if let label = c.periodLabel { result.append(label) }
        }

        // Surfaces that already have a title keep it first, so nothing jumps; "Try another"
        // reaches the alternatives.
        if let factual = c.factualTitle, request.kind == .title, [.movie, .book, .story, .collage].contains(c.surface) {
            result.insert(factual, at: 0)
        }
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Rendered words for one language. Facts never change with the language; only this does.
struct Words {
    enum Noun { case memory, day }

    let language: EditorialLanguage

    func month(_ month: Int) -> String {
        let english = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let turkish = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        guard (1...12).contains(month) else { return "" }
        return language == .turkish ? turkish[month - 1] : english[month - 1]
    }

    func number(_ value: Int) -> String {
        let english = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let turkish = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz", "on"]
        let list = language == .turkish ? turkish : english
        return list.indices.contains(value) && value >= 2 ? list[value] : String(value)
    }

    func count(_ value: Int, _ noun: Noun) -> String {
        switch (language, noun) {
        case (.english, .memory): "\(value) \(value == 1 ? "memory" : "memories")"
        case (.english, .day): "\(value) \(value == 1 ? "day" : "days")"
        case (.turkish, .memory): "\(value) anı"
        case (.turkish, .day): "\(value) gün"
        }
    }

    func daysIn(_ days: Int, _ place: String) -> String {
        switch language {
        case .english: "\(number(days).capitalizedFirst) days in \(place)."
        case .turkish: "\(place)\(TurkishSuffix.locative(place)) \(number(days)) gün."
        }
    }

    func memoriesFrom(_ memories: Int, _ place: String) -> String {
        switch language {
        case .english: "\(memories) memories from \(place)."
        case .turkish: "\(place)\(TurkishSuffix.ablative(place)) \(memories) anı."
        }
    }

    func together(_ name: String) -> String {
        language == .turkish ? "\(name), birlikte." : "\(name), together."
    }

    func our(_ year: Int) -> String {
        language == .turkish ? "Bizim \(year)" : "Our \(year)"
    }

    func fromTo(_ first: String, _ last: String) -> String {
        language == .turkish ? "\(first)\(TurkishSuffix.ablative(first)) \(last)\(TurkishSuffix.dative(last))" : "From \(first) to \(last)"
    }

    func thatWas(_ name: String) -> String {
        language == .turkish ? "İşte \(name)." : "That was \(name)."
    }

    func thatWasYour(_ month: String) -> String {
        language == .turkish ? "İşte \(month)." : "That was your \(month)."
    }

    func then(_ place: String) -> String {
        language == .turkish ? "Sonra \(place)." : "Then \(place)."
    }
}

/// Turkish case endings by vowel harmony and consonant hardening ("Kaş'ta", "Bergama'da",
/// "Fethiye'den", "Eylül'den"). Proper nouns take an apostrophe.
enum TurkishSuffix {
    private static let back: Set<Character> = ["a", "ı", "o", "u"]
    private static let front: Set<Character> = ["e", "i", "ö", "ü"]
    private static let hard: Set<Character> = ["f", "s", "t", "k", "ç", "ş", "h", "p"]

    private static func lastVowelIsBack(_ word: String) -> Bool {
        for character in word.lowercased().reversed() {
            if back.contains(character) { return true }
            if front.contains(character) { return false }
        }
        return true
    }

    private static func endsHard(_ word: String) -> Bool {
        word.lowercased().last.map(hard.contains) ?? false
    }

    private static func endsWithVowel(_ word: String) -> Bool {
        word.lowercased().last.map { back.contains($0) || front.contains($0) } ?? false
    }

    static func locative(_ word: String) -> String {
        "'" + (endsHard(word) ? "t" : "d") + (lastVowelIsBack(word) ? "a" : "e")
    }

    static func ablative(_ word: String) -> String {
        locative(word) + "n"
    }

    static func dative(_ word: String) -> String {
        "'" + (endsWithVowel(word) ? "y" : "") + (lastVowelIsBack(word) ? "a" : "e")
    }
}

// MARK: - Providers

/// A language model that can propose candidate wording on the device (or a fake in tests). Its
/// output is never shown directly: the pipeline validates every candidate.
public protocol EditorialModelProviding: Sendable {
    /// For diagnostics and analytics ("apple-on-device", "fake").
    var name: String { get }
    /// Whether it can run here and now (hardware, OS, language, settings).
    func isAvailable() async -> Bool
    func candidates(for request: EditorialRequest) async throws -> [String]
}

// MARK: - Pipeline

/// facts → provider → candidates → validator → accepted text, or Relive's own words.
///
/// Deterministic results are immediate and cached by request (the facts, not the screen), so a
/// redraw never regenerates text. A model, when available, only adds validated alternatives
/// after Relive's first choice: what is on screen doesn't jump.
/// What happened inside the pipeline, for local analytics. Codes only: never the text.
public enum EditorialEvent: Hashable, Sendable {
    case requested(surface: EditorialSurface, kind: EditorialRequestKind, provider: String, variants: Int)
    case candidateAccepted(surface: EditorialSurface, kind: EditorialRequestKind, provider: String)
    case candidateRejected(surface: EditorialSurface, kind: EditorialRequestKind, provider: String, reason: EditorialRejection)
    case fallbackUsed(surface: EditorialSurface, kind: EditorialRequestKind, reason: String)

    public var analyticsName: AnalyticsEventName {
        switch self {
        case .requested: .editorialRequested
        case .candidateAccepted: .editorialCandidateAccepted
        case .candidateRejected: .editorialCandidateRejected
        case .fallbackUsed: .editorialFallbackUsed
        }
    }

    /// Non-identifying properties.
    public var analyticsProperties: [String: String] {
        switch self {
        case .requested(let surface, let kind, let provider, let variants):
            ["surface": surface.rawValue, "kind": kind.rawValue, "provider": provider, "variants": String(variants)]
        case .candidateAccepted(let surface, let kind, let provider):
            ["surface": surface.rawValue, "kind": kind.rawValue, "provider": provider]
        case .candidateRejected(let surface, let kind, let provider, let reason):
            ["surface": surface.rawValue, "kind": kind.rawValue, "provider": provider, "reason": reason.rawValue]
        case .fallbackUsed(let surface, let kind, let reason):
            ["surface": surface.rawValue, "kind": kind.rawValue, "reason": reason]
        }
    }
}

public final class EditorialPipeline: @unchecked Sendable {
    public static let shared = EditorialPipeline()
    /// How many variants "Try another" cycles through at most.
    public static let maximumVariants = 3

    private let writer = DeterministicEditorialWriter()
    private let validator = EditorialValidator()
    private let lock = NSLock()
    private var cache: [EditorialRequest: EditorialResult] = [:]
    private var order: [EditorialRequest] = []
    private let capacity: Int
    private(set) var hits = 0
    private(set) var misses = 0

    private var observer: (@Sendable (EditorialEvent) -> Void)?

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    /// Receives what happens (the app forwards it to local analytics). Codes only.
    public func observe(_ observer: (@Sendable (EditorialEvent) -> Void)?) {
        lock.withLock { self.observer = observer }
    }

    func emit(_ event: EditorialEvent) {
        lock.withLock { observer }?(event)
    }

    /// Relive's own words for `request`, validated, from the cache when the facts are the same.
    public func result(for request: EditorialRequest) -> EditorialResult {
        if let cached = lock.withLock({ cache[request] }) {
            lock.withLock { hits += 1 }
            return cached
        }
        let candidates = writer.candidates(for: request).map { EditorialCandidate(text: $0, provider: "deterministic") }
        var accepted: [String] = []
        var rejections: [EditorialRejection] = []
        for candidate in candidates {
            let found = validator.rejections(for: candidate, request: request)
            if found.isEmpty { accepted.append(candidate.text) } else { rejections += found }
        }
        let fallback = request.context.factualTitle ?? request.context.periodLabel ?? ""
        let variants = Array((accepted.isEmpty ? [fallback] : accepted).prefix(Self.maximumVariants))
        let result = EditorialResult(text: variants.first ?? fallback, variants: variants, provider: "deterministic", usedFallback: accepted.isEmpty, rejections: rejections)
        IntelligenceDiagnostics.emit("editorial_request surface=\(request.context.surface.rawValue) kind=\(request.kind.rawValue) provider=deterministic factCount=\(request.context.facts.count) variants=\(variants.count)")
        emit(.requested(surface: request.context.surface, kind: request.kind, provider: "deterministic", variants: variants.count))
        if accepted.isEmpty {
            emit(.fallbackUsed(surface: request.context.surface, kind: request.kind, reason: rejections.first?.rawValue ?? "noFacts"))
        }
        lock.withLock {
            misses += 1
            cache[request] = result
            order.append(request)
            if order.count > capacity {
                cache[order.removeFirst()] = nil
            }
        }
        return result
    }

    /// Adds a model's candidates to Relive's own words: each is validated; accepted ones become
    /// further variants after the first. Refused ones are only counted, never shown or logged.
    public func merging(_ base: EditorialResult, candidates: [EditorialCandidate], request: EditorialRequest) -> EditorialResult {
        var result = base
        var accepted = 0
        for candidate in candidates.prefix(6) {
            let found = validator.rejections(for: candidate, request: request)
            IntelligenceDiagnostics.emit("editorial_validation surface=\(request.context.surface.rawValue) kind=\(request.kind.rawValue) provider=\(candidate.provider) accepted=\(found.isEmpty) reason=\(found.first?.rawValue ?? "none")")
            if let reason = found.first {
                emit(.candidateRejected(surface: request.context.surface, kind: request.kind, provider: candidate.provider, reason: reason))
            } else {
                emit(.candidateAccepted(surface: request.context.surface, kind: request.kind, provider: candidate.provider))
            }
            if found.isEmpty {
                let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
                // After Relive's first choice (what is shown never jumps), before its other
                // alternatives; still at most `maximumVariants`.
                if !result.variants.contains(text) {
                    result.variants.insert(text, at: min(accepted + 1, result.variants.count))
                    result.variants = Array(result.variants.prefix(Self.maximumVariants))
                    accepted += 1
                    result.provider = candidate.provider
                }
            } else {
                result.rejections += found
            }
        }
        return result
    }

    /// Keeps an enhanced result for `request` (the facts are the same, so are the words).
    public func remember(_ result: EditorialResult, for request: EditorialRequest) {
        lock.withLock {
            if cache[request] == nil {
                order.append(request)
                if order.count > capacity { cache[order.removeFirst()] = nil }
            }
            cache[request] = result
        }
    }

    var cacheStatistics: (hits: Int, misses: Int, entries: Int) {
        lock.withLock { (hits, misses, cache.count) }
    }

    /// Forget cached words (e.g. Start Over).
    public func clear() {
        lock.withLock {
            cache = [:]
            order = []
        }
    }
}

/// Chooses who writes: Relive's own words always (immediately), and an on-device model's
/// validated alternatives when one is available. Never throws, never blocks the caller's first
/// words, never needs a network.
public struct EditorialRouter: Sendable {
    public var pipeline: EditorialPipeline
    public var model: (any EditorialModelProviding)?

    public init(pipeline: EditorialPipeline = .shared, model: (any EditorialModelProviding)? = nil) {
        self.pipeline = pipeline
        self.model = model
    }

    /// Relive's own words, at once.
    public func immediate(_ request: EditorialRequest) -> EditorialResult {
        pipeline.result(for: request)
    }

    /// Relive's own words plus a model's validated alternatives, if a model is available. On any
    /// failure (unavailable, error, everything refused) the deterministic result is returned.
    public func enhanced(_ request: EditorialRequest) async -> EditorialResult {
        let base = pipeline.result(for: request)
        // Already enhanced for these facts: nothing is generated again.
        guard let model, base.provider == "deterministic" else { return base }
        guard await model.isAvailable() else {
            IntelligenceDiagnostics.emit("editorial_fallback surface=\(request.context.surface.rawValue) kind=\(request.kind.rawValue) provider=\(model.name) reason=unavailable")
            pipeline.emit(.fallbackUsed(surface: request.context.surface, kind: request.kind, reason: "unavailable"))
            return base
        }
        do {
            let texts = try await model.candidates(for: request)
            let merged = pipeline.merging(base, candidates: texts.map { EditorialCandidate(text: $0, provider: model.name) }, request: request)
            // Kept, so a redraw (and every surface asking for the same facts) reuses it.
            pipeline.remember(merged, for: request)
            return merged
        } catch {
            IntelligenceDiagnostics.emit("editorial_fallback surface=\(request.context.surface.rawValue) kind=\(request.kind.rawValue) provider=\(model.name) reason=error")
            pipeline.emit(.fallbackUsed(surface: request.context.surface, kind: request.kind, reason: "error"))
            return base
        }
    }
}

// MARK: - Recap facts as editorial context

extension EditorialFacts {
    /// The same facts as a shared editorial context, so recap text goes through the one
    /// validator every surface uses.
    public func editorialContext(surface: EditorialSurface = .recap) -> EditorialContext {
        var phrases: [String] = []
        switch self {
        case .monthOpening(let month, let year, _, _, _): phrases = [month, "\(month) \(year)"]
        case .yearOpening: phrases = []
        case .firstMemory(let period, _, let date, let place): phrases = [period, date] + [place].compactMap { $0 }
        case .trip(let name, _, _, let date): phrases = [name] + [date].compactMap { $0 }
        case .repeatedPlace(let place, _, _, _): phrases = [place]
        case .busyDay(let date, _, _): phrases = [date]
        case .people, .favorites: phrases = []
        case .frames(let period, _): phrases = [period]
        case .places: phrases = []
        case .timeline(let period, _): phrases = [period]
        case .numbers: phrases = []
        case .monthByMonth: phrases = []
        case .compact(let period, _, _, _): phrases = [period]
        case .closing(let period, _, _, _, _): phrases = [period]
        }
        var tripName: String?
        if case .trip(let name, _, _, _) = self { tripName = name }
        return EditorialContext(surface: surface, tripName: tripName, knownPhrases: phrases, extraNumbers: allowedNumbers)
    }
}
