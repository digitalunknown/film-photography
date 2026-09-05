import SwiftUI

/// The two ways into the add-roll form, chosen from the menu behind the + button.
enum AddRollEntry: String, Identifiable {
    case library
    case manual

    var id: String { rawValue }
}

struct AddRollView: View {
    let entry: AddRollEntry

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStockId: UUID?
    @State private var manualStockName = ""
    @State private var boxSpeedText = "400"
    @State private var showingStockPicker = false
    @State private var status: RollStatus = .inFridge
    @State private var format: FilmFormat = .format35Full
    @State private var selectedCameraId: UUID?
    @State private var exposuresText = "36"
    @State private var pushPull = 0
    @State private var frameCountText = "0"
    @State private var storageLocation = "Fridge"
    @State private var labName = "The Darkroom"
    @State private var includeExpiryDate = false
    @State private var expiryDate = Date()
    @State private var showingExpiryPicker = false
    @State private var hasAppeared = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case stock, boxSpeed, exposures, frames, storage, lab
    }

    private static let pushPullOptions: [(label: String, value: Int)] = [
        ("Box speed", 0),
        ("Pull −1", -1),
        ("Push +1", 1),
        ("Push +2", 2),
    ]

    private var exposures: Int {
        max(Int(exposuresText.filter(\.isNumber)) ?? format.defaultExposures, 1)
    }

    private var frameCount: Int {
        max(Int(frameCountText.filter(\.isNumber)) ?? 0, 0)
    }

    private var boxSpeed: Int {
        max(Int(boxSpeedText.filter(\.isNumber)) ?? 400, 1)
    }

    private var selectedStock: FilmStock? {
        selectedStockId.flatMap { store.stock(for: $0) }
    }

    private var isManual: Bool {
        entry == .manual
    }

    private var canSave: Bool {
        if isManual {
            guard !manualStockName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        } else {
            guard selectedStockId != nil else { return false }
        }
        if status == .inCamera { return selectedCameraId != nil }
        return true
    }

    private var pushPullLabel: String {
        Self.pushPullOptions.first { $0.value == pushPull }?.label ?? "Box speed"
    }

    private var availableCameras: [Camera] {
        store.cameras.filter { store.loadedRoll(for: $0.id) == nil || $0.id == selectedCameraId }
    }

    private var selectedCameraName: String? {
        selectedCameraId.flatMap { id in store.camera(for: id)?.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                detailsForm
                    .instrumentDetailContent()
            }
            .instrumentDetailScroll()
            .instrumentScreen()
            .navigationTitle("Add Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        LucideIcon(.x)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .font(AppType.body)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    InstrumentKeyboardDoneButton {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showingStockPicker, onDismiss: {
                // Backing out of the picker on the library path leaves nothing to describe,
                // so the whole flow closes rather than stranding an empty form.
                if entry == .library, selectedStockId == nil {
                    dismiss()
                }
            }) {
                StockPickerSheet(
                    title: "Choose Film",
                    selectedStockId: selectedStockId
                ) { stock in
                    selectedStockId = stock.id
                    if exposuresText == "36" || exposuresText == "72" || exposuresText == "24" || exposuresText.isEmpty {
                        exposuresText = String(format.defaultExposures)
                    }
                }
            }
            .sheet(isPresented: $showingExpiryPicker) {
                expirationPickerSheet
            }
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                exposuresText = String(format.defaultExposures)

                // The library path was already a choice to pick a stock, so it goes
                // straight there instead of opening on a form with an empty stock row.
                // A sheet raised while this one is still animating in can be dropped,
                // hence waiting for it to settle first.
                guard entry == .library else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    showingStockPicker = true
                }
            }
        }
        .instrumentSheetChrome()
    }

    private var expirationPickerSheet: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                MonthYearPicker(date: $expiryDate)
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
                        includeExpiryDate = false
                        showingExpiryPicker = false
                    }
                    .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        includeExpiryDate = true
                        expiryDate = ExpirationDate.normalize(expiryDate)
                        showingExpiryPicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var detailsForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            filmRows
            pipelineRows
            cameraRows
            storageRows
            labRows
        }
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    @ViewBuilder
    private var filmRows: some View {
        SectionLabel(title: "Film", style: .detail)

        if isManual {
            fieldRow("Stock") {
                TextField(placeholder: "Film name", text: $manualStockName)
                    .focused($focusedField, equals: .stock)
            }
            HairlineRule()
            fieldRow("Box speed") {
                TextField(placeholder: "400", text: $boxSpeedText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .boxSpeed)
            }
        } else {
            stockPickerRow
            HairlineRule()
            valueRow(
                "Box speed",
                value: selectedStock.map { "ISO \($0.iso)" } ?? "—",
                isPlaceholder: selectedStock == nil
            )
        }

        HairlineRule()
        menuRow("Format", value: format.displayName) {
            ForEach(FilmFormat.allCases) { fmt in
                Button(fmt.displayName) {
                    format = fmt
                    if exposuresText == "36" || exposuresText == "72" || exposuresText == "24" {
                        exposuresText = String(fmt.defaultExposures)
                    }
                }
            }
        }

        HairlineRule()
        fieldRow("Expected frames") {
            TextField(placeholder: "36", text: $exposuresText)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .exposures)
        }

        // Tech-spec values stay in the primary colour even at their defaults,
        // matching the roll detail screen.
        HairlineRule()
        menuRow("Push/pull", value: pushPullLabel) {
            ForEach(Self.pushPullOptions, id: \.value) { option in
                Button(option.label) { pushPull = option.value }
            }
        }

        HairlineRule()
        expirationRow
    }

    @ViewBuilder
    private var pipelineRows: some View {
        HairlineRule()
        SectionLabel(title: "Pipeline", style: .detail)
        menuRow("Status", value: status.displayName) {
            ForEach(RollStatus.pipelineCases, id: \.self) { stage in
                Button(stage.displayName) { status = stage }
            }
        }
    }

    @ViewBuilder
    private var cameraRows: some View {
        if status == .inCamera {
            HairlineRule()
            SectionLabel(title: "Camera", style: .detail)
            menuRow(
                "Loaded in",
                value: selectedCameraName ?? "Select camera",
                isPlaceholder: selectedCameraId == nil
            ) {
                ForEach(availableCameras) { camera in
                    Button(camera.name) { selectedCameraId = camera.id }
                }
            }
            HairlineRule()
            fieldRow("Frames shot") {
                TextField(placeholder: "0", text: $frameCountText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .frames)
            }
        } else if status.showsCamera {
            HairlineRule()
            SectionLabel(title: "Camera", style: .detail)
            menuRow("Shot with", value: selectedCameraName ?? "None") {
                Button("None") { selectedCameraId = nil }
                ForEach(store.cameras) { camera in
                    Button(camera.name) { selectedCameraId = camera.id }
                }
            }
        }
    }

    @ViewBuilder
    private var storageRows: some View {
        if status == .shotUndeveloped {
            HairlineRule()
            SectionLabel(title: "Storage", style: .detail)
            fieldRow("Location") {
                TextField(placeholder: "Fridge", text: $storageLocation)
                    .focused($focusedField, equals: .storage)
            }
        }
    }

    @ViewBuilder
    private var labRows: some View {
        if status == .atLab {
            HairlineRule()
            SectionLabel(title: "Lab", style: .detail)
            fieldRow("Lab name") {
                TextField(placeholder: "Lab", text: $labName)
                    .focused($focusedField, equals: .lab)
            }
        }
    }

    private var expirationRow: some View {
        Button {
            showingExpiryPicker = true
        } label: {
            DetailFieldRow(label: "Expiration date") {
                DetailFieldValue(
                    text: includeExpiryDate
                        ? DateFormatters.monthYear.string(from: expiryDate)
                        : "Not set"
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var stockPickerRow: some View {
        Button {
            showingStockPicker = true
        } label: {
            DetailFieldRow(label: "Stock") {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if selectedStock != nil {
                        RollPlate(stock: selectedStock, size: 22)
                    }
                    DetailFieldValue(
                        text: selectedStock?.name ?? "Choose film",
                        isPlaceholder: selectedStock == nil
                    )
                    .lineLimit(2)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stock")
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

    private func save() {
        let stockId: UUID
        let shootingISO: Int?

        if isManual {
            let name = manualStockName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let stock = store.addCustomStock(name: name, iso: boxSpeed)
            stockId = stock.id
            shootingISO = boxSpeed
        } else {
            guard let selected = selectedStockId else { return }
            stockId = selected
            shootingISO = selectedStock?.iso
        }

        store.addRoll(
            stockId: stockId,
            status: status,
            cameraId: selectedCameraId,
            format: format,
            exposures: exposures,
            pushPull: pushPull,
            shootingISO: shootingISO,
            frameCount: frameCount,
            storageLocation: storageLocation,
            labName: labName,
            expiryDate: includeExpiryDate ? ExpirationDate.normalize(expiryDate) : nil
        )
        dismiss()
    }
}

#Preview {
    AddRollView(entry: .manual)
        .environment(AppStore())
}
