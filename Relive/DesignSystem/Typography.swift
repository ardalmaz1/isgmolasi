import SwiftUI

/// Editorial typography built on system fonts: New York (serif) for headlines and titles,
/// San Francisco for everything functional. All styles scale with Dynamic Type.
enum Typography {
    static let display = Font.system(.largeTitle, design: .serif)
    static let title = Font.system(.title, design: .serif)
    static let title2 = Font.system(.title2, design: .serif)
    static let title3 = Font.system(.title3, design: .serif)
    static let body = Font.system(.body)
    static let bodySerif = Font.system(.body, design: .serif)
    static let callout = Font.system(.callout)
    static let subheadline = Font.system(.subheadline)
    static let footnote = Font.system(.footnote)
    /// Small uppercase labels ("FOUND FOR YOU").
    static let eyebrow = Font.system(.caption, design: .default).weight(.semibold)
    static let button = Font.system(.body).weight(.semibold)
}

/// Spacing scale.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Standard horizontal margin for screen content.
    static let screenMargin: CGFloat = 20
}

enum Radius {
    /// Photos get a small radius — closer to a printed photo than to an app tile.
    static let photo: CGFloat = 6
    static let card: CGFloat = 14
    static let button: CGFloat = 14
}

extension View {
    /// Uppercase, tracked label used above sections.
    func eyebrowStyle() -> some View {
        font(Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Palette.textSecondary)
    }

    /// The app's warm background, extended under safe areas.
    func reliveBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}
