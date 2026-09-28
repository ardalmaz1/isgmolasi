import ReliveCore
import SwiftUI
import UIKit

/// Renders a share card entirely on device. The recipient gets an image — no link, no account,
/// no need to have Relive.
@MainActor
enum ShareCardRenderer {
    /// 4:5 portrait, the shape most messaging apps and stories show well.
    static let size = CGSize(width: 1080, height: 1350)

    static func render(photo: UIImage, title: String, subtitle: String?) -> UIImage? {
        let card = ShareCardView(photo: photo, title: title, subtitle: subtitle)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// The card itself: the photo, a warm paper strip, the place and month, a quiet question.
struct ShareCardView: View {
    let photo: UIImage
    let title: String
    let subtitle: String?

    private let paper = Color(red: 0.969, green: 0.957, blue: 0.937)
    private let ink = Color(red: 0.118, green: 0.106, blue: 0.094)

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 1080, height: 1030)
                .clipped()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title.uppercased())
                        .font(.system(size: 50, weight: .semibold, design: .serif))
                        .tracking(6)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 36, design: .serif))
                            .foregroundStyle(ink.opacity(0.75))
                    }
                    Text("Remember this? ❤️")
                        .font(.system(size: 32))
                        .foregroundStyle(ink.opacity(0.75))
                        .padding(.top, 12)
                }
                Spacer(minLength: 24)
                Text("Relive")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .tracking(2)
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
            .frame(width: 1080, height: 320, alignment: .bottomLeading)
            .background(paper)
        }
        .frame(width: 1080, height: 1350)
        .background(paper)
    }
}
