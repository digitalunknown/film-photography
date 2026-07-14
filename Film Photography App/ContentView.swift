import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store

        TabView {
            RollsTabView()
                .tabItem {
                    Label("My Film", systemImage: "film")
                }

            CamerasTabView()
                .tabItem {
                    Label("My Cameras", systemImage: "camera")
                }

            StocksTabView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
        }
        .tint(AppTheme.textPrimary)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.showingAddCamera) {
            AddCameraView()
        }
        .sheet(isPresented: $store.showingAddRoll) {
            AddRollView()
        }
        .sheet(isPresented: $store.showingLoadFlow) {
            LoadFlowView(startWithCamera: store.loadFlowStartWithCamera)
                .instrumentSheetChrome()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
}
