import AVKit
import ReliveCore
import SwiftUI

/// Full-screen, swipeable photos and videos of one moment. The heart favorites the memory on
/// screen (in Relive only).
struct AssetViewer: View {
    let assets: [MemoryAsset]
    let startAssetID: AssetID

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: AssetID = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(assets) { asset in
                    Group {
                        if asset.kind == .video {
                            VideoPage(asset: asset, isCurrent: asset.id == currentID)
                        } else {
                            AssetImageView(assetID: asset.id, contentMode: .fit, quality: 1.5)
                                .background(Color.black)
                        }
                    }
                    .tag(asset.id)
                    .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack(spacing: Spacing.s) {
                if !currentID.isEmpty {
                    FavoriteButton(kind: .memory, identifier: currentID, tint: .white, accessibilityID: "photoFavorite")
                        .background(.black.opacity(0.35), in: Circle())
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.trailing, Spacing.m)

            if let caption {
                Text(caption)
                    .font(Typography.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Spacing.l)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { currentID = startAssetID }
        .statusBarHidden()
    }

    private var caption: String? {
        guard let asset = assets.first(where: { $0.id == currentID }), let date = asset.creationDate else { return nil }
        return date.formatted(date: .long, time: .shortened)
    }
}

/// Streams a video from the library when its page is visible.
private struct VideoPage: View {
    let asset: MemoryAsset
    let isCurrent: Bool

    @Environment(\.photoImageLoader) private var loader
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                AssetImageView(assetID: asset.id, contentMode: .fit)
                    .background(Color.black)
                if failed {
                    Text("This video isn’t available right now.")
                        .font(Typography.callout)
                        .foregroundStyle(.white)
                        .padding(Spacing.m)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                } else if isCurrent {
                    ProgressView().tint(.white)
                }
            }
        }
        .task(id: isCurrent) {
            guard isCurrent else {
                player?.pause()
                return
            }
            if player == nil {
                if let item = await loader.playerItem(for: asset.id) {
                    player = AVPlayer(playerItem: item)
                } else {
                    failed = true
                }
            }
            player?.play()
        }
        .onDisappear { player?.pause() }
    }
}
