import CloudKit
import UIKit

/// The few UIKit entry points SwiftUI doesn't offer: partner invitations opened from a link
/// (cold launch and while running) and iCloud's silent change notices. No visible notifications:
/// Relive never asks for notification permission.
@MainActor
final class ReliveAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ReliveSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return .noData }
        await PartnerInbox.shared.cloudDidChange()
        return .newData
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Silent updates are a convenience; Relive also refreshes whenever it opens.
    }
}

/// Receives an accepted invitation. iOS calls `willConnectTo` with the invitation when the link
/// launched Relive, and `userDidAcceptCloudKitShareWith` when Relive was already running.
@MainActor
final class ReliveSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Self.deliver(metadata)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Self.deliver(cloudKitShareMetadata)
    }

    private static func deliver(_ metadata: CKShare.Metadata) {
        PartnerInbox.shared.deliver(CloudKitPartnerService.invitation(from: metadata))
    }
}
