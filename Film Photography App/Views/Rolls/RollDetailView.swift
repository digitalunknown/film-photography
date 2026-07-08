import SwiftUI

struct RollDetailView: View {
    @Environment(AppStore.self) private var store
    let rollId: UUID

    @State private var showingImportAlert = false
    @State private var showingStatusPicker = false
    @State private var showingDeleteConfirm = false
    @State private var showingExportSheet = false
    @State private var loadCameraId: UUID?
    @State private var exportText = ""
    @State private var tagInput = ""
    @State private var showingAddDatedFrame = false
    @State private var datedFrameTimestamp = Date()

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
                        heroSection(roll)
                        pipelineSection(roll)
                        metadataSection(roll)
                        frameLogSection(roll)
                        if roll.status == .atLab || roll.status == .developed || roll.development != nil {
                            developmentSection(roll)
                        }
                        tagsSection(roll)
                        notesSection(roll)
                        exportSection(roll)
                        deleteSection(roll)
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
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
        .instrumentDetailNavigation(title: rollTitle)
        .sheet(isPresented: $showingStatusPicker) {
            if let roll {
                statusPickerSheet(roll)
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showingAddDatedFrame) {
            addDatedFrameSheet
        }
        .alert("Import scans", isPresented: $showingImportAlert) {
            Button("Import") {
                store.advanceRollStatus(rollId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Write camera, lens, stock, ISO, dates, and GPS into scan files.")
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

    @ViewBuilder
    private func heroSection(_ roll: Roll) -> some View {
        if roll.status == .inCamera {
            Button {
                store.addFrameMarker(to: roll.id)
            } label: {
                HeroMetric(
                    label: "Frame",
                    sublabel: store.stock(for: roll.stockId)?.name,
                    value: String(format: "%02d", roll.frameCount)
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    store.removeLastFrame(from: roll.id)
                }
            )
            .padding(.bottom, 8)

            Text("Tap counter to log a shot · long press to remove")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.bottom, 16)

            UnderlineMeter(
                label: "Exposures",
                value: "\(roll.frameCount)/\(roll.totalExposures)",
                progress: min(Double(roll.frameCount) / Double(max(roll.totalExposures, 1)), 1.0)
            )
            .padding(.bottom, 28)

            HairlineRule().padding(.bottom, 28)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(store.stock(for: roll.stockId)?.name ?? roll.shortId)
                        .font(InstrumentFont.display(32, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                    if roll.isExpired {
                        Text("Expired")
                            .font(InstrumentFont.mono(10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(AppTheme.rule))
                    } else if roll.isNearExpiry {
                        Text("Exp soon")
                            .font(InstrumentFont.mono(10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(AppTheme.rule))
                    }
                }
                Text(roll.shortId)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.bottom, 28)

            HairlineRule().padding(.bottom, 28)
        }
    }

    private func pipelineSection(_ roll: Roll) -> some View {
        DetailSection(title: "Pipeline") {
            VStack(alignment: .leading, spacing: 12) {
                if roll.status.isInventory {
                    Picker("Camera", selection: $loadCameraId) {
                        Text("Select camera").tag(nil as UUID?)
                        ForEach(availableCameras(for: roll)) { camera in
                            Text(camera.name).tag(camera.id as UUID?)
                        }
                    }
                    .font(InstrumentFont.mono(12))
                }

                PipelineStatusRow(
                    status: roll.status.displayName,
                    onTapStatus: { showingStatusPicker = true }
                )

                if roll.status == .inCamera {
                    TextAction(label: "Drop pin →") {
                        store.addFrameMarker(to: roll.id)
                    }
                    TextAction(label: "Duplicate last frame →") {
                        store.addFrameMarker(to: roll.id, duplicateLast: true)
                    }
                    if roll.frameCount > 0 {
                        TextAction(label: "Remove last frame →") {
                            store.removeLastFrame(from: roll.id)
                        }
                    }
                }

                if roll.status == .scanned {
                    TextAction(label: "Import scans →") {
                        showingImportAlert = true
                    }
                }
            }
        }
    }

    private func metadataSection(_ roll: Roll) -> some View {
        DetailSection(title: "Record") {
            VStack(spacing: 10) {
                DataRow(label: "ID", value: roll.shortId)
                if let stock = store.stock(for: roll.stockId) {
                    DataRow(label: "Stock", value: stock.name)
                    DataRow(label: "ISO", value: "\(roll.shootingISO ?? stock.iso)")
                }
                DataRow(label: "Format", value: roll.format.displayName)
                if roll.status.showsCamera, let camera = store.camera(for: roll.cameraId) {
                    DataRow(label: "Camera", value: camera.name)
                }
                editableFrameCountRow(roll)
                editableExposuresRow(roll)
                DataRow(label: "Pins", value: "\(roll.pinCount)")
                if let push = roll.pushPullLabel {
                    DataRow(label: "Push", value: push)
                }
                expiryRow(roll)
                if let location = roll.storageLocation {
                    DataRow(label: "Storage", value: location)
                }
            }
        }
    }

    private func frameLogSection(_ roll: Roll) -> some View {
        DetailSection(title: "Frame log") {
            VStack(alignment: .leading, spacing: 10) {
                if roll.frameMarkers.isEmpty {
                    Text("Optional — log a frame with a specific date and time.")
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(roll.frameMarkers.count) dated frame\(roll.frameMarkers.count == 1 ? "" : "s")")
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                TextAction(label: "Add frame with date →") {
                    datedFrameTimestamp = Date()
                    showingAddDatedFrame = true
                }
            }
        }
    }

    private var addDatedFrameSheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Date & time",
                    selection: $datedFrameTimestamp,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(InstrumentFont.mono(12))
            }
            .instrumentFormStyle()
            .navigationTitle("Add frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddDatedFrame = false
                    }
                    .font(InstrumentFont.mono(13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addFrameMarker(to: rollId, at: datedFrameTimestamp)
                        showingAddDatedFrame = false
                    }
                    .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func developmentSection(_ roll: Roll) -> some View {
        DetailSection(title: "Development") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Path", selection: developmentPathBinding(for: roll)) {
                    ForEach(DevelopmentPath.allCases, id: \.self) { path in
                        Text(path.displayName).tag(path)
                    }
                }
                .font(InstrumentFont.mono(12))

                if store.roll(for: rollId)?.development?.path == .lab {
                    TextField("Lab name", text: labNameBinding(for: roll))
                        .font(InstrumentFont.mono(12))
                } else if store.roll(for: rollId)?.development?.path == .diy {
                    TextField("Developer", text: devFieldBinding(for: roll, keyPath: \.developer))
                        .font(InstrumentFont.mono(12))
                    TextField("Dilution", text: devFieldBinding(for: roll, keyPath: \.dilution))
                        .font(InstrumentFont.mono(12))
                    TextField("Time (minutes)", text: devTimeBinding(for: roll))
                        .font(InstrumentFont.mono(12))
                        .keyboardType(.decimalPad)
                    TextField("Temperature °C", text: devTempBinding(for: roll))
                        .font(InstrumentFont.mono(12))
                        .keyboardType(.decimalPad)
                    TextField("Agitation notes", text: devFieldBinding(for: roll, keyPath: \.agitationNotes), axis: .vertical)
                        .font(InstrumentFont.mono(12))
                        .lineLimit(2...4)

                    if !store.devRecipePresets.isEmpty {
                        Menu("Apply preset") {
                            ForEach(store.devRecipePresets) { preset in
                                Button(preset.summary) {
                                    store.applyDevPreset(preset.id, to: roll.id)
                                }
                            }
                        }
                        .font(InstrumentFont.mono(12))
                    }
                }

                if let summary = store.roll(for: rollId)?.development?.summary {
                    Text(summary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private func tagsSection(_ roll: Roll) -> some View {
        DetailSection(title: "Tags") {
            VStack(alignment: .leading, spacing: 10) {
                if !roll.tags.isEmpty {
                    Text(roll.tags.joined(separator: " · "))
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                HStack {
                    TextField("Add tag", text: $tagInput)
                        .font(InstrumentFont.mono(12))
                        .submitLabel(.done)
                        .onSubmit { addTag(to: roll) }
                    Button("Add") { addTag(to: roll) }
                        .font(InstrumentFont.mono(12))
                        .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func notesSection(_ roll: Roll) -> some View {
        DetailSection(title: "Notes") {
            TextField(
                "Notes",
                text: notesBinding(for: roll),
                axis: .vertical
            )
            .font(InstrumentFont.mono(12))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(3...8)
            .submitLabel(.done)
        }
    }

    private func exportSection(_ roll: Roll) -> some View {
        DetailSection(title: "Export") {
            VStack(alignment: .leading, spacing: 8) {
                TextAction(label: "Copy CSV →") {
                    exportText = store.csvExport(for: roll.id) ?? ""
                    showingExportSheet = true
                }
                TextAction(label: "Print data sheet →") {
                    exportText = store.rollDataSheetText(for: roll.id) ?? ""
                    showingExportSheet = true
                }
            }
        }
    }

    private func deleteSection(_ roll: Roll) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextAction(label: "Delete roll →") {
                showingDeleteConfirm = true
            }
            .padding(.top, 8)
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
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingExportSheet = false }
                        .font(InstrumentFont.mono(13))
                }
            }
        }
    }

    private func statusPickerSheet(_ roll: Roll) -> some View {
        NavigationStack {
            List {
                ForEach(RollStatus.pipelineCases + [.archived], id: \.self) { status in
                    Button {
                        if status == .scanned && roll.status != .scanned {
                            showingStatusPicker = false
                            showingImportAlert = true
                        } else if status == .inCamera && roll.status.isInventory {
                            guard let loadCameraId else { return }
                            store.setRollStatus(roll.id, to: status, cameraId: loadCameraId)
                            showingStatusPicker = false
                        } else {
                            store.setRollStatus(roll.id, to: status, cameraId: roll.cameraId)
                            showingStatusPicker = false
                        }
                    } label: {
                        HStack {
                            Text(status.displayName)
                                .font(InstrumentFont.mono(13))
                            Spacer()
                            if roll.status == status {
                                Text("●")
                                    .font(InstrumentFont.mono(10))
                            }
                        }
                    }
                }
            }
            .instrumentFormStyle()
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingStatusPicker = false }
                        .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Bindings

    private func editableFrameCountRow(_ roll: Roll) -> some View {
        HStack {
            Text("Frames shot")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            HStack(spacing: 16) {
                Button {
                    store.removeLastFrame(from: roll.id)
                } label: {
                    Text("−")
                        .font(InstrumentFont.mono(16))
                        .foregroundStyle(roll.frameCount > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(roll.frameCount == 0)

                Text("\(roll.frameCount)")
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()

                Button {
                    store.addFrameMarker(to: roll.id)
                } label: {
                    Text("+")
                        .font(InstrumentFont.mono(16))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func editableExposuresRow(_ roll: Roll) -> some View {
        HStack {
            Text("Expected frames")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            TextField("36", value: exposuresBinding(for: roll), format: .number)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(width: 56)
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

    private func expiryRow(_ roll: Roll) -> some View {
        EditableDateRow(
            label: "Expiry date",
            date: expiryDateBinding(for: roll),
            hasDate: store.roll(for: rollId)?.expiryDate != nil,
            onToggle: { enabled in
                guard var updated = store.roll(for: rollId) else { return }
                if enabled {
                    updated.expiryDate = updated.expiryDate
                        ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())
                        ?? Date()
                } else {
                    updated.expiryDate = nil
                }
                store.updateRoll(updated)
            }
        )
    }

    private func expiryDateBinding(for roll: Roll) -> Binding<Date> {
        Binding(
            get: { store.roll(for: rollId)?.expiryDate ?? Date() },
            set: { newValue in
                guard var updated = store.roll(for: rollId) else { return }
                updated.expiryDate = Calendar.current.startOfDay(for: newValue)
                store.updateRoll(updated)
            }
        )
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

    private func addTag(to roll: Roll) {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty, var updated = store.roll(for: rollId), !updated.tags.contains(tag) else { return }
        updated.tags.append(tag)
        store.updateRoll(updated)
        tagInput = ""
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
