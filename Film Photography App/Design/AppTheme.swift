import SwiftUI

enum AppTheme {
    static let bg = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.541, green: 0.541, blue: 0.557) // ~#8A8A8E
    static let textTertiary = Color(red: 0.282, green: 0.282, blue: 0.290) // ~#48484A
    static let rule = Color(red: 0.173, green: 0.173, blue: 0.180) // ~#2C2C2E

    static let horizontalPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 14
    static let sectionSpacing: CGFloat = 32
}

enum InstrumentFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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

    static let telemetry: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()
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
