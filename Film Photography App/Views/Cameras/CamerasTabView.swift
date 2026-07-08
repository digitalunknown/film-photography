import SwiftUI

struct CamerasTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedCamera: Camera?
    @State private var cameraToDelete: Camera?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.camerasSummary)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.bottom, 20)

                    HairlineRule()
                        .padding(.horizontal, AppTheme.horizontalPadding)

                    if store.cameras.isEmpty {
                        InstrumentEmptyState(
                            message: "No cameras in your collection. Add a body to start tracking what's loaded.",
                            primaryAction: "Add camera →",
                            primaryHandler: { store.showingAddCamera = true }
                        )
                        .padding(.horizontal, AppTheme.horizontalPadding)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sortedCameras.enumerated()), id: \.element.id) { index, camera in
                                CameraLedgerRow(camera: camera)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedCamera = camera }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            cameraToDelete = camera
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .padding(.horizontal, AppTheme.horizontalPadding)
                                    .padding(.vertical, AppTheme.rowSpacing)

                                if index < sortedCameras.count - 1 {
                                    HairlineRule()
                                        .padding(.horizontal, AppTheme.horizontalPadding)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .instrumentScreen()
            .instrumentTabNavigation(title: "Cameras") {
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

    private var sortedCameras: [Camera] {
        store.cameras.sorted { lhs, rhs in
            let lhsLoaded = store.loadedRoll(for: lhs.id) != nil
            let rhsLoaded = store.loadedRoll(for: rhs.id) != nil
            if lhsLoaded != rhsLoaded { return lhsLoaded }
            return lhs.name < rhs.name
        }
    }
}

private struct CameraLedgerRow: View {
    @Environment(AppStore.self) private var store
    let camera: Camera

    private let photoSize: CGFloat = 54

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CameraPhotoPlate(photoData: camera.photoData, size: photoSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(camera.name)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                if let subtitle = camera.listSubtitle {
                    Text(subtitle)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                if let roll = loadedRoll {
                    Text("\(roll.frameCount)/\(roll.totalExposures)")
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let stock = loadedStock {
                        HStack(spacing: 6) {
                            RollPlate(tint: stock.emulsionTint, size: 16)
                            Text(stock.name)
                                .font(InstrumentFont.mono(11))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("Empty")
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
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
