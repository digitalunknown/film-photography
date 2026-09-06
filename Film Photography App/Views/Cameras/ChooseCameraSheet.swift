import SwiftUI

/// Same ledger as My Cameras — photo, name, load state — plus a way to add a body
/// without leaving the picker.
struct ChooseCameraSheet: View {
    @Environment(AppStore.self) private var store

    var title: String = "Choose camera"
    var onSelect: (Camera) -> Void
    var onDismiss: () -> Void

    @State private var showingAddCamera = false

    private var sortedCameras: [Camera] {
        store.cameras.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var loadedCameras: [Camera] {
        sortedCameras.filter { store.loadedRoll(for: $0.id) != nil }
    }

    private var emptyCameras: [Camera] {
        sortedCameras.filter { store.loadedRoll(for: $0.id) == nil }
    }

    private var sections: [(title: String, cameras: [Camera])] {
        var result: [(String, [Camera])] = []
        if !loadedCameras.isEmpty {
            result.append(("Loaded (\(loadedCameras.count))", loadedCameras))
        }
        if !emptyCameras.isEmpty {
            result.append(("Empty (\(emptyCameras.count))", emptyCameras))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.cameras.isEmpty {
                        Text("No cameras in your collection.")
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, AppTheme.horizontalPadding)
                            .padding(.top, AppTheme.Spacing.lg)
                            .padding(.bottom, AppTheme.Spacing.lg)
                    } else {
                        ForEach(Array(sections.enumerated()), id: \.element.title) { index, section in
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

                    Button {
                        showingAddCamera = true
                    } label: {
                        PillButtonLabel(title: "Add Camera", icon: .camera)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, store.cameras.isEmpty ? 0 : AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
            .instrumentScreen()
            .instrumentDetailScroll()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    InstrumentCloseButton(action: onDismiss)
                }
            }
            .sheet(isPresented: $showingAddCamera) {
                AddCameraView()
            }
        }
        .instrumentSheetChrome()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
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
                    .onTapGesture { onSelect(camera) }
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
