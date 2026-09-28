import PhotosUI
import SwiftUI

/// "Add Memories" from anywhere in the main app: choose photos with Apple's UI, then process
/// only what changed (cached analysis is reused).
private struct AddMemoriesFlow: ViewModifier {
    @Binding var isPresented: Bool

    @Environment(StoryStore.self) private var store
    @Environment(\.analytics) private var analytics
    @State private var selection = PhotoSelectionModel()
    @State private var isProcessing = false
    @State private var showsDeniedAlert = false

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $selection.isPickerPresented,
                selection: $selection.pickerItems,
                maxSelectionCount: PhotoSelectionModel.pickerLimit,
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            )
            .onChange(of: isPresented) { _, requested in
                guard requested else { return }
                isPresented = false
                Task { await selection.choosePhotos(store: store, analytics: analytics) }
            }
            .onChange(of: selection.pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await selection.handlePickedItems(store: store, analytics: analytics) }
            }
            .onChange(of: selection.phase) { _, phase in
                switch phase {
                case .finished(let change):
                    selection.reset()
                    if change.hasChanges {
                        analytics.track(.memoriesAdded, ["added": String(change.added), "removed": String(change.removed)])
                        isProcessing = true
                    }
                case .denied:
                    selection.reset()
                    showsDeniedAlert = true
                default:
                    break
                }
            }
            .sheet(isPresented: $isProcessing) {
                ProcessingView {
                    isProcessing = false
                }
                .interactiveDismissDisabled()
            }
            .alert("Relive can’t see your photos", isPresented: $showsDeniedAlert) {
                Button("Open Settings", action: { SystemPresenter.openSettings() })
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("You can choose which photos Relive may see in Settings.")
            }
    }
}

extension View {
    func addMemoriesFlow(isPresented: Binding<Bool>) -> some View {
        modifier(AddMemoriesFlow(isPresented: isPresented))
    }
}
