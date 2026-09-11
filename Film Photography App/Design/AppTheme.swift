import SwiftUI
import UIKit

enum AppTheme {
    static let bg = AppPalette.bg
    static let well = AppPalette.well
    static let surface = AppPalette.surface
    static let textPrimary = AppPalette.textPrimary
    static let textSecondary = AppPalette.textSecondary
    static let textTertiary = AppPalette.textSecondary
    static let accent = AppPalette.accent
    static let indicator = AppPalette.indicator
    static let canisterBody = AppPalette.canisterBody
    /// Hairline: `textPrimary` at 10% — every divider and hairline border in the app.
    static let rule = AppPalette.rule

    /// The one stroke weight. Every border in the app draws at this width, so panels,
    /// plates, and fields read as one family. Only the film-frame corner brackets and the
    /// circular exposure meters draw heavier, because they are marks rather than borders.
    static let strokeWidth: CGFloat = 1.25

    static let horizontalPadding: CGFloat = 20
    static let iconSize: CGFloat = 24

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let rowSpacing = Spacing.lg
    static let sectionSpacing = Spacing.xl

    /// Extra air above a screen's table of fields, on top of whatever bottom padding the
    /// block above it carries. Without it the table's first rule lands on the same 16pt
    /// rhythm as the rows inside it, so the boundary between hero and table disappears.
    static let tableGap = Spacing.lg

    /// Apply Figtree to navigation titles and other UIKit chrome once at launch.
    static func applyTypography() {
        let largeTitle = UIFont(name: InstrumentFont.boldName, size: 32)
            ?? .systemFont(ofSize: 32, weight: .bold)
        let inlineTitle = UIFont(name: InstrumentFont.semiBoldName, size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        let barRegular = UIFont(name: InstrumentFont.semiBoldName, size: 11)
            ?? .systemFont(ofSize: 11, weight: .semibold)

        // Font only — avoid replacing bar appearances so Liquid Glass stays intact.
        let navBar = UINavigationBar.appearance()
        navBar.titleTextAttributes = [.font: inlineTitle, .foregroundColor: UIColor(AppPalette.textPrimary)]
        navBar.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: UIColor(AppPalette.textPrimary)]

        let tabAttrs: [NSAttributedString.Key: Any] = [
            .font: barRegular,
            .foregroundColor: UIColor(AppPalette.textSecondary),
        ]
        let tabSelected: [NSAttributedString.Key: Any] = [
            .font: barRegular,
            .foregroundColor: UIColor(AppPalette.textPrimary),
        ]
        let tabItem = UITabBarItem.appearance()
        tabItem.setTitleTextAttributes(tabAttrs, for: .normal)
        tabItem.setTitleTextAttributes(tabSelected, for: .selected)

        // The system search field's default fill is a light grey that reads as a bright
        // slab against this palette.
        UISearchTextField.appearance().backgroundColor = UIColor(AppPalette.surface)

        UIBarButtonItem.appearance().setTitleTextAttributes([.font: inlineTitle], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: inlineTitle], for: .highlighted)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: inlineTitle], for: .disabled)
    }
}

enum AppType {
    /// 32/Bold — screen titles.
    static let largeTitle = InstrumentFont.display(32, weight: .bold)
    /// 17/SemiBold — list row titles, inline nav titles.
    static let title = InstrumentFont.display(17, weight: .semibold)
    /// 17/Regular — counter units and trailing counter copy.
    static let titleRegular = InstrumentFont.display(17, weight: .regular)
    /// 15/SemiBold — detail section headers.
    static let section = InstrumentFont.display(15, weight: .semibold)
    /// 15/Regular — detail row labels and values.
    static let body = InstrumentFont.display(15, weight: .regular)
    /// 13/SemiBold — list section headers, button labels.
    static let calloutEmphasized = InstrumentFont.display(13, weight: .semibold)
    /// 13/Regular — list secondary lines and notes.
    static let callout = InstrumentFont.display(13, weight: .regular)
    static let button = calloutEmphasized
    static let footnote = callout
    static let micro = InstrumentFont.display(11, weight: .semibold)
    /// 11/Regular — printed dial scale values.
    static let microRegular = InstrumentFont.display(11, weight: .regular)
    /// 10/SemiBold — EXPIRED tag.
    static let badge = InstrumentFont.display(10, weight: .semibold)
    /// 8/Medium — film-strip edge print (manufacturer and frame number).
    static let strip = InstrumentFont.display(8, weight: .medium)
    /// 50/Bold, 35pt line box — exposure counter.
    static let counter = InstrumentFont.display(50, weight: .bold)
    static let counterDigitHeight: CGFloat = 35
}

enum InstrumentFont {
    static let lightName = "Figtree-Light"
    static let regularName = "Figtree-Regular"
    static let mediumName = "Figtree-Medium"
    static let semiBoldName = "Figtree-SemiBold"
    static let boldName = "Figtree-Bold"
    static let italicName = "Figtree-Italic"
    static let boldItalicName = "Figtree-BoldItalic"

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom(size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom(size, weight: weight)
    }

    private static func custom(_ size: CGFloat, weight: Font.Weight) -> Font {
        .custom(postScriptName(for: weight), size: size)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return lightName
        case .medium:
            return mediumName
        case .semibold:
            return semiBoldName
        case .bold, .heavy, .black:
            return boldName
        default:
            return regularName
        }
    }
}

struct DateFormatters {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// Film box-style expiry: month and year only.
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    static let telemetry: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    /// iCloud status: `Sep 6, 2026 at 9:14 AM`.
    static let synced: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

enum ExpirationDate {
    /// Normalize to the first day of the labeled month.
    static func normalize(_ date: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// Film labeled for a month is usable through the end of that month.
    static func isExpired(_ expiryDate: Date, relativeTo now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let expiry = calendar.dateComponents([.year, .month], from: expiryDate)
        let current = calendar.dateComponents([.year, .month], from: now)
        guard let ey = expiry.year, let em = expiry.month,
              let ny = current.year, let nm = current.month else { return false }
        if ny != ey { return ny > ey }
        return nm > em
    }

    static func endOfMonth(containing date: Date) -> Date {
        let calendar = Calendar.current
        let start = normalize(date)
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: start),
              let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) else {
            return start
        }
        return end
    }
}

extension String {
    func midTruncated(head: Int = 4, tail: Int = 4) -> String {
        guard count > head + tail + 1 else { return self }
        return String(prefix(head)) + "…" + String(suffix(tail))
    }
}

extension View {
    func instrumentScreen() -> some View {
        background(AppTheme.bg)
            .scrollContentBackground(.hidden)
            .preferredColorScheme(.dark)
    }

    /// Standard navigation bar with system Liquid Glass — no custom toolbar backgrounds.
    func instrumentTabNavigation(title: String, addAction: (() -> Void)? = nil) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let addAction {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: addAction) {
                            LucideIcon(.plus)
                        }
                        .accessibilityLabel("Add")
                    }
                }
            }
    }

    func instrumentDetailNavigation(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
