import SwiftUI
import UIKit

struct RollDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let rollId: UUID

    @State private var showingDeleteConfirm = false
    @State private var showingExportSheet = false
    @State private var loadCameraId: UUID?
    @State private var showingCameraPicker = false
    @State private var exportText = ""
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
                        let showDevelopment = roll.status == .atLab
                            || roll.status == .developed
                            || roll.development != nil

                        // Inventory uses the load slider; every other status uses the frame carousel.
                        loadOrExposureStage(roll)
                        if !showLoad {
                            sectionDivider
                            pipelineSection(roll)
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
                        .font(InstrumentFont.mono(17, weight: .semibold))
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
                        exportText = store.rollDataSheetText(for: rollId) ?? "Roll summary unavailable."
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
                InstrumentKeyboardDoneButton {
                    isNotesFocused = false
                }
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
        .alert(deleteAlertTitle, isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.requestDeleteRoll(rollId)
                dismiss()
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

    @ViewBuilder
    private func loadOrExposureStage(_ roll: Roll) -> some View {
        let selectedCamera = loadCameraId.flatMap { store.camera(for: $0) }
            ?? roll.cameraId.flatMap { store.camera(for: $0) }
        let startMode: LoadExposureStage.StartMode = {
            roll.status.isInventory ? .slide : .carousel
        }()

        LoadExposureStage(
            roll: roll,
            stock: store.stock(for: roll.stockId),
            cameraName: selectedCamera?.name ?? "camera",
            canSlide: selectedCamera != nil && roll.status.isInventory,
            startMode: startMode,
            onChoose: {
                showingCameraPicker = true
            },
            onChangeSelection: {
                showingCameraPicker = true
            },
            onCommitLoad: {
                if let cameraId = loadCameraId ?? selectedCamera?.id {
                    store.assignRoll(roll.id, to: cameraId)
                }
            },
            onAdvance: { store.advanceExposure(on: roll.id) },
            onUndo: { store.removeLastFrame(from: roll.id) },
            onSetCount: { store.setFrameCount($0, for: roll.id) }
        )
        // Keep identity stable across load so the slide→carousel transition isn't remounted away.
        // Remount when the chosen camera changes so the entrance animation can replay.
        .id("load-stage-\(roll.id)-\(loadCameraId?.uuidString ?? roll.cameraId?.uuidString ?? "pick")")
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
        .presentationDragIndicator(.hidden)
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
        .inFridge,
        .inCamera,
        .shotUndeveloped,
        .atLab,
        .developed,
        .scanned,
        .archived,
    ]

    private func selectPipelineStatus(_ status: RollStatus, for roll: Roll) {
        if status.isInventory {
            loadCameraId = nil
        }
        store.setRollStatus(roll.id, to: status, cameraId: roll.cameraId ?? loadCameraId)
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
            .submitLabel(.return)
            .focused($isNotesFocused)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            ScrollView {
                Text(exportText.isEmpty ? "Roll summary unavailable." : exportText)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.horizontalPadding)
                    .padding(.vertical, AppTheme.Spacing.md)
            }
            .instrumentScreen()
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingExportSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") {
                        printSummary()
                    }
                    .font(InstrumentFont.mono(13))
                    .disabled(exportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if exportText.isEmpty {
                    exportText = store.rollDataSheetText(for: rollId) ?? "Roll summary unavailable."
                }
            }
        }
    }

    private func printSummary() {
        let text = exportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let formatter = UISimpleTextPrintFormatter(text: text)
        formatter.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        formatter.color = .black
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = store.roll(for: rollId).map { "\($0.shortId) Summary" } ?? "Roll Summary"
        info.orientation = .portrait

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = formatter
        controller.present(animated: true)
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
        .presentationDragIndicator(.hidden)
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
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.notes = trimmed.isEmpty ? nil : newValue
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

#Preview {
    NavigationStack {
        RollDetailView(rollId: UUID())
    }
    .environment(AppStore())
}
