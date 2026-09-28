import ReliveCore
import SwiftUI

/// Previews the share card and hands it to the system share sheet.
struct ShareMomentView: View {
    let moment: Moment

    @Environment(StoryStore.self) private var store
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss
    @State private var card: UIImage?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                Group {
                    if let card {
                        Image(uiImage: card)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                            .accessibilityLabel("Share card: \(shareTitle)")
                    } else if failed {
                        QuietMessageView(title: "Couldn’t make a card", message: "This photo isn’t available right now.")
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)

                Button {
                    share()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.relivePrimary)
                .disabled(card == nil)

                Text("Your partner doesn’t need Relive to see it.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(Spacing.screenMargin)
            .reliveBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await renderCard() }
    }

    /// "KAŞ" / "August 2025"
    private var shareTitle: String {
        moment.place?.name ?? store.chapter(for: moment)?.place?.name ?? moment.title.primary
    }

    private var shareSubtitle: String? {
        moment.startDate.map(DateText.monthYear)
    }

    private func renderCard() async {
        guard let hero = store.heroAssetID(for: moment),
              let photo = await loader.image(for: hero, pixelSize: CGSize(width: 1600, height: 1600)) else {
            failed = true
            return
        }
        card = ShareCardRenderer.render(photo: photo, title: shareTitle, subtitle: shareSubtitle)
        failed = card == nil
    }

    private func share() {
        guard let card else { return }
        SystemPresenter.share(items: [card]) { completed, activity in
            guard completed else { return }
            analytics.track(.memoryShared, ["activity": activity ?? "unknown"])
        }
    }
}
