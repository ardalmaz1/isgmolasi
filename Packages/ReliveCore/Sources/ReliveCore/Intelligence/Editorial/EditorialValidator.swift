import Foundation

/// The one gate every generated word passes, on every surface. A candidate is accepted only when
/// everything it says is supported by the context:
///
/// - numbers (digits and number words) are counts, days or years the context holds;
/// - month and weekday names are the context's own;
/// - place names and other proper nouns are ones Relive already shows for these memories;
/// - no people are named (faces are never identities);
/// - no feelings, rankings, relationship events, seasons or picture contents are claimed unless
///   the context (or the user's own words) holds them.
///
/// The user's own words are never checked: `authorship == .user` is always accepted.
/// English and Turkish are understood; facts are language-independent.
public struct EditorialValidator: Sendable {
    public init() {}

    public func rejections(for candidate: EditorialCandidate, request: EditorialRequest) -> [EditorialRejection] {
        guard candidate.authorship == .relive else { return [] }
        let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [.empty] }
        var found: [EditorialRejection] = []
        if text.count > request.maxCharacters { found.append(.tooLong) }
        found += Self.rejections(in: text, context: request.context)
        var seen = Set<EditorialRejection>()
        return found.filter { seen.insert($0).inserted }
    }

    public func accepts(_ candidate: EditorialCandidate, request: EditorialRequest) -> Bool {
        rejections(for: candidate, request: request).isEmpty
    }

    // MARK: - Checks

    static func rejections(in text: String, context: EditorialContext) -> [EditorialRejection] {
        var found: [EditorialRejection] = []
        // Words the context supports may be repeated verbatim: mask them first.
        let masked = mask(text, phrases: context.allowedPhrases + [context.userText].compactMap { $0 })
        let folded = fold(masked)
        let foldedTokens = folded.split(separator: " ").map(String.init)
        let contextFolded = fold(([context.userText, context.factualTitle, context.tripName, context.momentName, context.season] + context.places.map(Optional.some) + context.knownPhrases.map(Optional.some)).compactMap { $0 }.joined(separator: " "))

        // Feelings and rankings.
        let claims = FactualTextPolicy.violations(in: masked)
        if !claims.isEmpty {
            found.append(claims.contains(where: FactualTextPolicy.rankingClaims.contains) ? .ranking : .emotionalClaim)
            if claims.contains(where: { !FactualTextPolicy.rankingClaims.contains($0) }) { found.append(.emotionalClaim) }
        }
        // Relationship events and picture contents, unless the context itself names them.
        if Lexicon.relationshipEvents.contains(where: { contains(folded, $0) && !contains(contextFolded, $0) }) {
            found.append(.relationshipEvent)
        }
        if Lexicon.visualClaims.contains(where: { contains(folded, $0) && !contains(contextFolded, $0) }) {
            found.append(.visualClaim)
        }
        if Lexicon.seasons.contains(where: { contains(folded, $0) && !contains(contextFolded, $0) }) {
            found.append(.unsupportedSeason)
        }
        if context.tripName == nil, Lexicon.tripWords.contains(where: { contains(folded, $0) && !contains(contextFolded, $0) }) {
            found.append(.unsupportedTrip)
        }

        // Numbers: digits and number words.
        let digits = EditorialFacts.numbers(in: masked)
        let words = Set(foldedTokens.compactMap { Lexicon.numberWords[$0] })
        if !digits.isSubset(of: context.allowedNumbers) || !words.isSubset(of: context.allowedNumberWords) {
            found.append(.unsupportedNumber)
        }

        // Dates and proper nouns, from the original capitalisation.
        let allowedMonths = Set(context.months.flatMap { Lexicon.monthNames(for: $0.month) })
        let tokens = originalTokens(masked)
        for (index, token) in tokens.enumerated() {
            let key = fold(token)
            guard let first = token.first, first.isUppercase else {
                // Lowercase month/weekday names are only common words ("may", "march"); skip.
                continue
            }
            if Lexicon.allMonthNames.contains(key) {
                if !allowedMonths.contains(key) { found.append(.unsupportedDate) }
                continue
            }
            if Lexicon.weekdays.contains(key) {
                found.append(.unsupportedDate)
                continue
            }
            if Lexicon.common.contains(key) || Lexicon.numberWords[key] != nil { continue }
            // An unknown proper noun: a place Relive doesn't know, or a person it can't know.
            let previous = index > 0 ? fold(tokens[index - 1]) : ""
            let next = index + 1 < tokens.count ? fold(tokens[index + 1]) : ""
            if Lexicon.placePrepositions.contains(previous) || Lexicon.turkishPlaceSuffixes.contains(next) {
                found.append(.unsupportedPlace)
            } else {
                found.append(.unsupportedName)
            }
        }
        if found.contains(.unsupportedName) || found.contains(.unsupportedPlace),
           Lexicon.identityPatterns.contains(where: { contains(folded, $0) }) {
            found.append(.identityClaim)
        }
        return found
    }

    // MARK: - Text helpers

    /// Case- and diacritic-insensitive, letters and digits only, words separated by one space.
    static func fold(_ text: String) -> String {
        let lowered = text.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "ı")
        let folded = lowered.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
        let spaced = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    static func contains(_ folded: String, _ phrase: String) -> Bool {
        (" " + folded + " ").contains(" " + phrase + " ")
    }

    /// Removes every occurrence of the supported phrases (any case, any diacritics).
    static func mask(_ text: String, phrases: [String]) -> String {
        var result = text
        for phrase in phrases where !phrase.isEmpty {
            while let range = result.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) {
                result.replaceSubrange(range, with: " ")
            }
        }
        return result
    }

    /// Words as written (apostrophe suffixes split off: "Kaş'ta" → "Kaş", "ta").
    static func originalTokens(_ text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}

