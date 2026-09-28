import SwiftUI
import UIKit

/// Warm, quiet colors. Photography provides the color; the interface stays neutral.
enum Palette {
    /// Warm off-white paper / deep warm charcoal.
    static let background = Color(light: 0xF7F4EF, dark: 0x151311)
    /// Subtle warm gray for cards and grouped sections.
    static let surface = Color(light: 0xEFEAE2, dark: 0x201D1A)
    /// Shown while a photo loads.
    static let placeholder = Color(light: 0xE6E0D6, dark: 0x2A2622)
    static let textPrimary = Color(light: 0x1E1B18, dark: 0xF3EFE9)
    static let textSecondary = Color(light: 0x6B645B, dark: 0xA89F94)
    static let textTertiary = Color(light: 0x958D82, dark: 0x746C62)
    static let hairline = Color(light: 0x1E1B18, dark: 0xF3EFE9).opacity(0.12)
    /// Text drawn on top of filled primary buttons.
    static let onPrimary = Color(light: 0xF7F4EF, dark: 0x151311)
    static let accent = Color.accentColor
}

extension Color {
    /// A color that adapts to light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
