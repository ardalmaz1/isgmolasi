import Foundation
import os
import ReliveCore

/// Where this iPhone remembers its partner connection between launches. Just the small
/// `PartnerConnectionRecord` — no photos, no library data, nothing from iCloud beyond identifiers.
@MainActor
protocol PartnerConnectionCaching: AnyObject {
    func load() -> PartnerConnectionRecord?
    func save(_ record: PartnerConnectionRecord?)
}

/// A JSON file in Application Support, excluded from backups (the connection is re-established
/// from iCloud on a new iPhone; a restored stale file would claim a connection that isn't there).
@MainActor
final class FilePartnerConnectionCache: PartnerConnectionCaching {
    private let url: URL
    private static let logger = Logger(subsystem: "app.relive", category: "partner")

    init(url: URL = FilePartnerConnectionCache.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Relive", directoryHint: .isDirectory).appending(path: "PartnerConnection.json")
    }

    func load() -> PartnerConnectionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(PartnerConnectionRecord.self, from: data)
        } catch {
            Self.logger.error("Partner connection memory unreadable; starting solo")
            return nil
        }
    }

    func save(_ record: PartnerConnectionRecord?) {
        do {
            guard let record else {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = url
            try? excluded.setResourceValues(values)
        } catch {
            Self.logger.error("Couldn't save the partner connection memory")
        }
    }
}

/// In memory, for tests and previews.
@MainActor
final class InMemoryPartnerConnectionCache: PartnerConnectionCaching {
    var record: PartnerConnectionRecord?

    init(_ record: PartnerConnectionRecord? = nil) {
        self.record = record
    }

    func load() -> PartnerConnectionRecord? { record }
    func save(_ record: PartnerConnectionRecord?) { self.record = record }
}