/// Word lists, folded (lowercase, no diacritics). English and Turkish.
enum Lexicon {
    static let monthsEnglish = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static let monthsTurkish = ["ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim", "kasim", "aralik"]
    static let allMonthNames = Set(monthsEnglish + monthsTurkish)

    static func monthNames(for month: Int) -> [String] {
        guard (1...12).contains(month) else { return [] }
        return [monthsEnglish[month - 1], monthsTurkish[month - 1]]
    }

    static let weekdays: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "pazartesi", "sali", "carsamba", "persembe", "cuma", "cumartesi", "pazar",
    ]

    /// Number words (not "one"/"bir"/"on": each is also an everyday word).
    static let numberWords: [String: Int] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "twenty": 20, "thirty": 30,
        "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
        "yirmi": 20, "otuz": 30,
    ]

    static let placePrepositions: Set<String> = ["in", "at", "to", "from", "near", "around", "through", "across"]
    static let turkishPlaceSuffixes: Set<String> = ["ta", "te", "da", "de", "tan", "ten", "dan", "den", "a", "e", "ya", "ye", "nda", "nde"]

    static let identityPatterns = ["you and", "and you", "sen ve", "ve sen", "siz ve", "ve siz", "ikiniz"]

    static let relationshipEvents = [
        "anniversary", "engaged", "engagement", "proposal", "proposed", "honeymoon", "wedding", "married",
        "first date", "first kiss", "moved in", "yildonumu", "balayi", "dugun", "evlilik", "evlendiniz", "ilk bulusma",
    ]

    static let visualClaims = [
        "beach", "sea", "seaside", "ocean", "sunset", "sunsets", "sunrise", "mountain", "mountains", "restaurant",
        "dinner", "party", "snow", "lake", "forest", "kiss", "kissing", "hug", "hugging", "smile", "smiling",
        "selfie", "pool", "plaj", "deniz", "gun batimi", "dag", "kumsal", "yemek", "kar", "gol", "orman",
    ]

    static let tripWords = ["trip", "trips", "journey", "vacation", "holiday", "getaway", "gezi", "tatil", "seyahat", "yolculuk"]

    static let seasons = ["summer", "winter", "spring", "autumn", "yaz", "kis", "ilkbahar", "sonbahar", "bahar"]

    /// Capitalised words that are ordinary words (title case, sentence starts), not names.
    static let common: Set<String> = [
        // English
        "a", "an", "the", "our", "your", "you", "we", "us", "my", "in", "at", "on", "of", "from", "to", "by", "for",
        "and", "with", "back", "again", "together", "still", "days", "day", "nights", "night", "weekend", "week",
        "weeks", "month", "months", "year", "years", "memory", "memories", "moment", "moments", "photo", "photos",
        "picture", "pictures", "frame", "frames", "place", "places", "trip", "trips", "journey", "stop", "stops",
        "first", "last", "here", "there", "this", "that", "these", "it", "its", "just", "few", "some", "all", "more",
        "made", "began", "begins", "ended", "ends", "shape", "counted", "numbers", "kept", "close", "ones", "once",
        "home", "away", "another", "time", "times", "little", "long", "short", "between", "across", "through",
        "until", "after", "before", "during", "since", "every", "each", "relive", "yuvi", "start", "end", "chapter",
        "story", "book", "movie", "film", "collage", "recap", "marked", "as", "favorites", "beginning", "chronology",
        "was", "were", "is", "are", "one", "where", "when", "what", "seen", "remember", "so", "far", "way", "up",
        "out", "over", "late", "early", "mid", "new", "same", "again", "two", "both", "then", "now",
        // Turkish
        "bir", "bu", "su", "o", "ve", "ile", "icinde", "gun", "gunu", "gunler", "gece", "hafta", "ay", "yil", "yili",
        "an", "anilar", "anlar", "ani", "kare", "kareler", "yer", "yerler", "gezi", "yolculuk", "birlikte", "yine",
        "tekrar", "ilk", "son", "burada", "orada", "bizim", "sizin", "senin", "hep", "her", "boyunca", "kadar",
        "sonra", "once", "biraz", "bircok", "anisi", "hatira", "hatiralar",
    ]
}
