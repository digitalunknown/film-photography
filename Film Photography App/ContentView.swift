import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedTab: Tab = .film

    private enum Tab {
        case film, cameras, library
    }

    var body: some View {
        @Bindable var store = store

        TabView(selection: $selectedTab) {
            RollsTabView()
                .tabItem {
                    Label("My Film", lucide: .film)
                }
                .tag(Tab.film)

            CamerasTabView()
                .tabItem {
                    Label("My Cameras", lucide: .camera)
                }
                .tag(Tab.cameras)

            StocksTabView()
                .tabItem {
                    Label("Library", lucide: .libraryBig)
                }
                .tag(Tab.library)
        }
        .tint(AppTheme.textPrimary)
        // Fires only on an actual tab change, so re-tapping the current tab stays silent.
        .sensoryFeedback(.impact(weight: .light), trigger: selectedTab)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.showingAddCamera) {
            AddCameraView()
        }
        .sheet(item: $store.addRollEntry) { entry in
            AddRollView(entry: entry)
        }
        .sheet(isPresented: $store.showingLoadFlow) {
            LoadFlowView(startWithCamera: store.loadFlowStartWithCamera)
                .instrumentSheetChrome()
        }
        .sheet(isPresented: $store.showingSettings) {
            SettingsView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let problem = store.persistProblem {
                PersistFailureBanner(problem: problem) {
                    store.retryPersist()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
}
