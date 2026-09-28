import Photos
import UIKit

/// Presents the few UIKit-only system screens Relive needs (the limited-library picker and the
/// share sheet) from whatever is currently on screen.
@MainActor
enum SystemPresenter {
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Lets a user with limited access change which photos Relive can see.
    /// Returns the identifiers newly selected in this session.
    static func presentLimitedLibraryPicker() async -> [String] {
        guard let presenter = topViewController() else { return [] }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { identifiers in
                continuation.resume(returning: identifiers)
            }
        }
    }

    /// The native share sheet. `completion` reports whether something was actually shared.
    static func share(items: [Any], completion: @escaping @MainActor (_ completed: Bool, _ activity: String?) -> Void) {
        guard let presenter = topViewController() else {
            completion(false, nil)
            return
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            let activityName = activity?.rawValue
            Task { @MainActor in completion(completed, activityName) }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
