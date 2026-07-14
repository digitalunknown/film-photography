import SwiftUI

@main
struct Film_Photography_AppApp: App {
    @State private var store = AppStore()

    init() {
        AppTheme.applyTypography()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .font(InstrumentFont.mono(13))
        }
    }
}
