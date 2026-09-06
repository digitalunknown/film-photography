import SwiftUI

/// Lucide icons bundled as template PDFs/SVGs. Default size matches Figma (24×24).
/// Icons: Lucide (https://lucide.dev), ISC License.
enum Lucide: String {
    case plus
    case film
    case camera
    case aperture
    case library
    case libraryBig = "library-big"
    case ellipsis
    case chevronsLeft = "chevrons-left"
    case chevronsUpDown = "chevrons-up-down"
    case imageUp = "image-up"
    case imageDown = "image-down"
    case share
    case scan
    case trash = "trash-2"
    case x
    case chevronRight = "chevron-right"
    case chevronDown = "chevron-down"
    case chevronLeft = "chevron-left"
    case imagePlus = "image-plus"
    case fileText = "file-text"
    case undo = "undo-2"
    case mapPin = "map-pin"
    case mapPinPlus = "map-pin-plus"
    case mapPinMinus = "map-pin-minus"
    case calendarPlus = "calendar-plus"
    case calendarMinus = "calendar-minus"
    case circleCheckBig = "circle-check-big"
    case squareCheck = "square-check"
    case squareX = "square-x"
    case gripVertical = "grip-vertical"
    case arrowUpDown = "arrow-up-down"

    var assetName: String { "lucide.\(rawValue)" }
}

struct LucideIcon: View {
    let icon: Lucide
    var size: CGFloat = AppTheme.iconSize

    init(_ icon: Lucide, size: CGFloat = AppTheme.iconSize) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

extension Image {
    init(lucide icon: Lucide) {
        self.init(icon.assetName)
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, lucide icon: Lucide) {
        self.init {
            Text(title)
        } icon: {
            Image(lucide: icon)
                .renderingMode(.template)
        }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// Mirrors `Button(_:systemImage:action:)` for menu rows using Lucide art.
    init(_ title: String, lucide icon: Lucide, action: @escaping () -> Void) {
        self.init(action: action) {
            SwiftUI.Label(title, lucide: icon)
        }
    }

    init(_ title: String, lucide icon: Lucide, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            SwiftUI.Label(title, lucide: icon)
        }
    }
}

/// Menu row for a destructive action. A menu applies its own tint to a `Label`, which
/// can leave the Lucide icon white while the title goes red. Colouring each half
/// separately keeps them on the same accent.
struct DestructiveMenuLabel: View {
    let title: String
    let icon: Lucide

    var body: some View {
        // An HStack, not a Label — menus retint Label icons to primary (white) while
        // the title takes the destructive colour. A custom row keeps both on accent.
        HStack {
            Image(lucide: icon)
                .renderingMode(.template)
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(AppType.body)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

extension Button where Label == DestructiveMenuLabel {
    /// Destructive menu row with Lucide art, red across both the title and the icon.
    init(destructive title: String, lucide icon: Lucide, action: @escaping () -> Void) {
        self.init(role: .destructive, action: action) {
            DestructiveMenuLabel(title: title, icon: icon)
        }
    }
}
