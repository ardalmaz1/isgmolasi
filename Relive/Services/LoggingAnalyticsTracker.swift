import os
import ReliveCore
import SwiftUI

/// Prototype analytics: events go to the unified log only (visible in Console.app while
/// testing). A real provider can replace this without touching call sites.
struct LoggingAnalyticsTracker: AnalyticsTracking {
    private static let logger = Logger(subsystem: "app.relive", category: "analytics")

    func track(_ event: AnalyticsEvent) {
        let properties = event.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        Self.logger.notice("\(event.name.rawValue, privacy: .public) \(properties, privacy: .public)")
    }
}

extension EnvironmentValues {
    @Entry var analytics: any AnalyticsTracking = LoggingAnalyticsTracker()
}
