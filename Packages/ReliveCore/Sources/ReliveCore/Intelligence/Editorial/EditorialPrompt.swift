import Foundation

/// What an on-device model is told: the structured facts of one request and the rules — never
/// photos, identifiers, coordinates, notes or captions. Its answer is only a proposal: every line
/// still has to pass `EditorialValidator`.
public enum EditorialPrompt {
    /// How many alternatives a model is asked for.
    public static let requestedAlternatives = 2

    public static func instructions(for language: EditorialLanguage) -> String {
        let languageName = language == .turkish ? "Turkish" : "English"
        return """
        You write very short titles for a private photo memory app used by a couple.
        Write in \(languageName). Use only the facts you are given. Never add a place, date, number, \
        person, name, season, event, feeling, ranking or anything the photos might show. \
        Do not say who is in the photos. Do not use emoji or hashtags. Warm, restrained, plain.
        Reply with one option per line and nothing else.
        """
    }

    public static func prompt(for request: EditorialRequest) -> String {
        var lines = ["Write \(requestedAlternatives) different \(description(of: request.kind)), each at most \(request.maxCharacters) characters.", "Facts:"]
        for fact in request.context.facts where fact.key != "userText" {
            lines.append("- \(fact.key): \(fact.value)")
        }
        if let label = request.context.periodLabel { lines.append("- period: \(label)") }
        if let title = request.context.factualTitle { lines.append("- current title: \(title)") }
        return lines.joined(separator: "\n")
    }

    /// The model's reply as candidate lines: list markers, numbering and quotes removed.
    public static func lines(from reply: String) -> [String] {
        reply.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            while let first = line.first, "-•*0123456789.)".contains(first) { line.removeFirst() }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: " \"“”'‘’"))
            return line.isEmpty ? nil : line
        }
        .prefix(requestedAlternatives + 1)
        .map { $0 }
    }

    private static func description(of kind: EditorialRequestKind) -> String {
        switch kind {
        case .title: "titles"
        case .subtitle: "subtitles"
        case .transition: "transition lines"
        case .chapterTitle: "chapter titles"
        case .closingLine: "closing lines"
        case .shortCaption: "captions"
        case .shareCardLine: "share card lines"
        }
    }
}
