import PhotosUI
import SwiftUI
import UIKit

struct CameraDetailView: View {
    @Environment(AppStore.self) private var store
    let cameraId: UUID

    @State private var photoItem: PhotosPickerItem?
    @State private var showingLoadPicker = false
    @State private var showingPurchaseDatePicker = false
    @State private var purchaseDateDraft = Date()
    @State private var selectedHistoryRoll: Roll?
    @FocusState private var isNotesFocused: Bool
    @FocusState private var isPriceFocused: Bool

    private let cameraTypes = ["Rangefinder", "SLR", "Point & shoot", "TLR", "Large format", "Instant"]
    private let currencyCodes = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HKD", "SGD", "KRW", "CNY", "MXN", "BRL"]

    private var camera: Camera? {
        store.camera(for: cameraId)
    }

    private var loadedRoll: Roll? {
        store.loadedRoll(for: cameraId)
    }

    private var historyRolls: [Roll] {
        let loadedId = loadedRoll?.id
        return store.rollsForCamera(cameraId)
            .filter { $0.id != loadedId }
            .sorted { ($0.historyDate ?? .distantPast) > ($1.historyDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if let camera {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        photoHero(camera)

                        if let roll = loadedRoll {
                            loadedRollSection(roll)
                            loadedExposureStage(roll)
                        } else {
                            loadSection
                        }

                        cameraFields(camera)
                    }
                    .instrumentDetailContent()
                }
                .instrumentDetailScroll()
            } else {
                VStack(alignment: .leading) {
                    Text("Camera not found")
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
        .instrumentDetailChrome()
        .instrumentDetailNavigation(title: camera?.name ?? "Camera")
        .navigationDestination(item: $selectedHistoryRoll) { roll in
            RollDetailView(rollId: roll.id)
        }
        .sheet(isPresented: $showingLoadPicker) {
            loadPickerSheet
        }
        .sheet(isPresented: $showingPurchaseDatePicker) {
            purchaseDatePickerSheet
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                InstrumentKeyboardDoneButton {
                    isNotesFocused = false
                    isPriceFocused = false
                }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(from: newItem) }
        }
    }

    private func photoHero(_ camera: Camera) -> some View {
        DetailHeroBlock {
            Menu {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Upload Photo", lucide: .imagePlus)
                }
                if camera.photoData != nil {
                    Button("Remove", role: .destructive) {
                        update(camera) { $0.photoData = nil }
                    }
                }
            } label: {
                CameraPhotoPlate(photoData: camera.photoData, square: false, height: 220)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadedExposureStage(_ roll: Roll) -> some View {
        LoadExposureStage(
            roll: roll,
            stock: store.stock(for: roll.stockId),
            onAdvance: { store.advanceExposure(on: roll.id) },
            onUndo: { store.removeLastFrame(from: roll.id) },
            onSetCount: { store.setFrameCount($0, for: roll.id) },
            onFinishRoll: { store.setRollStatus(roll.id, to: .shotUndeveloped) }
        )
        .id("camera-load-stage-\(roll.id)")
    }

    private func loadedRollSection(_ roll: Roll) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SectionLabel(title: "Loaded", style: .detail)
            Button {
                selectedHistoryRoll = roll
            } label: {
                RollLedgerRow(roll: roll, showsCameraName: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private var loadSection: some View {
        Button {
            showingLoadPicker = true
        } label: {
            PillButtonLabel(title: "Load Roll", icon: .film)
        }
        .buttonStyle(.plain)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    /// Everything below the exposure stage: the spec table, then history, then notes
    /// last. One 16pt stack with explicit rules and trailing-aligned values, mirroring
    /// the roll detail layout.
    private func cameraFields(_ camera: Camera) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            specRows(camera)
            historyRows
            notesRows(camera)
        }
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    @ViewBuilder
    private func specRows(_ camera: Camera) -> some View {
        HairlineRule()
        fieldRow("Name") {
            TextField(placeholder: "Camera name", text: binding(camera, \.name))
        }
        HairlineRule()
        fieldRow("Lens") {
            TextField(placeholder: "38mm f/1.8", text: binding(camera, \.lensSubtitle))
        }
        HairlineRule()
        menuRow("Type", value: camera.cameraType.isEmpty ? "Not set" : camera.cameraType) {
            ForEach(cameraTypes, id: \.self) { type in
                Button(type) {
                    update(camera) { $0.cameraType = type }
                }
            }
        }
        HairlineRule()
        menuRow("Default format", value: camera.defaultFormat?.displayName ?? "Not set") {
            Button("Not set") {
                update(camera) { $0.defaultFormat = nil }
            }
            ForEach(FilmFormat.allCases) { fmt in
                Button(fmt.displayName) {
                    update(camera) { $0.defaultFormat = fmt }
                }
            }
        }
        HairlineRule()
        fieldRow("Serial number") {
            TextField(placeholder: "Optional", text: optionalStringBinding(camera, \.serialNumber))
        }
        HairlineRule()
        purchaseDateRow(camera)
        HairlineRule()
        purchasePriceRow(camera)
    }

    private func purchaseDateRow(_ camera: Camera) -> some View {
        Button {
            purchaseDateDraft = camera.purchaseDate ?? Date()
            showingPurchaseDatePicker = true
        } label: {
            DetailFieldRow(label: "Purchase date") {
                DetailFieldValue(text: purchaseDateDisplay(for: camera))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The amount right-aligns into the value column and the currency menu keeps its
    /// chevron at the trailing edge, where every other dropdown row puts it.
    private func purchasePriceRow(_ camera: Camera) -> some View {
        DetailFieldRow(label: "Purchase price") {
            HStack(spacing: AppTheme.Spacing.xs) {
                TextField(placeholder: "0", text: priceBinding(camera))
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isPriceFocused)

                Menu {
                    ForEach(currencyMenuCodes(for: camera), id: \.self) { code in
                        Button(code) {
                            update(camera) { $0.purchaseCurrency = code }
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        DetailFieldValue(text: camera.purchaseCurrency)
                        LucideIcon(.chevronsUpDown)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Currency")
            }
        }
    }

    @ViewBuilder
    private var historyRows: some View {
        if !historyRolls.isEmpty {
            HairlineRule()
            SectionLabel(title: "History", style: .detail)
            ForEach(Array(historyRolls.enumerated()), id: \.element.id) { index, roll in
                if index > 0 {
                    HairlineRule()
                }
                Button {
                    selectedHistoryRoll = roll
                } label: {
                    DetailFieldRow(label: historyDateText(for: roll)) {
                        VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                            DetailFieldValue(text: store.label(for: roll))
                            DetailFieldValue(text: roll.status.displayName, isPlaceholder: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func notesRows(_ camera: Camera) -> some View {
        HairlineRule()
        SectionLabel(title: "Notes", style: .detail)
        TextField(
            placeholder: "Add a note",
            text: notesBinding(camera),
            axis: .vertical
        )
        .font(AppType.body)
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(2...8)
        .submitLabel(.return)
        .focused($isNotesFocused)
    }

    // MARK: - Row builders

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

    /// Editable variant — the field right-aligns into the value column.
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

    private func historyDateText(for roll: Roll) -> String {
        guard let date = roll.historyDate else { return "—" }
        return DateFormatters.medium.string(from: date)
    }

    private func currencyMenuCodes(for camera: Camera) -> [String] {
        var codes = currencyCodes
        if !codes.contains(camera.purchaseCurrency) {
            codes.insert(camera.purchaseCurrency, at: 0)
        }
        return codes
    }

    private var purchaseDatePickerSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xl) {
                DatePicker(
                    "Purchase date",
                    selection: $purchaseDateDraft,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.horizontalPadding)

                Spacer(minLength: 0)
            }
            .instrumentScreen()
            .navigationTitle("Purchase date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        if let camera = camera {
                            update(camera) { $0.purchaseDate = nil }
                        }
                        showingPurchaseDatePicker = false
                    }
                    .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let camera = camera {
                            update(camera) {
                                $0.purchaseDate = Calendar.current.startOfDay(for: purchaseDateDraft)
                            }
                        }
                        showingPurchaseDatePicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var loadPickerSheet: some View {
        NavigationStack {
            List {
                if !store.inventoryRolls.isEmpty {
                    Section("In stock") {
                        ForEach(store.inventoryRolls) { roll in
                            Button {
                                showingLoadPicker = false
                                store.assignRoll(roll.id, to: cameraId)
                            } label: {
                                Text(inventoryRollLabel(for: roll))
                                    .font(AppType.body)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }
                    }
                }

                if !store.availableFridgeItems.isEmpty {
                    Section("Unopened stock") {
                        ForEach(store.availableFridgeItems) { item in
                            Button {
                                showingLoadPicker = false
                                loadFridgeItem(item)
                            } label: {
                                Text(fridgeItemLabel(for: item))
                                    .font(AppType.body)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }
                    }
                }

                if store.inventoryRolls.isEmpty && store.availableFridgeItems.isEmpty {
                    Text(loadEmptyMessage)
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(Color.clear)
                }
            }
            .instrumentFormStyle()
            .navigationTitle("Choose roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingLoadPicker = false }
                        .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var loadEmptyMessage: String {
        if store.inventoryRolls.isEmpty && store.availableFridgeItems.isEmpty {
            if store.activeRolls.isEmpty {
                return "No rolls yet. Add a roll on the Rolls tab, then load it here."
            }
            return "No unloadable stock. Set a roll to In stock — or add unopened stock — then choose it here."
        }
        return "Choose a roll to load it."
    }

    private func inventoryRollLabel(for roll: Roll) -> String {
        let exposures = "\(roll.totalExposures) exp"
        return "\(store.label(for: roll)) · \(roll.format.displayName) · \(exposures)"
    }

    private func fridgeItemLabel(for item: FridgeItem) -> String {
        let stockName = store.stock(for: item.stockId)?.name ?? "Stock"
        let qty = item.quantity > 1 ? " · ×\(item.quantity)" : ""
        return "\(stockName) · \(item.format.displayName)\(qty)"
    }

    private func purchaseDateDisplay(for camera: Camera) -> String {
        guard let date = camera.purchaseDate else { return "Not set" }
        return DateFormatters.medium.string(from: date)
    }

    /// Unopened stock becomes a fresh roll that is loaded straight into this camera.
    private func loadFridgeItem(_ item: FridgeItem) {
        store.loadRoll(
            cameraId: cameraId,
            stockId: item.stockId,
            format: item.format,
            iso: store.stock(for: item.stockId)?.iso ?? 400,
            exposures: item.format.defaultExposures,
            expiryDate: item.expiryDate,
            fromFridgeItemId: item.id
        )
    }

    // MARK: - Bindings

    private func binding(_ camera: Camera, _ keyPath: WritableKeyPath<Camera, String>) -> Binding<String> {
        Binding(
            get: { store.camera(for: cameraId)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                update(camera) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func optionalStringBinding(_ camera: Camera, _ keyPath: WritableKeyPath<Camera, String?>) -> Binding<String> {
        Binding(
            get: { store.camera(for: cameraId)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                update(camera) { $0[keyPath: keyPath] = newValue.isEmpty ? nil : newValue }
            }
        )
    }

    private func priceBinding(_ camera: Camera) -> Binding<String> {
        Binding(
            get: {
                guard let price = store.camera(for: cameraId)?.purchasePrice else { return "" }
                if price.truncatingRemainder(dividingBy: 1) == 0 {
                    return String(format: "%.0f", price)
                }
                return String(format: "%.2f", price)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                update(camera) {
                    $0.purchasePrice = trimmed.isEmpty
                        ? nil
                        : Double(trimmed.replacingOccurrences(of: ",", with: "."))
                }
            }
        )
    }

    private func notesBinding(_ camera: Camera) -> Binding<String> {
        Binding(
            get: { store.camera(for: cameraId)?.notes ?? "" },
            set: { newValue in
                update(camera) {
                    let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.notes = text.isEmpty ? nil : newValue
                }
            }
        )
    }

    private func update(_ camera: Camera, _ transform: (inout Camera) -> Void) {
        guard var current = store.camera(for: cameraId) else { return }
        transform(&current)
        store.updateCamera(current)
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              var camera = store.camera(for: cameraId) else { return }

        if let image = UIImage(data: data) {
            camera.photoData = image.jpegData(compressionQuality: 0.82)
        } else {
            camera.photoData = data
        }
        store.updateCamera(camera)
    }
}

#Preview {
    NavigationStack {
        CameraDetailView(cameraId: AppStore().cameras[0].id)
    }
    .environment(AppStore())
}
