import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct RollDetailView: View {
    @Environment(AppStore.self) private var store
    let rollId: UUID

    @State private var showingDeleteConfirm = false
    @State private var showingExportSheet = false
    @State private var loadCameraId: UUID?
    @State private var showingCameraPicker = false
    @State private var exportText = ""
    @State private var scanPickerItems: [PhotosPickerItem] = []
    @State private var openedScanFrame: StripFrame?
    @State private var showingAddDatePicker = false
    @State private var addDateDraft = Date()
    @FocusState private var isNotesFocused: Bool

    private var roll: Roll? {
        store.roll(for: rollId)
    }

    private var rollTitle: String {
        guard let roll else { return "Roll" }
        return store.stock(for: roll.stockId)?.name ?? roll.shortId
    }

    var body: some View {
        Group {
            if let roll {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let stock = store.stock(for: roll.stockId), stock.rollImageName != nil {
                            DetailHeroBlock {
                                StockPlate(stock: stock, square: false, height: 220)
                            }
                        }

                        let showLoad = roll.status.isInventory
                        let showScans = roll.status.canImportScans
                        let showDevelopment = roll.status == .atLab
                            || roll.status == .developed
                            || roll.development != nil

                        if showLoad {
                            loadSection(roll)
                            sectionDivider
                        } else {
                            pipelineSection(roll)
                            sectionDivider
                        }
                        frameCounterSection(roll)
                        if showScans {
                            sectionDivider
                            scansSection(roll)
                        }
                        sectionDivider
                        notesSection(roll)
                        sectionDivider
                        metadataSection(roll)
                        if showDevelopment {
                            sectionDivider
                            developmentSection(roll)
                        }
                    }
                    .instrumentDetailContent()
                }
                .instrumentDetailScroll()
            } else {
                VStack(alignment: .leading) {
                    Text("Roll not found")
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
        .instrumentDetailChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(rollTitle)
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if roll?.isExpired == true {
                        ExpiredLabel()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Printable Summary Sheet", systemImage: "doc.text") {
                        exportText = store.rollDataSheetText(for: rollId) ?? ""
                        showingExportSheet = true
                    }
                    Divider()
                    Button("Delete Roll", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isNotesFocused = false
                }
                .font(InstrumentFont.mono(13))
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showingCameraPicker) {
            cameraPickerSheet(for: rollId)
        }
        .sheet(isPresented: $showingAddDatePicker) {
            addDatePickerSheet
        }
        .fullScreenCover(item: $openedScanFrame) { frame in
            NavigationStack {
                ScanFrameView(
                    rollId: rollId,
                    frame: frame,
                    stock: store.roll(for: rollId).flatMap { store.stock(for: $0.stockId) }
                )
            }
        }
        .alert(deleteAlertTitle, isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.requestDeleteRoll(rollId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteAlertMessage)
        }
    }

    private var deleteAlertTitle: String {
        roll?.status == .inCamera ? "Delete active roll?" : "Delete roll?"
    }

    private var deleteAlertMessage: String {
        if roll?.status == .inCamera {
            return "This roll is loaded in a camera. Deleting it removes all frame pins and cannot be undone after 5 seconds."
        }
        return "You can undo for 5 seconds after deleting."
    }

    private var sectionDivider: some View {
        SectionRule()
            .padding(.bottom, AppTheme.Spacing.md)
    }

    private func scansSection(_ roll: Roll) -> some View {
        DetailSection(title: "Scans") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if roll.scanFileNames.isEmpty {
                    PhotosPicker(
                        selection: $scanPickerItems,
                        maxSelectionCount: 72,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        scanEmptyState
                    }
                    .buttonStyle(.plain)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                            GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                        ],
                        spacing: AppTheme.Spacing.sm
                    ) {
                        ForEach(Array(roll.scanFileNames.enumerated()), id: \.element) { index, fileName in
                            Button {
                                openedScanFrame = StripFrame(
                                    index: index + 1,
                                    state: .scanned,
                                    marker: nil,
                                    scanFileName: fileName
                                )
                            } label: {
                                scanThumbnail(rollId: roll.id, fileName: fileName)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.removeScan(from: roll.id, fileName: fileName)
                                }
                            }
                        }
                    }

                    PhotosPicker(
                        selection: $scanPickerItems,
                        maxSelectionCount: 72,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Text("Add more photos →")
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onChange(of: scanPickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importScans(items, for: roll.id) }
            }
        }
    }

    private var scanEmptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(AppTheme.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 120)
                VStack(spacing: AppTheme.Spacing.sm) {
                    Text("◻◻")
                        .font(InstrumentFont.mono(18))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("Add photos")
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Tap to upload scans")
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scanThumbnail(rollId: UUID, fileName: String) -> some View {
        Group {
            if let image = ScanStorage.thumbnail(for: rollId, fileName: fileName, maxSize: 600) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AppTheme.rule.opacity(0.35))
                    .overlay {
                        Text("·")
                            .font(InstrumentFont.mono(16))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipped()
        .overlay {
            Rectangle()
                .strokeBorder(AppTheme.rule, lineWidth: 0.5)
        }
    }

    private func importScans(_ items: [PhotosPickerItem], for rollId: UUID) async {
        let existingCount = await MainActor.run {
            store.roll(for: rollId)?.scanFileNames.count ?? 0
        }
        var names: [String] = []
        for (offset, item) in items.enumerated() {
            guard let data = await loadImageData(from: item) else { continue }
            let fileName = "scan-\(existingCount + offset + 1)-\(UUID().uuidString.prefix(8)).jpg"
            if ScanStorage.saveScan(data: data, rollId: rollId, fileName: fileName) != nil {
                names.append(fileName)
            }
        }
        if !names.isEmpty {
            await MainActor.run {
                store.appendScans(to: rollId, fileNames: names)
                scanPickerItems = []
            }
        } else {
            await MainActor.run { scanPickerItems = [] }
        }
    }

    private func loadImageData(from item: PhotosPickerItem) async -> Data? {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            return jpegData(from: data)
        }
        if let transfer = try? await item.loadTransferable(type: ScanImageTransfer.self) {
            return jpegData(from: transfer.data)
        }
        return nil
    }

    private func jpegData(from data: Data) -> Data? {
        if let image = UIImage(data: data) {
            return image.jpegData(compressionQuality: 0.88) ?? data
        }
        return data
    }

    @ViewBuilder
    private func loadSection(_ roll: Roll) -> some View {
        if roll.status.isInventory {
            DetailSection(title: "Load") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    let selectedCamera = loadCameraId.flatMap { store.camera(for: $0) }

                    FilmLoadSlider(
                        stock: store.stock(for: roll.stockId),
                        cameraName: selectedCamera?.name ?? "camera",
                        prompt: selectedCamera == nil ? "choose a camera" : "slide to load",
                        onChooseRoll: selectedCamera == nil ? { showingCameraPicker = true } : nil
                    ) {
                        if let cameraId = loadCameraId {
                            store.assignRoll(roll.id, to: cameraId)
                        }
                    }
                    .id("\(roll.id)-\(loadCameraId?.uuidString ?? "none")")
                    .allowsHitTesting(selectedCamera != nil)
                    .overlay {
                        if selectedCamera == nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showingCameraPicker = true }
                        }
                    }

                    if let selectedCamera {
                        HStack {
                            Text(selectedCamera.name)
                                .font(InstrumentFont.mono(11))
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                            Button("Change →") { showingCameraPicker = true }
                                .font(InstrumentFont.mono(11))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else if availableCameras(for: roll).isEmpty {
                        Text("No empty cameras available.")
                            .font(InstrumentFont.mono(11))
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        Text("Tap the bay to choose a camera, then slide to load.")
                            .font(InstrumentFont.mono(11))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func cameraPickerSheet(for rollId: UUID) -> some View {
        NavigationStack {
            List {
                if let roll = store.roll(for: rollId) {
                    ForEach(availableCameras(for: roll)) { camera in
                        Button {
                            loadCameraId = camera.id
                            showingCameraPicker = false
                        } label: {
                            Text(camera.name)
                                .font(InstrumentFont.mono(13))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }

                    if availableCameras(for: roll).isEmpty {
                        Text("No empty cameras available.")
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .instrumentFormStyle()
            .navigationTitle("Choose camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCameraPicker = false }
                        .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func pipelineSection(_ roll: Roll) -> some View {
        DetailSection(title: "Pipeline") {
            InstrumentMenuRow(
                label: "Status",
                value: roll.status.displayName,
                valueBright: true,
                showsDivider: false
            ) {
                ForEach(Self.postLoadStatuses, id: \.self) { status in
                    Button(status.displayName) {
                        selectPipelineStatus(status, for: roll)
                    }
                }
            }
        }
    }

    private static let postLoadStatuses: [RollStatus] = [
        .inCamera,
        .shotUndeveloped,
        .atLab,
        .developed,
        .scanned,
        .archived,
    ]

    private func selectPipelineStatus(_ status: RollStatus, for roll: Roll) {
        store.setRollStatus(roll.id, to: status, cameraId: roll.cameraId ?? loadCameraId)
    }

    private func frameCounterSection(_ roll: Roll) -> some View {
        DetailSection(title: "Exposures") {
            FrameExposureCounter(
                shot: roll.frameCount,
                total: max(roll.totalExposures, 1),
                onIncrement: { store.advanceExposure(on: roll.id) },
                onSetCount: { store.setFrameCount($0, for: roll.id) }
            )
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    private func metadataSection(_ roll: Roll) -> some View {
        DetailSection(title: "Technical Specifications") {
            VStack(spacing: 0) {
                if let stock = store.stock(for: roll.stockId) {
                    DataRow(label: "Stock", value: stock.name, showsDivider: false)
                    DataRow(label: "ISO", value: "\(roll.shootingISO ?? stock.iso)")
                    DataRow(label: "Format", value: roll.format.displayName)
                } else {
                    DataRow(label: "Format", value: roll.format.displayName, showsDivider: false)
                }
                if !roll.status.isInventory {
                    cameraRow(roll)
                }
                editableExposuresRow(roll)
                pushPullRow(roll)
                addDateRow(roll)
            }
        }
    }

    private func pushPullRow(_ roll: Roll) -> some View {
        InstrumentMenuRow(
            label: "Push / pull",
            value: roll.pushPullDisplayValue,
            valueBright: roll.pushPull != nil && roll.pushPull != 0
        ) {
            ForEach(Self.pushPullOptions, id: \.value) { option in
                Button(option.label) {
                    guard var updated = store.roll(for: rollId) else { return }
                    updated.pushPull = option.value == 0 ? nil : option.value
                    store.updateRoll(updated)
                }
            }
        }
    }

    private static let pushPullOptions: [(label: String, value: Int)] = [
        ("Box speed", 0),
        ("Pull −1", -1),
        ("Push +1", 1),
        ("Push +2", 2),
    ]

    private func cameraRow(_ roll: Roll) -> some View {
        InstrumentMenuRow(
            label: "Camera",
            value: cameraDisplayValue(for: roll),
            valueBright: roll.cameraId != nil
        ) {
            Button("Not Set") {
                store.assignRoll(rollId, to: nil)
            }
            ForEach(store.cameras) { camera in
                Button(camera.name) {
                    store.assignRoll(rollId, to: camera.id)
                }
            }
        }
    }

    private func cameraDisplayValue(for roll: Roll) -> String {
        guard let cameraId = roll.cameraId,
              let camera = store.camera(for: cameraId) else {
            return "Not Set"
        }
        return camera.name
    }

    private func developmentSection(_ roll: Roll) -> some View {
        DetailSection(title: "Development") {
            VStack(alignment: .leading, spacing: 0) {
                InstrumentMenuRow(
                    label: "Path",
                    value: (store.roll(for: rollId)?.development?.path ?? .lab).displayName,
                    valueBright: true,
                    showsDivider: false
                ) {
                    ForEach(DevelopmentPath.allCases, id: \.self) { path in
                        Button(path.displayName) {
                            developmentPathBinding(for: roll).wrappedValue = path
                        }
                    }
                }

                if store.roll(for: rollId)?.development?.path == .lab {
                    InstrumentEditableRow(label: "Lab") {
                        TextField("Lab name", text: labNameBinding(for: roll))
                    }
                } else if store.roll(for: rollId)?.development?.path == .diy {
                    InstrumentEditableRow(label: "Developer") {
                        TextField("Developer", text: devFieldBinding(for: roll, keyPath: \.developer))
                    }
                    InstrumentEditableRow(label: "Dilution") {
                        TextField("Dilution", text: devFieldBinding(for: roll, keyPath: \.dilution))
                    }
                    InstrumentEditableRow(label: "Time") {
                        TextField("Minutes", text: devTimeBinding(for: roll))
                            .keyboardType(.decimalPad)
                    }
                    InstrumentEditableRow(label: "Temp") {
                        TextField("°C", text: devTempBinding(for: roll))
                            .keyboardType(.decimalPad)
                    }
                    InstrumentEditableRow(label: "Agitation") {
                        TextField("Notes", text: devFieldBinding(for: roll, keyPath: \.agitationNotes), axis: .vertical)
                            .lineLimit(2...4)
                    }

                    if !store.devRecipePresets.isEmpty {
                        VStack(spacing: 0) {
                            HairlineRule()
                            Menu("Apply preset") {
                                ForEach(store.devRecipePresets) { preset in
                                    Button(preset.summary) {
                                        store.applyDevPreset(preset.id, to: roll.id)
                                    }
                                }
                            }
                            .font(InstrumentFont.mono(12))
                            .padding(.vertical, AppTheme.Spacing.md)
                        }
                    }
                }

                if let summary = store.roll(for: rollId)?.development?.summary {
                    DataRow(label: "Summary", value: summary, valueBright: false)
                }
            }
        }
    }

    private func notesSection(_ roll: Roll) -> some View {
        DetailSection(title: "Notes") {
            TextField(
                "Add a note",
                text: notesBinding(for: roll),
                axis: .vertical
            )
            .font(InstrumentFont.mono(12))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(3...8)
            .submitLabel(.done)
            .focused($isNotesFocused)
            .onSubmit {
                isNotesFocused = false
            }
            .padding(.vertical, AppTheme.Spacing.sm)
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            ScrollView {
                Text(exportText)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.horizontalPadding)
            }
            .instrumentScreen()
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingExportSheet = false }
                        .font(InstrumentFont.mono(13))
                }
            }
        }
    }

    // MARK: - Bindings

    private func editableExposuresRow(_ roll: Roll) -> some View {
        InstrumentRow(label: "Expected frames") {
            TextField("36", value: exposuresBinding(for: roll), format: .number)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .keyboardType(.numberPad)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exposuresBinding(for roll: Roll) -> Binding<Int> {
        Binding(
            get: { max(store.roll(for: rollId)?.totalExposures ?? 36, 1) },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                updated.totalExposures = max(newValue, 1)
                store.updateRoll(updated)
            }
        )
    }

    private func developmentPathBinding(for roll: Roll) -> Binding<DevelopmentPath> {
        Binding(
            get: { store.roll(for: rollId)?.development?.path ?? .lab },
            set: { path in
                guard var updated = store.roll(for: rollId) else { return }
                if updated.development == nil {
                    updated.development = DevelopmentRecord(path: path)
                } else {
                    updated.development?.path = path
                }
                store.updateRoll(updated)
            }
        )
    }

    private func labNameBinding(for roll: Roll) -> Binding<String> {
        Binding(
            get: { store.roll(for: rollId)?.development?.labName ?? store.roll(for: rollId)?.labName ?? "" },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                if updated.development == nil {
                    updated.development = DevelopmentRecord(path: .lab, labName: newValue)
                } else {
                    updated.development?.labName = newValue
                }
                updated.labName = newValue.isEmpty ? nil : newValue
                store.updateRoll(updated)
            }
        )
    }

    private func devFieldBinding(for roll: Roll, keyPath: WritableKeyPath<DevelopmentRecord, String?>) -> Binding<String> {
        Binding(
            get: { store.roll(for: rollId)?.development?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                if updated.development == nil {
                    updated.development = DevelopmentRecord(path: .diy)
                }
                updated.development?[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                store.updateRoll(updated)
            }
        )
    }

    private func devTimeBinding(for roll: Roll) -> Binding<String> {
        Binding(
            get: {
                guard let minutes = store.roll(for: rollId)?.development?.timeMinutes else { return "" }
                return String(minutes)
            },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                if updated.development == nil { updated.development = DevelopmentRecord(path: .diy) }
                updated.development?.timeMinutes = Double(newValue)
                store.updateRoll(updated)
            }
        )
    }

    private func devTempBinding(for roll: Roll) -> Binding<String> {
        Binding(
            get: {
                guard let temp = store.roll(for: rollId)?.development?.temperatureC else { return "" }
                return String(format: "%.0f", temp)
            },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                if updated.development == nil { updated.development = DevelopmentRecord(path: .diy) }
                updated.development?.temperatureC = Double(newValue)
                store.updateRoll(updated)
            }
        )
    }

    private func addDateRow(_ roll: Roll) -> some View {
        Button {
            addDateDraft = roll.expiryDate ?? Date()
            showingAddDatePicker = true
        } label: {
            InstrumentRow(label: "Expiration date") {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(addDateDisplayValue(for: roll))
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(roll.expiryDate != nil ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(InstrumentFont.mono(9, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addDatePickerSheet: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                MonthYearPicker(date: $addDateDraft)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .padding(.horizontal, AppTheme.horizontalPadding)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .instrumentScreen()
            .navigationTitle("Expiration date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        guard var updated = store.roll(for: rollId) else { return }
                        updated.expiryDate = nil
                        store.updateRoll(updated)
                        showingAddDatePicker = false
                    }
                    .font(InstrumentFont.mono(13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard var updated = store.roll(for: rollId) else { return }
                        updated.expiryDate = ExpirationDate.normalize(addDateDraft)
                        store.updateRoll(updated)
                        showingAddDatePicker = false
                    }
                    .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func addDateDisplayValue(for roll: Roll) -> String {
        guard let date = roll.expiryDate else { return "Not Set" }
        return DateFormatters.monthYear.string(from: date)
    }

    private func notesBinding(for roll: Roll) -> Binding<String> {
        Binding(
            get: { store.roll(for: rollId)?.notes ?? "" },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                var text = newValue
                // Vertical TextFields treat the Done key as Return; dismiss instead of a new line.
                if text.hasSuffix("\n") {
                    text = String(text.dropLast())
                    Task { @MainActor in
                        isNotesFocused = false
                    }
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.notes = trimmed.isEmpty ? nil : text
                store.updateRoll(updated)
            }
        )
    }

    private func availableCameras(for roll: Roll) -> [Camera] {
        store.cameras.filter {
            store.loadedRoll(for: $0.id) == nil || $0.id == loadCameraId
        }
    }
}

/// Reliable PhotosPicker image transfer — `Data.self` alone often fails for library assets.
private struct ScanImageTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { ScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .png) { ScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .heic) { ScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .image) { ScanImageTransfer(data: $0) }
    }
}

#Preview {
    NavigationStack {
        RollDetailView(rollId: UUID())
    }
    .environment(AppStore())
}
