import SwiftUI
import UIKit

/// The Yuvi icon, drawn (`yuvi-ikon.svg`): a clay tile, a paper door, and the Y whose two arms
/// meet in one stem. Used by the opening and by the small mark on everything Yuvi exports.
struct YuviLogo: View {
    var tile: Color = Palette.accent
    var door: Color = Palette.background
    /// 0...1: how far the door has risen (the opening animates it).
    var doorRise: CGFloat = 1
    /// 0...1: how much of the Y is drawn.
    var yDrawn: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 1024
            ZStack {
                tile
                YuviDoor()
                    .fill(door)
                    .scaleEffect(x: 1, y: doorRise, anchor: .bottom)
                    .opacity(doorRise > 0 ? 1 : 0)
                // Both arms draw at once and meet in the stem.
                ForEach([YuviY.Arm.left, .right], id: \.self) { arm in
                    YuviY(arm: arm)
                        .trim(from: 0, to: yDrawn)
                        .stroke(tile, style: StrokeStyle(lineWidth: 64 * unit, lineCap: .round, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 230 * unit, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The small "yuvi" mark in a corner of shared images and movies: the icon and the lowercase
/// wordmark. On a pill of paper when it sits over photos, so it reads on any picture.
struct YuviMark: View {
    /// Height of the icon, in the canvas's design points.
    var height: CGFloat = 30
    var onPill = false

    private static let clay = Color(red: 0.545, green: 0.353, blue: 0.235)
    private static let paper = Color(red: 0.969, green: 0.957, blue: 0.937)
    private static let ink = Color(red: 0.12, green: 0.11, blue: 0.1)

    var body: some View {
        HStack(spacing: height * 0.3) {
            YuviLogo(tile: Self.clay, door: Self.paper)
                .frame(width: height, height: height)
            Text("yuvi")
                .font(.system(size: height * 0.92, weight: .medium, design: .serif))
                .foregroundStyle(Self.ink.opacity(onPill ? 0.9 : 0.75))
        }
        .padding(.horizontal, onPill ? height * 0.45 : 0)
        .padding(.vertical, onPill ? height * 0.28 : 0)
        .background {
            if onPill { Capsule().fill(Self.paper.opacity(0.9)) }
        }
        .fixedSize()
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }

    /// The mark as an image, for drawing into movie frames.
    @MainActor
    static func image(height: CGFloat, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: YuviMark(height: height, onPill: true))
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// The arched door of the icon, in the icon's 1024-point space.
struct YuviDoor: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 1024
        var path = Path()
        path.move(to: CGPoint(x: 284 * unit, y: 840 * unit))
        path.addLine(to: CGPoint(x: 284 * unit, y: 404 * unit))
        path.addArc(center: CGPoint(x: 512 * unit, y: 404 * unit), radius: 228 * unit, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: 740 * unit, y: 840 * unit))
        path.closeSubpath()
        return path
    }
}

/// One arm of the Y; the left one goes on as the stem (two lives, one path).
struct YuviY: Shape {
    enum Arm { case left, right }
    let arm: Arm

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 1024
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
        let x: CGFloat = arm == .left ? 406 : 618
        var path = Path()
        path.move(to: point(x, 356))
        path.addCurve(to: point(512, 594), control1: point(x, 486), control2: point(512, 500))
        if arm == .left { path.addLine(to: point(512, 880)) }
        return path
    }
}
