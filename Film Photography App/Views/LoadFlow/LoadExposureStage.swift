import SwiftUI
import PhotosUI
import UIKit

/// Exposure carousel for a loaded roll — counter, film strip and scan import.
/// Inventory rolls get a single button that picks a camera and loads them.
struct LoadExposureStage: View {
    let roll: Roll
    let stock: FilmStock?
    var onChoose: (() -> Void)?
    var onAdvance: () -> Void
    var onUndo: (() -> Void)? = nil
    var onSetCount: (Int) -> Void
    var onFinishRoll: (() -> Void)? = nil

    @State private var selectedFrameIndex: Int?
    @State private var viewingFrame: StripFrame?
    @State private var frameToClear: StripFrame?
    @State private var scanPickerItems: [PhotosPickerItem] = []
    @State private var pendingScans: [PendingScan] = []
    @State private var isArranging = false
    @State private var isPreparingScans = false
    @Environment(AppStore.self) private var store

    private var frameTotal: Int {
        max(roll.totalExposures, 1)
    }

    /// How far the roll runs for the purposes of arranging scans: normally its exposure
    /// count, but stretched to cover any scan sitting past the end. A scan the list left
    /// out would be read as one the photographer had removed, and deleted on save.
    private var frameSpan: Int {
        let lastPhoto = roll.framePhotoFileNames.keys.compactMap(Int.init).max() ?? 0
        let lastScan = roll.scanFileNames.isEmpty
            ? 0
            : roll.scanFileNames.count + roll.scanAlignmentOffset
        return max(frameTotal, lastPhoto, lastScan)
    }

    var body: some View {
        DetailSection(title: "") {
            content
        }
        .onChange(of: scanPickerItems) { _, items in
            handleScanPickerChange(items)
        }
        .sheet(item: $viewingFrame) { frame in
            scanSheet(frame)
        }
        .sheet(isPresented: $isArranging) {
            ScanImportSheet(
                rollId: roll.id,
                scans: pendingScans,
                frames: pendingFrames,
                onCancel: { dismissScanOrder() },
                onConfirm: { placement in
                    dismissScanOrder()
                    applyArrangement(placement)
                }
            )
        }
        .alert(
            "Remove scan?",
            isPresented: Binding(get: { frameToClear != nil },
                                 set: { if !$0 { frameToClear = nil } }),
            presenting: frameToClear
        ) { frame in
            Button("Remove", role: .destructive) { removeScan(from: frame) }
            Button("Cancel", role: .cancel) {}
        } message: { frame in
            Text("This removes the photo from frame \(frame.index).")
        }
    }

    /// A scan sits either in the per-frame map or in the roll's ordered list, depending on
    /// how it was imported, and only one of the two holds it.
    private func removeScan(from frame: StripFrame) {
        if roll.framePhotoFileName(forFrame: frame.index) != nil {
            store.removeFramePhoto(from: roll.id, frameIndex: frame.index)
        } else if let fileName = roll.scanFileName(forFrame: frame.index) {
            store.removeScan(from: roll.id, fileName: fileName)
        }
    }

