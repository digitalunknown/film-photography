import SwiftUI

/// The app's colour system. Shared with the widget.
///
/// Two complete schemes live side by side so the app can be switched wholesale while we
/// decide which one to keep. `neutral` is the current Figma palette; `blue` is the
/// earlier blue-tinted one. Flipping `scheme` moves every surface, text colour, and dial
/// at once — nothing else in the app hardcodes a palette colour.
enum AppPalette {
    enum Scheme {
        case neutral
        case blue
    }

    /// The active scheme. Change this one line to swap the whole app.
    static let scheme: Scheme = .neutral

    /// `#E00E19` — expired tags and critical highlights. Shared by both schemes: the
    /// Figma palette has no red of its own, and this one is semantic rather than
    /// decorative.
    static let accent = Color(hex: 0xE0_0E_19)

    /// Screen background.
    static var bg: Color {
        switch scheme {
        case .neutral: Color(hex: 0x0A_0A_0A)
        case .blue: Color(hex: 0x0A_0F_15)
        }
    }

    /// Recessed surfaces, film-strip chrome, banners.
    static var surface: Color {
        switch scheme {
        case .neutral: Color(hex: 0x17_17_17)
        case .blue: Color(hex: 0x21_25_31)
        }
    }

    /// Dial faces. The blue scheme cut these below the sheet; with a near-black
    /// background there is no room left underneath, so the neutral scheme lifts them
    /// instead and lets the raised panel read as the recess.
    static var well: Color {
        switch scheme {
        case .neutral: Color(hex: 0x26_26_26)
        case .blue: Color(hex: 0x07_0B_10)
        }
    }

    /// Titles, values, active icons.
    static var textPrimary: Color {
        switch scheme {
        case .neutral: Color(hex: 0xF5_F5_F5)
        case .blue: Color(hex: 0xF0_F1_F5)
        }
    }

    /// Labels, metadata, inactive chrome.
    static var textSecondary: Color {
        switch scheme {
        case .neutral: Color(hex: 0x8A_8A_8A)
        case .blue: Color(hex: 0x65_70_84)
        }
    }

    /// The film canister's plastic body. Tracks `surface` in spirit, but the 3D shading
    /// multiplies this colour's HSB brightness, and it was tuned against the blue
    /// scheme's lighter surface. The neutral value therefore matches that brightness
    /// (0.192) rather than following `surface` down, which would halve the film's
    /// lightness and undo the tuning.
    static var canisterBody: Color {
        switch scheme {
        case .neutral: Color(hex: 0x31_31_31)
        case .blue: Color(hex: 0x21_25_31)
        }
    }

    /// Dial needles marking the value currently selected.
    static var indicator: Color {
        switch scheme {
        case .neutral: Color(hex: 0xF6_A8_00)
        case .blue: Color(hex: 0xFF_B1_15)
        }
    }

    /// `textPrimary` at 10% — the single divider/hairline colour.
    static var rule: Color { textPrimary.opacity(0.10) }
}

extension Color {
    /// 24-bit RGB, written the way the Figma reports it — e.g. `0x0A_0A_0A`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
