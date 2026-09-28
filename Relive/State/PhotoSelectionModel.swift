import Foundation
import Observation
import PhotosUI
import ReliveCore
import SwiftUI

/// Drives "Choose Our Photos" and "Add Memories" using Apple's privacy-preserving selection.
///
/// - Limited access (recommended): the system's own picker defines exactly which photos Relive
///   can see, and Relive mirrors that selection.
/// - Full access: Relive still never reads the whole library; the user picks items in the
///   system `PhotosPicker` and only those identifiers are stored.
/// - Denied: nothing is read; the user is pointed to Settings.
@Observable
@MainActor
final class PhotoSelectionModel {
    enum Phase: Equatable {
        case idle
        case requestingAccess
        case importing
        case denied
        case finished(SelectionChange)
    }

    /// Recommended upper bound for one pick; the prototype is tuned for 50–500 memories.
    static let pickerLimit = 500
    /// Below this, clustering has little to work with, so we gently suggest adding more.
    static let recommendedMinimum = 30

    var phase: Phase = .idle
    var isPickerPresented = false
    var pickerItems: [PhotosPickerItem] = []

    func choosePhotos(store: StoryStore, analytics: any AnalyticsTracking) async {
        let status = store.photoLibrary.accessStatus()
        switch status {
        case .notDetermined:
            phase = .requestingAccess
            let granted = await store.photoLibrary.requestAccess()
            await handle(granted, justRequested: true, store: store, analytics: analytics)
        default:
            await handle(status, justRequested: false, store: store, analytics: analytics)
        }
    }

    /// Called when the system `PhotosPicker` returns.
    func handlePickedItems(store: StoryStore, analytics: any AnalyticsTracking) async {
        let identifiers = pickerItems.compactMap(\.itemIdentifier)
        pickerItems = []
        guard !identifiers.isEmpty else {
            phase = .idle
            return
        }
        phase = .importing
        let change = await store.importSelection(identifiers: identifiers)
        finish(change, store: store, analytics: analytics, access: "full")
    }

    func reset() {
        phase = .idle
    }

    private func handle(
        _ status: PhotoAccessStatus,
        justRequested: Bool,
        store: StoryStore,
        analytics: any AnalyticsTracking
    ) async {
        switch status {
        case .limited:
            // When access was just granted as "limited", iOS has already shown its picker.
            // Otherwise (or if nothing was chosen) let the user adjust the selection now.
            if !justRequested || (await store.photoLibrary.allAccessibleAssets()).isEmpty {
                _ = await SystemPresenter.presentLimitedLibraryPicker()
            }
            phase = .importing
            let change = await store.syncWithAccessibleAssets()
            finish(change, store: store, analytics: analytics, access: "limited")
        case .full:
            phase = .idle
            isPickerPresented = true
        case .denied, .restricted:
            phase = .denied
        case .notDetermined:
            phase = .idle
        }
    }

    private func finish(_ change: SelectionChange, store: StoryStore, analytics: any AnalyticsTracking, access: String) {
        phase = .finished(change)
        analytics.track(.photosSelected, [
            "added": String(change.added),
            "removed": String(change.removed),
            "total": String(store.selectionCount),
            "access": access,
        ])
    }
}