    /// The whole roll, frame one to the last exposure, however many scans have already
    /// been imported. The list reads the same on every visit, and scans can be spread out
    /// with gaps rather than landing on consecutive frames. Each frame carries what the
    /// shutter logged for it, which is how a photo gets matched to the frame it was shot
    /// on, along with whatever scan is already sitting there.
    private var pendingFrames: [ScanImportFrame] {
        let markers = Dictionary(
            roll.frameMarkers.map { ($0.frameIndex, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        return (1...frameSpan).map { index in
            ScanImportFrame(
                index: index,
                location: markers[index]?.location,
                date: markers[index]?.captureDate,
                existingScan: roll.framePhotoFileName(forFrame: index)
                    ?? roll.scanFileName(forFrame: index)
            )
        }
    }

    private func dismissScanOrder() {
        isArranging = false
        pendingScans = []
    }

    @ViewBuilder
    private var content: some View {
        if roll.status.isInventory {
            loadButton
        } else {
            carouselContent
        }
    }

    @ViewBuilder
    private var loadButton: some View {
        if let onChoose {
            Button(action: onChoose) {
                PillButtonLabel(title: "Load to Camera", icon: .camera)
            }
            .buttonStyle(.plain)
        }
    }

    private func scanSheet(_ frame: StripFrame) -> some View {
        NavigationStack {
            ScanFrameView(
                rollId: roll.id,
                frame: frame,
                stock: stock
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.bg)
        .preferredColorScheme(.dark)
    }

    private func handleScanPickerChange(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isPreparingScans = true
        Task { await prepareScans(items) }
    }

    // MARK: - Carousel

    private var carouselContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            FrameExposureCounter(
                shot: roll.frameCount,
                total: frameTotal,
                showsSegmentBar: false,
                onIncrement: onAdvance,
                onDecrement: onUndo,
                onSetCount: onSetCount
            )

            FilmStripView(
                roll: roll,
                stock: stock,
                selectedFrameIndex: $selectedFrameIndex,
                onRemoveScan: { frame in
                    frameToClear = frame
                },
                onOpenScan: { frame in
                    viewingFrame = frame
                }
            )

            rollAction
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    /// Shooting and scanning are separate jobs. While the roll is still in the camera the
    /// photographer has no scans yet, so the action finishes the roll; scan import only
    /// appears once the roll is off the camera.
    @ViewBuilder
    private var rollAction: some View {
        if roll.status.countsAsShot {
            HStack(spacing: AppTheme.Spacing.md) {
                addScansPicker
                arrangeButton
                saveButton
            }
        } else {
            finishRollButton
        }
    }

    private var hasScans: Bool {
        !roll.framePhotoFileNames.isEmpty || !roll.scanFileNames.isEmpty
    }

    /// Scans rarely come back from the lab in the order they were shot, and which photo
    /// belongs to which frame is often only obvious with the whole roll laid out. This
    /// opens that view without having to add a photo to get to it.
    @ViewBuilder
    private var arrangeButton: some View {
        if hasScans {
            Button {
                pendingScans = []
                isArranging = true
            } label: {
                PillButtonLabel(title: "Arrange", icon: .arrowUpDown)
            }
            .buttonStyle(.plain)
        }
    }

    /// Sends the roll's scans back out with everything logged for them written in. There
    /// is nothing to save until a scan has arrived, so it appears with the first one.
    @ViewBuilder
    private var saveButton: some View {
        let scans = ExportedScan.all(for: roll, in: store)
        if !scans.isEmpty {
            ExportScansButton(
                scans: scans,
                label: "Save scans",
                style: .pill(title: "Save")
            )
        }
    }

    @ViewBuilder
    private var finishRollButton: some View {
        if let onFinishRoll {
            Button(action: onFinishRoll) {
                PillButtonLabel(title: "Finish Roll", icon: .circleCheckBig)
            }
            .buttonStyle(.plain)
        }
    }

    /// Frames still free to take a scan, counted from the first empty one to the end of
    /// the roll. This caps what the picker will let through, so a selection can't be made
    /// that the roll has no room for.
    /// Alone on the row it can use the full label; next to Arrange/Save it stays short.
    private var addScansTitle: String {
        if isPreparingScans { return "Adding…" }
        return hasScans ? "Add" : "Add Scans"
    }

    private var remainingScanCapacity: Int {
        max(max(roll.totalExposures, 1) - nextFrameIndexForScans() + 1, 0)
    }

    /// Once every frame carries a scan there is nowhere left to put one, so the action
    /// goes away rather than opening a picker that could only be cancelled.
    @ViewBuilder
    private var addScansPicker: some View {
        if remainingScanCapacity > 0 {
            PhotosPicker(
                selection: $scanPickerItems,
                maxSelectionCount: remainingScanCapacity,
                matching: .images,
                photoLibrary: .shared()
            ) {
                // Three pills share the row, so the busy label stays as short as the
                // widest resting one rather than crowding its neighbours.
                PillButtonLabel(
                    title: addScansTitle,
                    icon: .imageUp
                )
            }
            .buttonStyle(.plain)
            .disabled(isPreparingScans)
        }
    }

    /// Decodes the picked images up front so the order sheet can show them. A single
    /// image has no order to choose, so it goes straight onto the next free frame.
    private func prepareScans(_ items: [PhotosPickerItem]) async {
        let startFrame = nextFrameIndexForScans()
        // The picker already holds the selection to what fits, so this only guards against
        // the roll having filled up in between.
        let capacity = remainingScanCapacity

        var payloads: [Data] = []
        for item in items.prefix(capacity) {
            if let data = await loadImageData(from: item) {
                payloads.append(data)
            }
        }

        // Re-encoding and decoding previews is heavy, so it happens off the main actor.
        let prepared = await Task.detached(priority: .userInitiated) {
            payloads.compactMap { data -> PendingScan? in
                guard let jpeg = ScanStorage.normalizedJPEG(from: data) else { return nil }
                return PendingScan(
                    jpeg: jpeg,
                    preview: ScanStorage.preview(from: jpeg, laidOnSide: true)
                )
            }
        }.value

        scanPickerItems = []
        isPreparingScans = false
        if prepared.count > 1 {
            pendingScans = prepared
            isArranging = true
        } else if let single = prepared.first {
            // One image has no order to choose, so it goes straight onto the next free
            // frame. Writing just that frame leaves the rest of the roll alone.
            store.setFramePhoto(on: roll.id, frameIndex: startFrame, imageData: single.jpeg)
            selectedFrameIndex = startFrame
        }
    }

    /// Hands the whole roll's worth of placement back in one call. The scans already on
    /// the roll are in here too, since they can be moved around alongside the new ones,
    /// and anything the photographer took off the roll is simply absent.
    private func applyArrangement(_ placement: [Int: ArrangedScan]) {
        let cap = frameSpan
        var assignments: [Int: ScanAssignment] = [:]
        var firstAdded: Int?

        for (frameIndex, scan) in placement where frameIndex >= 1 && frameIndex <= cap {
            switch scan {
            case .existing(let fileName):
                assignments[frameIndex] = .existing(fileName: fileName)
            case .picked(let pending):
                assignments[frameIndex] = .new(pending.jpeg)
                firstAdded = min(firstAdded ?? frameIndex, frameIndex)
            }
        }

        store.setScanPlacement(on: roll.id, placement: assignments)
        if let firstAdded {
            selectedFrameIndex = firstAdded
        }
    }

    private func nextFrameIndexForScans() -> Int {
        let maxPhoto = roll.framePhotoFileNames.keys.compactMap(Int.init).max() ?? 0
        let maxScan = roll.scanFileNames.isEmpty
            ? 0
            : roll.scanFileNames.count + roll.scanAlignmentOffset
        return max(maxPhoto, maxScan, 0) + 1
    }

    private func loadImageData(from item: PhotosPickerItem) async -> Data? {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        if let transfer = try? await item.loadTransferable(type: FrameScanImageTransfer.self) {
            return transfer.data
        }
        return nil
    }
}

/// Reliable PhotosPicker image transfer — `Data.self` alone often fails for library assets.
private struct FrameScanImageTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { FrameScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .png) { FrameScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .heic) { FrameScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .image) { FrameScanImageTransfer(data: $0) }
    }
}
