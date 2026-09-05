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
                .font(AppType.body)
                // Set once at the root rather than per scroll view: the visibility is an
                // environment value, so it reaches every scroll view and list in the app,
                // sheets included.
                .scrollIndicators(.hidden)
        }
    }
}
