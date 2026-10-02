import Foundation
import Observation
import os
import ReliveCore

/// Somewhere a trend catalog can come from.
protocol TrendCatalogProviding: Sendable {
    /// The last good catalog kept on this iPhone, if any.
    func cachedCatalog() -> TrendCatalog?
    /// A fresh catalog, or nil when offline, failing, malformed or older.
    func fetchCatalog() async -> TrendCatalog?
}

/// A remote catalog: plain JSON over HTTPS, validated by `TrendCatalogParser` before use, cached
/// on device. **Not configured in v0.3** — Relive makes no network request for trends unless a
/// catalog URL is set (`ReliveTrendCatalogURL` in Info.plist), which it isn't.
///
/// A catalog is data only. It can choose among recipes compiled into the app and set plain
/// parameters; it can never deliver code.
struct RemoteTrendCatalogProvider: TrendCatalogProviding {
    private static let logger = Logger(subsystem: "app.relive", category: "trends")

    let url: URL
    let cacheURL: URL
    var session: URLSession = .shared

    /// Only https URLs are accepted.
    init?(url: URL, cacheURL: URL = RemoteTrendCatalogProvider.defaultCacheURL, session: URLSession = .shared) {
        guard url.scheme?.lowercased() == "https" else { return nil }
        self.url = url
        self.cacheURL = cacheURL
        self.session = session
    }

    /// From Info.plist; nil (and no network use) when not set.
    static func configured(bundle: Bundle = .main) -> RemoteTrendCatalogProvider? {
        guard let string = bundle.object(forInfoDictionaryKey: "ReliveTrendCatalogURL") as? String,
              let url = URL(string: string) else { return nil }
        return RemoteTrendCatalogProvider(url: url)
    }

    static var defaultCacheURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Relive", directoryHint: .isDirectory)
            .appending(path: "trend-catalog.json")
    }

    func cachedCatalog() -> TrendCatalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? TrendCatalogParser.parse(data).get().catalog
    }

    func fetchCatalog() async -> TrendCatalog? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            switch TrendCatalogParser.parse(data) {
            case .success(let parsed):
                if !parsed.rejected.isEmpty {
                    Self.logger.notice("Trend catalog: skipped \(parsed.rejected.count) invalid entries")
                }
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
                return parsed.catalog
            case .failure(let error):
                Self.logger.error("Trend catalog rejected: \(String(describing: error), privacy: .public)")
                return nil
            }
        } catch {
            Self.logger.info("Trend catalog unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// The trends Relive can show right now: the newest valid catalog (the bundled one at least),
/// filtered by what this app supports.
@Observable
@MainActor
final class TrendCatalogStore {
    private(set) var catalog: TrendCatalog
    let ai: AITrendCoordinator

    @ObservationIgnored private let bundled: TrendCatalog
    @ObservationIgnored private let remote: (any TrendCatalogProviding)?
    @ObservationIgnored private let appVersion: AppVersion?
    @ObservationIgnored private var isRefreshing = false

    init(
        bundled: TrendCatalog = StarterTrendCatalog.catalog,
        remote: (any TrendCatalogProviding)? = RemoteTrendCatalogProvider.configured(),
        ai: AITrendCoordinator = AITrendCoordinator(provider: nil),
        appVersion: AppVersion? = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    ) {
        self.bundled = bundled
        self.remote = remote
        self.ai = ai
        self.appVersion = appVersion
        self.catalog = TrendCatalogResolver.choose(bundled: bundled, cached: remote?.cachedCatalog(), fetched: nil)
    }

    /// Fetches a newer catalog when one is configured; otherwise keeps the bundled one.
    func refresh() async {
        guard let remote, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let fetched = await remote.fetchCatalog()
        catalog = TrendCatalogResolver.choose(bundled: bundled, cached: remote.cachedCatalog(), fetched: fetched)
    }

    func context(now: Date = Date()) -> TrendContext {
        TrendContext(now: now, appVersion: appVersion, recipes: TrendRecipeRegistry.supported, isAIAvailable: ai.isAvailable)
    }

    func visibleTrends(now: Date = Date()) -> [(trend: TrendDefinition, availability: TrendAvailability)] {
        TrendCatalogFilter.visibleTrends(in: catalog, context: context(now: now))
    }

    func trend(id: String) -> TrendDefinition? {
        catalog.trends.first { $0.id == id }
    }
}

/// What the trend screens should offer for a trend.
enum TrendFlowPolicy {
    enum PrimaryAction: Equatable {
        case choosePhotos
        case unavailable(String)
    }

    static func primaryAction(for trend: TrendDefinition, availability: TrendAvailability) -> PrimaryAction {
        switch availability {
        case .available:
            // An AI trend is only "available" once a provider exists; the photos then go through
            // the disclosure first (see `needsDisclosure`).
            return .choosePhotos
        case .comingSoon:
            return .unavailable("Not available yet")
        case .hidden:
            return .unavailable("Not available")
        }
    }

    /// The "About AI creations" step: only and always for trends processed by an AI provider.
    static func needsDisclosure(_ trend: TrendDefinition) -> Bool {
        TrendPrivacyGate.requiresDisclosure(trend)
    }

    static func privacyLine(for trend: TrendDefinition) -> String {
        needsDisclosure(trend)
            ? "This creation needs the photos you choose to be processed by an AI provider. Only those photos would be sent — never the rest of your library."
            : "Made on this iPhone. Your photos aren’t uploaded."
    }
}
