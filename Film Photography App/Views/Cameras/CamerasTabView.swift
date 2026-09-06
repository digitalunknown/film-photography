import SwiftUI

struct CamerasTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedCamera: Camera?
    @State private var cameraToDelete: Camera?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.cameras.isEmpty {
                        InstrumentEmptyState(
                            message: "No cameras in your collection. Add a body to start tracking what's loaded.",
                            primaryAction: "Add camera",
                            primaryHandler: { store.showingAddCamera = true }
                        )
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.top, AppTheme.Spacing.sm)
                    } else {
                        ForEach(Array(visibleSections.enumerated()), id: \.element.title) { index, section in
                            if index > 0 {
                                HairlineRule()
                                    .padding(.horizontal, AppTheme.horizontalPadding)
                                    .padding(.vertical, AppTheme.Spacing.lg)
                            }

                            cameraSection(
                                title: section.title,
                                cameras: section.cameras,
                                isFirst: index == 0
                            )
                        }
                    }
                }
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .instrumentScreen()
            .instrumentTabNavigation(title: "My Cameras") {
                store.showingAddCamera = true
            }
            .navigationDestination(item: $selectedCamera) { camera in
                CameraDetailView(cameraId: camera.id)
            }
            .alert("Delete camera?", isPresented: deleteCameraBinding) {
                Button("Delete", role: .destructive) {
                    if let camera = cameraToDelete {
                        store.deleteCamera(camera.id)
                    }
                    cameraToDelete = nil
                }
                Button("Cancel", role: .cancel) { cameraToDelete = nil }
            } message: {
                if let camera = cameraToDelete {
                    if store.loadedRoll(for: camera.id) != nil {
                        Text("\(camera.name) has a loaded roll that will also be deleted.")
                    } else {
                        Text("\(camera.name) will be removed from your collection.")
                    }
                }
            }
        }
    }

    private var deleteCameraBinding: Binding<Bool> {
        Binding(
            get: { cameraToDelete != nil },
            set: { if !$0 { cameraToDelete = nil } }
        )
    }

    private var visibleSections: [(title: String, cameras: [Camera])] {
        let loaded = sortedCameras.filter { store.loadedRoll(for: $0.id) != nil }
        let empty = sortedCameras.filter { store.loadedRoll(for: $0.id) == nil }
        var sections: [(String, [Camera])] = []
        if !loaded.isEmpty {
            sections.append(("Loaded (\(loaded.count))", loaded))
        }
        if !empty.isEmpty {
            sections.append(("Empty (\(empty.count))", empty))
        }
        return sections
    }

    private var sortedCameras: [Camera] {
        store.cameras.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func cameraSection(title: String, cameras: [Camera], isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: title)
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, isFirst ? AppTheme.Spacing.sm : 0)
                .padding(.bottom, AppTheme.Spacing.sm)

            ForEach(Array(cameras.enumerated()), id: \.element.id) { index, camera in
                CameraLedgerRow(camera: camera)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedCamera = camera }
                    .contextMenu {
                        Button(destructive: "Delete", lucide: .trash) {
                            cameraToDelete = camera
                        }
                        .font(AppType.body)
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.vertical, AppTheme.Spacing.sm)

                if index < cameras.count - 1 {
                    HairlineRule()
                        .padding(.horizontal, AppTheme.horizontalPadding)
                }
            }
        }
    }
}

#Preview {
    CamerasTabView()
        .environment(AppStore())
}
