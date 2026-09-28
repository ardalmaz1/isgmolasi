import UIKit

/// Asks iOS for a little extra time to finish work if the user leaves the app, and releases the
/// request when the work ends or the time runs out (never leaving an expired assertion, which
/// would get the app terminated).
@MainActor
final class BackgroundActivity {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // UIKit calls expiration handlers on the main thread.
            MainActor.assumeIsolated {
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
