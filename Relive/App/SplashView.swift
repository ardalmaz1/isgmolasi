import SwiftUI

/// The opening: the door rises, the Y draws itself (two lives, one path), then "yuvi" and the
/// line under it. It stays until `isReady` (launch knows whether to show the app or the wall)
/// and at least the animation has played; a tap skips the rest. Same background as the system
/// launch screen, so there is no seam.
struct SplashView: View {
    /// Whether what's behind the splash is ready to be shown.
    let isReady: Bool
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tile = false
    @State private var door = false
    @State private var yDrawn = false
    @State private var words = false
    @State private var played = false
    @State private var leaving = false

    /// Never wait longer than this for `isReady`: the app or the wall shows its own loading.
    private static let longestWait: Duration = .seconds(2)

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.l) {
                logo
                    .frame(width: 112, height: 112)
                    .scaleEffect(tile ? 1 : 0.86)
                    .opacity(tile ? 1 : 0)
                VStack(spacing: Spacing.xs) {
                    Text("yuvi")
                        .font(.system(size: 44, weight: .medium, design: .serif))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Our story, together")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                }
                .opacity(words ? 1 : 0)
                .offset(y: words ? 0 : 8)
            }
            .scaleEffect(leaving ? 1.04 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yuvi. Our story, together")
        .accessibilityIdentifier("splash")
        .task { await play() }
        .onChange(of: isReady) { _, ready in
            if ready, played { finish() }
        }
    }

    /// The app icon, drawn: clay tile, paper door, clay Y.
    private var logo: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 1024
            ZStack {
                RoundedRectangle(cornerRadius: 230 * unit, style: .continuous)
                    .fill(Palette.accent)
                YuviDoor()
                    .fill(Palette.background)
                    .scaleEffect(x: 1, y: door ? 1 : 0, anchor: .bottom)
                    .opacity(door ? 1 : 0)
                // Both arms draw at once and meet in the stem.
                ForEach([YuviY.Arm.left, .right], id: \.self) { arm in
                    YuviY(arm: arm)
                        .trim(from: 0, to: yDrawn ? 1 : 0)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 64 * unit, lineCap: .round, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 230 * unit, style: .continuous))
        }
    }

    private func play() async {
        if reduceMotion {
            tile = true; door = true; yDrawn = true
            withAnimation(.easeOut(duration: 0.3)) { words = true }
            try? await Task.sleep(for: .seconds(0.9))
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { tile = true }
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.easeOut(duration: 0.45)) { door = true }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.easeInOut(duration: 0.6)) { yDrawn = true }
            try? await Task.sleep(for: .seconds(0.45))
            withAnimation(.easeOut(duration: 0.45)) { words = true }
            try? await Task.sleep(for: .seconds(0.8))
        }
        played = true
        if isReady { return finish() }
        try? await Task.sleep(for: Self.longestWait)
        finish()
    }

    private func finish() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.4)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.4))
            onFinish()
        }
    }
}

/// The arched door of the icon, in the icon's 1024-point space (`yuvi-ikon.svg`).
private struct YuviDoor: Shape {
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
private struct YuviY: Shape {
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
