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
                        Button(role: .destructive) {
                            cameraToDelete = camera
                        } label: {
                            Label("Delete", lucide: .trash)
                        }
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

private struct CameraLedgerRow: View {
    @Environment(AppStore.self) private var store
    let camera: Camera

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            CameraPhotoPlate(photoData: camera.photoData, size: 100)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Text(camera.name)
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: AppTheme.Spacing.xs)

                    if let roll = loadedRoll {
                        Text("\(roll.frameCount)/\(roll.totalExposures)")
                            .font(AppType.title)
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    } else {
                        Text("Empty")
                            .font(AppType.title)
                            .foregroundStyle(AppTheme.textSecondary)
                            .layoutPriority(1)
                    }
                }

                if let subtitle = camera.listSubtitle {
                    Text(subtitle)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let stockName = loadedStock?.name {
                    Text(stockName)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadedRoll: Roll? { store.loadedRoll(for: camera.id) }
    private var loadedStock: FilmStock? {
        guard let roll = loadedRoll else { return nil }
        return store.stock(for: roll.stockId)
    }
}

#Preview {
    CamerasTabView()
        .environment(AppStore())
}
