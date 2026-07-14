import SwiftUI
import UIKit

enum AppTheme {
    static let bg = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.541, green: 0.541, blue: 0.557) // ~#8A8A8E
    static let textTertiary = Color(red: 0.282, green: 0.282, blue: 0.290) // ~#48484A
    static let rule = Color(red: 0.173, green: 0.173, blue: 0.180) // ~#2C2C2E

    static let horizontalPadding: CGFloat = 20

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let rowSpacing = Spacing.md
    static let sectionSpacing = Spacing.xl

    /// Apply Space Mono to navigation titles and other UIKit chrome once at launch.
    static func applyTypography() {
        let regular = UIFont(name: InstrumentFont.regularName, size: 17)
            ?? .monospacedSystemFont(ofSize: 17, weight: .regular)
        let bold = UIFont(name: InstrumentFont.boldName, size: 34)
            ?? .monospacedSystemFont(ofSize: 34, weight: .bold)
        let barRegular = UIFont(name: InstrumentFont.regularName, size: 13)
            ?? .monospacedSystemFont(ofSize: 13, weight: .regular)

        // Font only — avoid replacing bar appearances so Liquid Glass stays intact.
        let navBar = UINavigationBar.appearance()
        navBar.titleTextAttributes = [.font: regular]
        navBar.largeTitleTextAttributes = [.font: bold]

        let tabAttrs: [NSAttributedString.Key: Any] = [.font: barRegular]
        let tabItem = UITabBarItem.appearance()
        tabItem.setTitleTextAttributes(tabAttrs, for: .normal)
        tabItem.setTitleTextAttributes(tabAttrs, for: .selected)

        UIBarButtonItem.appearance().setTitleTextAttributes([.font: barRegular], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: barRegular], for: .highlighted)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: barRegular], for: .disabled)
    }
}

enum InstrumentFont {
    static let regularName = "SpaceMono-Regular"
    static let boldName = "SpaceMono-Bold"
    static let italicName = "SpaceMono-Italic"
    static let boldItalicName = "SpaceMono-BoldItalic"

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom(size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom(size, weight: weight)
    }

    private static func custom(_ size: CGFloat, weight: Font.Weight) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold:
            name = boldName
        default:
            name = regularName
        }
        return .custom(name, size: size)
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
                        Button("Add", systemImage: "plus", action: addAction)
                    }
                }
            }
    }

    func instrumentDetailNavigation(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
