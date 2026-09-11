import SwiftUI

struct RollDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let rollId: UUID

    @State private var showingDeleteConfirm = false
    @State private var showingCameraPicker = false
    @State private var showingAddDatePicker = false
    @State private var showingFrozenDatePicker = false
    @State private var addDateDraft = Date()
    @State private var frozenDateDraft = Date()
    @FocusState private var isNotesFocused: Bool

    private var roll: Roll? {
        store.roll(for: rollId)
    }

    private var rollTitle: String {
        guard let roll else { return "Roll" }
        return store.label(for: roll)
    }

    var body: some View {
        Group {
            if let roll {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let stock = store.stock(for: roll.stockId), stock.rollImageName != nil {
                            DetailHeroBlock {
                                RollCanister3D(stock: stock)
                                    .frame(width: 250, height: 250)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        // Inventory uses the load slider; every other status uses the frame carousel.
                        loadOrExposureStage(roll)
                        rollFields(roll)
                    }
                    .instrumentDetailContent()
                }
                .instrumentDetailScroll()
            } else {
                VStack(alignment: .leading) {
                    Text("Roll not found")
                        .font(AppType.body)
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
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if roll?.isExpired == true {
                        ExpiredLabel()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(destructive: "Delete Roll", lucide: .trash) {
                        showingDeleteConfirm = true
                    }
                    .font(AppType.body)
                } label: {
                    LucideIcon(.ellipsis)
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
        .sheet(isPresented: $showingCameraPicker) {
            ChooseCameraSheet(
                onSelect: { camera in
                    store.assignRoll(rollId, to: camera.id)
                    showingCameraPicker = false
                },
                onDismiss: { showingCameraPicker = false }
            )
        }
        .sheet(isPresented: $showingAddDatePicker) {
            addDatePickerSheet
        }
        .sheet(isPresented: $showingFrozenDatePicker) {
            frozenDatePickerSheet
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

    private func loadOrExposureStage(_ roll: Roll) -> some View {
        LoadExposureStage(
            roll: roll,
            stock: store.stock(for: roll.stockId),
            onChoose: { showingCameraPicker = true },
            onAdvance: { store.advanceExposure(on: roll.id) },
            onUndo: { store.removeLastFrame(from: roll.id) },
            onSetCount: { store.setFrameCount($0, for: roll.id) },
            onFinishRoll: { store.setRollStatus(roll.id, to: .shotUndeveloped) }
        )
    }

    /// Everything below the scan button: the camera, then what is on the roll, then the
    /// status override, development, and finally notes. One 16pt stack with explicit
    /// rules, mirroring the Figma auto-layout.
    private func rollFields(_ roll: Roll) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            cameraRow(roll)
            techSpecsRows(roll)
            statusOverrideRow(roll)
            developmentRows(roll)
            notesRows(roll)
        }
        .padding(.top, AppTheme.tableGap)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    @ViewBuilder
    private func cameraRow(_ roll: Roll) -> some View {
        if !roll.status.isInventory {
            HairlineRule()
            menuRow("Camera", value: cameraDisplayValue(for: roll)) {
                Button("Not set") {
                    store.assignRoll(rollId, to: nil)
                }
                ForEach(store.cameras) { camera in
                    Button(camera.name) {
                        store.assignRoll(rollId, to: camera.id)
                    }
                }
            }
        }
    }

    /// The pipeline normally moves the roll along on its own, so this is an escape hatch
    /// rather than the usual way to change status — hence its place at the bottom.
    @ViewBuilder
    private func statusOverrideRow(_ roll: Roll) -> some View {
        if !roll.status.isInventory {
            HairlineRule()
            menuRow("Status override", value: roll.status.displayName) {
                ForEach(Self.postLoadStatuses, id: \.self) { status in
                    Button(status.displayName) {
                        selectPipelineStatus(status, for: roll)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notesRows(_ roll: Roll) -> some View {
        HairlineRule()
        SectionLabel(title: "Notes", style: .detail)
        TextField(
            placeholder: "Add a note",
            text: notesBinding(for: roll),
            axis: .vertical
        )
        .font(AppType.body)
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(2...8)
        .submitLabel(.return)
        .focused($isNotesFocused)
    }

    @ViewBuilder
    private func techSpecsRows(_ roll: Roll) -> some View {
        HairlineRule()
        stockRows(roll)
        formatAndFrameRows(roll)
        pushPullAndExpiryRows(roll)
    }

    @ViewBuilder
    private func stockRows(_ roll: Roll) -> some View {
        if let stock = store.stock(for: roll.stockId) {
            NavigationLink {
                StockDetailView(stockId: stock.id)
            } label: {
                DetailFieldRow(label: "Film") {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        DetailFieldValue(text: stock.name)
                        LucideIcon(.chevronRight)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HairlineRule()
            valueRow("ISO/ASA", value: "\(roll.shootingISO ?? stock.iso)")
            HairlineRule()
        }
    }

    @ViewBuilder
    private func formatAndFrameRows(_ roll: Roll) -> some View {
        valueRow("Format", value: roll.format.displayName)
        HairlineRule()
        DetailFieldRow(label: "Expected frames") {
            TextField(
                "36",
                value: exposuresBinding(for: roll),
                format: .number,
                prompt: .fieldPrompt("36")
            )
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
        }
        HairlineRule()
    }

    @ViewBuilder
    private func pushPullAndExpiryRows(_ roll: Roll) -> some View {
        // The Figma keeps every tech-spec value in the primary colour, including the
        // "Box speed" and "Not set" defaults, so these rows don't dim when unset.
        menuRow("Push/pull", value: roll.pushPullDisplayValue) {
            ForEach(Self.pushPullOptions, id: \.value) { option in
                Button(option.label) {
                    guard var updated = store.roll(for: rollId) else { return }
                    updated.pushPull = option.value == 0 ? nil : option.value
                    store.updateRoll(updated)
                }
            }
        }
        HairlineRule()
        expirationRow(roll)
        HairlineRule()
        storageRows(roll)
    }

    @ViewBuilder
    private func storageRows(_ roll: Roll) -> some View {
        menuRow("Storage method", value: roll.storageMethod.displayName) {
            ForEach(StorageMethod.allCases) { method in
                Button(method.displayName) {
                    setStorageMethod(method, on: roll)
                }
            }
        }
        if roll.storageMethod == .freezer {
            HairlineRule()
            frozenDateRow(roll)
        }
    }

    private func setStorageMethod(_ method: StorageMethod, on roll: Roll) {
        guard var updated = store.roll(for: rollId) else { return }
        updated.storageLocation = method.rawValue
        if method != .freezer {
            updated.frozenDate = nil
        } else if updated.frozenDate == nil {
            updated.frozenDate = Date()
        }
        store.updateRoll(updated)
    }

    private func frozenDateRow(_ roll: Roll) -> some View {
        Button {
            frozenDateDraft = roll.frozenDate ?? Date()
            showingFrozenDatePicker = true
        } label: {
            DetailFieldRow(label: "Frozen date") {
                DetailFieldValue(text: frozenDateDisplay(for: roll))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func frozenDateDisplay(for roll: Roll) -> String {
        guard let date = roll.frozenDate else { return "Not set" }
        return DateFormatters.medium.string(from: date)
    }

    private var frozenDatePickerSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xl) {
                DatePicker(
                    "Frozen date",
                    selection: $frozenDateDraft,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.horizontalPadding)

                Spacer(minLength: 0)
            }
            .instrumentScreen()
            .navigationTitle("Frozen date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        if var updated = store.roll(for: rollId) {
                            updated.frozenDate = nil
                            store.updateRoll(updated)
                        }
                        showingFrozenDatePicker = false
                    }
                    .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if var updated = store.roll(for: rollId) {
                            updated.frozenDate = Calendar.current.startOfDay(for: frozenDateDraft)
                            store.updateRoll(updated)
                        }
                        showingFrozenDatePicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func expirationRow(_ roll: Roll) -> some View {
        Button {
            addDateDraft = roll.expiryDate ?? Date()
            showingAddDatePicker = true
        } label: {
            DetailFieldRow(label: "Expiration date") {
                DetailFieldValue(text: addDateDisplayValue(for: roll))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row builders

    private func valueRow(_ label: String, value: String, isPlaceholder: Bool = false) -> some View {
        DetailFieldRow(label: label) {
            DetailFieldValue(text: value, isPlaceholder: isPlaceholder)
        }
    }

    private func menuRow<Content: View>(
        _ label: String,
        value: String,
        isPlaceholder: Bool = false,
        @ViewBuilder menu: @escaping () -> Content
    ) -> some View {
        DetailFieldRow(label: label) {
            Menu {
                menu()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    DetailFieldValue(text: value, isPlaceholder: isPlaceholder)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
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
        store.setRollStatus(roll.id, to: status, cameraId: roll.cameraId)
    }

    private static let pushPullOptions: [(label: String, value: Int)] = [
        ("Box speed", 0),
        ("Pull −1", -1),
        ("Push +1", 1),
        ("Push +2", 2),
    ]

    private func cameraDisplayValue(for roll: Roll) -> String {
        guard let cameraId = roll.cameraId,
              let camera = store.camera(for: cameraId) else {
            return "Not set"
        }
        return camera.name
    }

    @ViewBuilder
    private func developmentRows(_ roll: Roll) -> some View {
        let showDevelopment = roll.status == .atLab
            || roll.status == .developed
            || roll.development != nil

        if showDevelopment {
            HairlineRule()
            SectionLabel(title: "Development", style: .detail)
            menuRow(
                "Path",
                value: (store.roll(for: rollId)?.development?.path ?? .lab).displayName
            ) {
                ForEach(DevelopmentPath.allCases, id: \.self) { path in
                    Button(path.displayName) {
                        developmentPathBinding(for: roll).wrappedValue = path
                    }
                }
            }
            developmentPathRows(roll)
            developmentSummaryRow()
        }
    }

    @ViewBuilder
    private func developmentPathRows(_ roll: Roll) -> some View {
        let path = store.roll(for: rollId)?.development?.path
        if path == .lab {
            HairlineRule()
            fieldRow("Lab") {
                TextField(placeholder: "Lab name", text: labNameBinding(for: roll))
            }
        } else if path == .diy {
            HairlineRule()
            fieldRow("Developer") {
                TextField(placeholder: "Developer", text: devFieldBinding(for: roll, keyPath: \.developer))
            }
            HairlineRule()
            fieldRow("Dilution") {
                TextField(placeholder: "Dilution", text: devFieldBinding(for: roll, keyPath: \.dilution))
            }
            diyTimingRows(roll)
        }
    }

    @ViewBuilder
    private func diyTimingRows(_ roll: Roll) -> some View {
        HairlineRule()
        fieldRow("Time") {
            TextField(placeholder: "Minutes", text: devTimeBinding(for: roll))
                .keyboardType(.decimalPad)
        }
        HairlineRule()
        fieldRow("Temp") {
            TextField(placeholder: "°C", text: devTempBinding(for: roll))
                .keyboardType(.decimalPad)
        }
        HairlineRule()
        fieldRow("Agitation") {
            TextField(placeholder: "Notes", text: devFieldBinding(for: roll, keyPath: \.agitationNotes), axis: .vertical)
                .lineLimit(1...4)
        }
        developmentPresetRow(roll)
    }

    @ViewBuilder
    private func developmentPresetRow(_ roll: Roll) -> some View {
        if !store.devRecipePresets.isEmpty {
            HairlineRule()
            Menu("Apply preset") {
                ForEach(store.devRecipePresets) { preset in
                    Button(preset.summary) {
                        store.applyDevPreset(preset.id, to: roll.id)
                    }
                }
            }
            .font(AppType.body)
        }
    }

    @ViewBuilder
    private func developmentSummaryRow() -> some View {
        if let summary = store.roll(for: rollId)?.development?.summary {
            HairlineRule()
            valueRow("Summary", value: summary, isPlaceholder: true)
        }
    }

    /// Editable variant of `valueRow` — the field right-aligns into the value column.
    private func fieldRow<Content: View>(
        _ label: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DetailFieldRow(label: label) {
            content()
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Bindings

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
                    .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard var updated = store.roll(for: rollId) else { return }
                        updated.expiryDate = ExpirationDate.normalize(addDateDraft)
                        store.updateRoll(updated)
                        showingAddDatePicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func addDateDisplayValue(for roll: Roll) -> String {
        guard let date = roll.expiryDate else { return "Not set" }
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

}

#Preview {
    NavigationStack {
        RollDetailView(rollId: UUID())
    }
    .environment(AppStore())
}
