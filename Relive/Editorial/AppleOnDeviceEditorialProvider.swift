import Foundation
import ReliveCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device foundation model (the FoundationModels framework, iOS 26 or later, on
/// devices with Apple Intelligence turned on) as an editorial provider.
///
/// - Runs entirely on the device: no network, no account, no API key, no cost per request.
/// - Is sent structured facts only (`EditorialPrompt`): never photos, identifiers, coordinates,
///   notes, captions or the user's own words.
/// - Only proposes: every line it returns still has to pass `EditorialValidator`, and Relive's
///   own words stay first.
/// - Anywhere it can't run (older iOS, an ineligible device, Apple Intelligence off, the model
///   still downloading, an unsupported language) it reports unavailable and Relive silently uses
///   its deterministic words.
struct AppleOnDeviceEditorialProvider: EditorialModelProviding {
    let name = "apple-on-device"

    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return false }
            return model.supportsLocale(Locale.current)
        }
        #endif
        return false
    }

    /// Why it can't run, as a code (DEBUG diagnostics only).
    func availabilityCode() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return SystemLanguageModel.default.supportsLocale(Locale.current) ? "available" : "unsupportedLocale"
            case .unavailable(.deviceNotEligible):
                return "deviceNotEligible"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "appleIntelligenceNotEnabled"
            case .unavailable(.modelNotReady):
                return "modelNotReady"
            case .unavailable:
                return "unavailable"
            }
        }
        return "osTooOld"
        #else
        return "sdkWithoutFoundationModels"
        #endif
    }

    func candidates(for request: EditorialRequest) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: EditorialPrompt.instructions(for: request.context.language))
            let options = GenerationOptions(temperature: 0.5, maximumResponseTokens: 80)
            let response = try await session.respond(to: EditorialPrompt.prompt(for: request), options: options)
            return EditorialPrompt.lines(from: response.content)
        }
        #endif
        return []
    }
}
