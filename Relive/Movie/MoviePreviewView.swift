import ReliveCore
import SwiftUI
import UIKit

/// Plays a movie plan live, without exporting: the same timeline and the same frame drawer as
/// the exporter, drawn small. Photos are loaded once, small, and reused.
struct MoviePreviewView: View {
    /// The Yuvi mark, as the export draws it.
    private static let mark = YuviMark.image(height: 54, scale: 2)?.cgImage

    let plan: MoviePlan
    @Binding var isPlaying: Bool
    /// Seconds into the movie when paused (set by the scene strip to show a scene).
    @Binding var position: Double

    @Environment(\.photoImageLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var images: [ImageKey: MovieSceneImages] = [:]
    @State private var playStartedAt: Date?
    @State private var playStartPosition: Double = 0

    /// What the preview shows before anything plays: the opening, title in place.
    static let posterTime = 1.7
    /// Preview pixels relative to the exported frame (small, for memory and speed).
    static let pixelScale = 0.42

    private struct ImageKey: Hashable {
        let id: AssetID
        let framing: MovieFraming
        let aspect: MovieAspect
    }

    var body: some View {
        let timeline = MovieTimeline(plan: plan)
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
                let time = currentTime(at: context.date, duration: timeline.duration)
                if let image = render(timeline: timeline, time: time, size: proxy.size) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .onChange(of: time >= timeline.duration - 0.05) { _, ended in
                            if ended, isPlaying { finish() }
                        }
                } else {
                    Color.black
                }
            }
        }
        .aspectRatio(plan.settings.aspect.ratio, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .task(id: loadKey) { await loadImages() }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                playStartPosition = position >= timeline.duration - 0.1 ? 0 : position
                playStartedAt = Date()
            } else if let started = playStartedAt {
                position = min(timeline.duration, playStartPosition + Date().timeIntervalSince(started))
                playStartedAt = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Movie preview, \(plan.scenes.count) photos, \(MovieText.durationLabel(timeline.duration))")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("moviePreview")
    }

    private var loadKey: [ImageKey] {
        plan.scenes.map { ImageKey(id: $0.assetID, framing: $0.framing, aspect: plan.settings.aspect) }
    }

    private func currentTime(at date: Date, duration: Double) -> Double {
        if isPlaying, let started = playStartedAt {
            return min(duration, playStartPosition + date.timeIntervalSince(started))
        }
        return position > 0 ? position : min(Self.posterTime, duration / 2)
    }

    private func finish() {
        isPlaying = false
        position = 0
        playStartedAt = nil
    }

    private func render(timeline: MovieTimeline, time: Double, size: CGSize) -> UIImage? {
        guard size.width > 1, size.height > 1, !plan.scenes.isEmpty else { return nil }
        let frame = timeline.frame(at: time)
        var byIndex: [Int: MovieSceneImages] = [:]
        for layer in frame.layers {
            let scene = plan.scenes[layer.sceneIndex]
            byIndex[layer.sceneIndex] = images[ImageKey(id: scene.assetID, framing: scene.framing, aspect: plan.settings.aspect)]
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(displayScale, 2)
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            MovieFrameDrawer.draw(frame, plan: plan, in: context.cgContext, size: size, images: byIndex, mark: Self.mark)
        }
    }

    /// Loads each scene's pixels once (small), opening first, then in order.
    private func loadImages() async {
        let loader = MovieImageLoader(loader: self.loader, scale: Self.pixelScale, caches: true)
        let wanted = Set(loadKey)
        images = images.filter { wanted.contains($0.key) }
        for scene in plan.scenes {
            let key = ImageKey(id: scene.assetID, framing: scene.framing, aspect: plan.settings.aspect)
            guard images[key] == nil else { continue }
            if Task.isCancelled { return }
            if let loaded = await loader.images(for: scene, aspect: plan.settings.aspect) {
                images[key] = loaded
            }
        }
    }
}

extension MovieText {
    /// "0:38".
    static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
