import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store

        TabView {
            CamerasTabView()
                .tabItem {
                    Label("Cameras", systemImage: "camera")
                }

            RollsTabView()
                .tabItem {
                    Label("Rolls", systemImage: "film")
                }

            StocksTabView()
                .tabItem {
                    Label("Stocks", systemImage: "books.vertical")
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
            LoadFlowView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
}
