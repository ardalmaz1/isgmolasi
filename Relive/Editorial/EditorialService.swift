import Foundation
import os
import ReliveCore

/// The app's one door to editorial intelligence: Relive's deterministic words at once, and —
/// where Apple's on-device model can run — a few more validated alternatives for "Try another".
///
/// Never needs a network, never blocks what is on screen, never fails a feature: anything that
/// goes wrong leaves Relive's own words in place.
final class EditorialService: Sendable {
    static let shared = EditorialService(model: EditorialService.model(for: ProcessInfo.processInfo.arguments))

    let router: EditorialRouter

    init(pipeline: EditorialPipeline = .shared, model: (any EditorialModelProviding)?) {
        self.router = EditorialRouter(pipeline: pipeline, model: model)
    }

    /// Which model may add alternatives: Apple's on-device model; none when tests switch it off.
    static func model(for arguments: [String]) -> (any EditorialModelProviding)? {
        #if DEBUG
        if arguments.contains("-ReliveEditorialModelOff") { return nil }
        #endif
        return AppleOnDeviceEditorialProvider()
    }

    var providerName: String { router.model?.name ?? "deterministic" }

    /// Forwards pipeline events to local analytics (codes only, never text).
    static func connect(analytics: any AnalyticsTracking, pipeline: EditorialPipeline = .shared) {
        pipeline.observe { event in
            analytics.track(event.analyticsName, event.analyticsProperties)
        }
    }

    /// Asks the model (if any) for alternatives to `request`. Returns whether Relive now has more
    /// words for it than before (the caller then re-reads them from the pipeline's cache).
    func enhance(_ request: EditorialRequest?) async -> Bool {
        guard let request, router.model != nil else { return false }
        let before = router.immediate(request)
        let after = await router.enhanced(request)
        return after.variants != before.variants
    }

    /// One DEBUG line at launch: which provider, and whether it can run here.
    func logProvider() {
        #if DEBUG
        let model = router.model
        Task.detached {
            let code = (model as? AppleOnDeviceEditorialProvider)?.availabilityCode() ?? (model == nil ? "off" : "custom")
            IntelligenceDiagnostics.emit("editorial_provider name=\(model?.name ?? "deterministic") status=\(code)")
        }
        #endif
    }
}
