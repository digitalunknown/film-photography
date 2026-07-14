import PhotosUI
import SwiftUI
import UIKit

struct CameraDetailView: View {
    @Environment(AppStore.self) private var store
    let cameraId: UUID

    @State private var photoItem: PhotosPickerItem?
    @State private var selectedLoadRollId: UUID?
    @State private var selectedFridgeItemId: UUID?
    @State private var showingLoadPicker = false
    @State private var showingPurchaseDatePicker = false
    @State private var purchaseDateDraft = Date()
    @State private var selectedHistoryRoll: Roll?
    @State private var pendingLoadRevealRollId: UUID?
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

    private var sectionDivider: some View {
        SectionRule()
            .padding(.bottom, AppTheme.Spacing.md)
    }

    var body: some View {
        Group {
            if let camera {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        photoHero(camera)

                        if let roll = loadedRoll {
                            loadedRollSection(roll)
                            sectionDivider
                            loadedExposureStage(roll)
                            sectionDivider
                        } else {
                            loadSection(camera)
                            sectionDivider
                        }

                        notesSection(camera)
                        sectionDivider
                        specificationsSection(camera)

                        if !historyRolls.isEmpty {
                            sectionDivider
                            historySection
                        }
                    }
                    .instrumentDetailContent()
                }
                .instrumentDetailScroll()
            } else {
                VStack(alignment: .leading) {
                    Text("Camera not found")
                        .font(InstrumentFont.mono(13))
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
                Button("Done") {
                    isNotesFocused = false
                    isPriceFocused = false
                }
                .font(InstrumentFont.mono(13))
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
                    Label("Upload Photo", systemImage: "photo.badge.plus")
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
        let reveal = pendingLoadRevealRollId == roll.id
        return LoadExposureStage(
            roll: roll,
            stock: store.stock(for: roll.stockId),
            cameraName: camera?.name ?? "camera",
            canSlide: false,
            startMode: reveal ? .reveal : .carousel,
            onAdvance: { store.advanceExposure(on: roll.id) },
            onSetCount: { store.setFrameCount($0, for: roll.id) },
            onRevealFinished: {
                pendingLoadRevealRollId = nil
            }
        )
        .id("camera-load-stage-\(roll.id)-\(reveal ? "reveal" : "carousel")")
    }

    private func loadedRollSection(_ roll: Roll) -> some View {
        DetailSection(title: "Loaded") {
            Button {
                selectedHistoryRoll = roll
            } label: {
                RollLedgerRow(roll: roll, showsCameraName: false)
            }
            .buttonStyle(.plain)
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    private func loadSection(_ camera: Camera) -> some View {
        DetailSection(title: "Load") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                FilmLoadSlider(
                    stock: currentLoadSelection?.stock,
                    cameraName: camera.name,
                    onChooseRoll: { showingLoadPicker = true }
                ) {
                    if let selection = currentLoadSelection {
                        performLoad(onto: camera, selection: selection)
                        pendingLoadRevealRollId = store.loadedRoll(for: camera.id)?.id
                    }
                }
                .id(currentLoadSelection?.id ?? "empty-load")

                if currentLoadSelection != nil {
                    HStack {
                        Text(selectedLoadLabel)
                            .font(InstrumentFont.mono(11))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Change →") {
                            showingLoadPicker = true
                        }
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                } else {
                    Text(loadEmptyMessage)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func specificationsSection(_ camera: Camera) -> some View {
        DetailSection(title: "Technical Specifications") {
            VStack(alignment: .leading, spacing: 0) {
                InstrumentEditableRow(label: "Name", showsDivider: false) {
                    TextField("Camera name", text: binding(camera, \.name))
                        .multilineTextAlignment(.leading)
                }
                InstrumentEditableRow(label: "Lens") {
                    TextField("38mm f/1.8", text: binding(camera, \.lensSubtitle))
                        .multilineTextAlignment(.leading)
                }
                InstrumentMenuRow(
                    label: "Type",
                    value: camera.cameraType.isEmpty ? "Not Set" : camera.cameraType,
                    valueBright: !camera.cameraType.isEmpty
                ) {
                    ForEach(cameraTypes, id: \.self) { type in
                        Button(type) {
                            update(camera) { $0.cameraType = type }
                        }
                    }
                }
                InstrumentMenuRow(
                    label: "Default format",
                    value: camera.defaultFormat?.displayName ?? "Not Set",
                    valueBright: camera.defaultFormat != nil
                ) {
                    Button("Not Set") {
                        update(camera) { $0.defaultFormat = nil }
                    }
                    ForEach(FilmFormat.allCases) { fmt in
                        Button(fmt.displayName) {
                            update(camera) { $0.defaultFormat = fmt }
                        }
                    }
                }
                InstrumentEditableRow(label: "Serial number") {
                    TextField("Optional", text: optionalStringBinding(camera, \.serialNumber))
                        .multilineTextAlignment(.leading)
                }
                Button {
                    purchaseDateDraft = camera.purchaseDate ?? Date()
                    showingPurchaseDatePicker = true
                } label: {
                    InstrumentRow(label: "Purchase date") {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text(purchaseDateDisplay(for: camera))
                                .font(InstrumentFont.mono(12))
                                .foregroundStyle(camera.purchaseDate != nil ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(InstrumentFont.mono(9, weight: .bold))
                                .foregroundStyle(AppTheme.textTertiary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
                InstrumentEditableRow(label: "Purchase price") {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Menu {
                            ForEach(currencyMenuCodes(for: camera), id: \.self) { code in
                                Button(code) {
                                    update(camera) { $0.purchaseCurrency = code }
                                }
                            }
                        } label: {
                            HStack(spacing: AppTheme.Spacing.xs) {
                                Text(camera.purchaseCurrency)
                                    .font(InstrumentFont.mono(12))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(InstrumentFont.mono(9, weight: .bold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        TextField("0", text: priceBinding(camera))
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(AppTheme.textPrimary)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .focused($isPriceFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func notesSection(_ camera: Camera) -> some View {
        DetailSection(title: "Notes") {
            TextField(
                "Add a note",
                text: notesBinding(camera),
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

    private var historySection: some View {
        DetailSection(title: "History") {
            VStack(spacing: 0) {
                ForEach(Array(historyRolls.enumerated()), id: \.element.id) { index, roll in
                    Button {
                        selectedHistoryRoll = roll
                    } label: {
                        cameraHistoryRow(roll, showsDivider: index > 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cameraHistoryRow(_ roll: Roll, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            if showsDivider {
                HairlineRule()
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(historyDateText(for: roll))
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Text(historyFilmType(for: roll))
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Text(store.stock(for: roll.stockId)?.name ?? roll.shortId)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(roll.status.displayName)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }

    private func historyDateText(for roll: Roll) -> String {
        guard let date = roll.historyDate else { return "—" }
        return DateFormatters.medium.string(from: date)
    }

    private func historyFilmType(for roll: Roll) -> String {
        store.stock(for: roll.stockId)?.filmType.label ?? roll.format.displayName
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
            VStack(spacing: AppTheme.Spacing.lg) {
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
                    .font(InstrumentFont.mono(13))
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
                    .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var loadPickerSheet: some View {
        NavigationStack {
            List {
                if !store.inventoryRolls.isEmpty {
                    Section("In stock") {
                        ForEach(store.inventoryRolls) { roll in
                            Button {
                                selectedLoadRollId = roll.id
                                selectedFridgeItemId = nil
                                showingLoadPicker = false
                            } label: {
                                Text(inventoryRollLabel(for: roll))
                                    .font(InstrumentFont.mono(13))
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }
                    }
                }

                if !store.availableFridgeItems.isEmpty {
                    Section("Unopened stock") {
                        ForEach(store.availableFridgeItems) { item in
                            Button {
                                selectedFridgeItemId = item.id
                                selectedLoadRollId = nil
                                showingLoadPicker = false
                            } label: {
                                Text(fridgeItemLabel(for: item))
                                    .font(InstrumentFont.mono(13))
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }
                    }
                }

                if store.inventoryRolls.isEmpty && store.availableFridgeItems.isEmpty {
                    Text(loadEmptyMessage)
                        .font(InstrumentFont.mono(12))
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
                        .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private enum LoadSelection {
        case roll(Roll, FilmStock?)
        case fridgeItem(FridgeItem, FilmStock?)

        var id: String {
            switch self {
            case .roll(let roll, _): return "roll-\(roll.id)"
            case .fridgeItem(let item, _): return "fridge-\(item.id)"
            }
        }

        var stock: FilmStock? {
            switch self {
            case .roll(_, let stock), .fridgeItem(_, let stock): return stock
            }
        }
    }

    private var currentLoadSelection: LoadSelection? {
        if let selectedLoadRollId, let roll = store.roll(for: selectedLoadRollId) {
            return .roll(roll, store.stock(for: roll.stockId))
        }
        if let selectedFridgeItemId,
           let item = store.fridgeItems.first(where: { $0.id == selectedFridgeItemId }) {
            return .fridgeItem(item, store.stock(for: item.stockId))
        }
        return nil
    }

    private var selectedLoadLabel: String {
        switch currentLoadSelection {
        case .roll(let roll, _):
            return inventoryRollLabel(for: roll)
        case .fridgeItem(let item, _):
            return fridgeItemLabel(for: item)
        case nil:
            return "Not Set"
        }
    }

    private var loadEmptyMessage: String {
        if store.inventoryRolls.isEmpty && store.availableFridgeItems.isEmpty {
            if store.activeRolls.isEmpty {
                return "No rolls yet. Add a roll on the Rolls tab, then load it here."
            }
            return "No unloadable stock. Set a roll to In stock — or add unopened stock — then choose it here."
        }
        return "Tap the empty canister to choose a roll, then slide to load."
    }

    private func inventoryRollLabel(for roll: Roll) -> String {
        let stockName = store.stock(for: roll.stockId)?.name ?? roll.shortId
        return "\(stockName) · \(roll.shortId)"
    }

    private func fridgeItemLabel(for item: FridgeItem) -> String {
        let stockName = store.stock(for: item.stockId)?.name ?? "Stock"
        let qty = item.quantity > 1 ? " · ×\(item.quantity)" : ""
        return "\(stockName) · \(item.format.displayName)\(qty)"
    }

    private func purchaseDateDisplay(for camera: Camera) -> String {
        guard let date = camera.purchaseDate else { return "Not Set" }
        return DateFormatters.medium.string(from: date)
    }

    private func performLoad(onto camera: Camera, selection: LoadSelection) {
        switch selection {
        case .roll(let roll, _):
            store.assignRoll(roll.id, to: camera.id)
        case .fridgeItem(let item, let stock):
            store.loadRoll(
                cameraId: camera.id,
                stockId: item.stockId,
                format: item.format,
                iso: stock?.iso ?? 400,
                exposures: item.format.defaultExposures,
                expiryDate: item.expiryDate,
                fromFridgeItemId: item.id
            )
        }
        selectedLoadRollId = nil
        selectedFridgeItemId = nil
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
