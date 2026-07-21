import SwiftUI
import UIKit

struct AddRollView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum EntryMethod {
        case library
        case manual
    }

    @State private var entryMethod: EntryMethod?
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
    @State private var showingPhotoCamera = false
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
        entryMethod == .manual
    }

    /// Form appears after library pick, or immediately for manual entry.
    private var showsDetails: Bool {
        entryMethod == .manual || selectedStockId != nil
    }

    private var canSave: Bool {
        guard showsDetails else { return false }
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

    private var sectionDivider: some View {
        SectionRule()
            .padding(.bottom, AppTheme.Spacing.md)
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
                VStack(alignment: .leading, spacing: 0) {
                    if showsDetails {
                        detailsForm
                    } else {
                        entryMethodList
                    }
                }
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
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if showsDetails {
                        Button("Add") { save() }
                            .font(InstrumentFont.mono(13))
                            .disabled(!canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    InstrumentKeyboardDoneButton {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showingStockPicker, onDismiss: {
                if entryMethod == .library, selectedStockId == nil {
                    entryMethod = nil
                }
            }) {
                StockPickerSheet(
                    title: "Choose film",
                    selectedStockId: selectedStockId
                ) { stock in
                    selectedStockId = stock.id
                    if entryMethod == nil {
                        entryMethod = .library
                    }
                    if exposuresText == "36" || exposuresText == "72" || exposuresText == "24" || exposuresText.isEmpty {
                        exposuresText = String(format.defaultExposures)
                    }
                }
            }
            .sheet(isPresented: $showingExpiryPicker) {
                expirationPickerSheet
            }
            .onAppear {
                exposuresText = String(format.defaultExposures)
            }
            .fullScreenCover(isPresented: $showingPhotoCamera) {
                DeviceCameraPicker(
                    onCapture: { image in
                        showingPhotoCamera = false
                        handOffToLoadFlow(image: image)
                    },
                    onCancel: {
                        showingPhotoCamera = false
                    }
                )
                .ignoresSafeArea()
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
                    .font(InstrumentFont.mono(13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        includeExpiryDate = true
                        expiryDate = ExpirationDate.normalize(expiryDate)
                        showingExpiryPicker = false
                    }
                    .font(InstrumentFont.mono(13))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func handOffToLoadFlow(image: UIImage?) {
        store.pendingLoadCapture = image
        store.loadFlowStartWithCamera = true
        store.showingAddRoll = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            store.showingLoadFlow = true
        }
    }

    private var entryMethodList: some View {
        VStack(spacing: 0) {
            entryMethodRow(
                title: "Choose from library",
                subtitle: "Pick a stock from your film library"
            ) {
                entryMethod = .library
                showingStockPicker = true
            }

            HairlineRule()

            entryMethodRow(
                title: "Add manually",
                subtitle: "Enter roll details yourself"
            ) {
                entryMethod = .manual
            }

            HairlineRule()

            entryMethodRow(
                title: "Add with photo",
                subtitle: "Scan a canister or roll box"
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingPhotoCamera = true
                } else {
                    handOffToLoadFlow(image: nil)
                }
            }
        }
        .padding(.top, AppTheme.Spacing.sm)
    }

    private func entryMethodRow(
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(title)
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(InstrumentFont.mono(11, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailsForm: some View {
        DetailSection(title: "Film") {
            VStack(spacing: 0) {
                if isManual {
                    InstrumentEditableRow(label: "Stock") {
                        TextField("Film name", text: $manualStockName)
                            .focused($focusedField, equals: .stock)
                    }

                    InstrumentEditableRow(label: "Box speed") {
                        TextField("400", text: $boxSpeedText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .boxSpeed)
                    }
                } else {
                    stockPickerRow(showsDivider: false)

                    DataRow(
                        label: "Box speed",
                        value: selectedStock.map { "ISO \($0.iso)" } ?? "—"
                    )
                }

                InstrumentMenuRow(
                    label: "Format",
                    value: format.displayName,
                    valueBright: true
                ) {
                    ForEach(FilmFormat.allCases) { fmt in
                        Button(fmt.displayName) {
                            format = fmt
                            if exposuresText == "36" || exposuresText == "72" || exposuresText == "24" {
                                exposuresText = String(fmt.defaultExposures)
                            }
                        }
                    }
                }

                InstrumentEditableRow(label: "Expected frames") {
                    TextField("36", text: $exposuresText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .exposures)
                }

                InstrumentMenuRow(
                    label: "Push / pull",
                    value: pushPullLabel,
                    valueBright: pushPull != 0
                ) {
                    ForEach(Self.pushPullOptions, id: \.value) { option in
                        Button(option.label) { pushPull = option.value }
                    }
                }

                Button {
                    showingExpiryPicker = true
                } label: {
                    InstrumentRow(label: "Expiration date") {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text(
                                includeExpiryDate
                                    ? DateFormatters.monthYear.string(from: expiryDate)
                                    : "Not set"
                            )
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(
                                includeExpiryDate ? AppTheme.textPrimary : AppTheme.textSecondary
                            )
                            .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.down")
                                .font(InstrumentFont.mono(9, weight: .bold))
                                .foregroundStyle(AppTheme.textTertiary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }

        sectionDivider

        DetailSection(title: "Pipeline") {
            InstrumentMenuRow(
                label: "Status",
                value: status.displayName,
                valueBright: true,
                showsDivider: false
            ) {
                ForEach(RollStatus.pipelineCases, id: \.self) { stage in
                    Button(stage.displayName) { status = stage }
                }
            }
        }

        if status == .inCamera {
            sectionDivider
            DetailSection(title: "Camera") {
                VStack(spacing: 0) {
                    InstrumentMenuRow(
                        label: "Loaded in",
                        value: selectedCameraName ?? "Select camera",
                        valueBright: selectedCameraId != nil,
                        showsDivider: false
                    ) {
                        ForEach(availableCameras) { camera in
                            Button(camera.name) { selectedCameraId = camera.id }
                        }
                    }
                    InstrumentEditableRow(label: "Frames shot") {
                        TextField("0", text: $frameCountText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .frames)
                    }
                }
            }
        } else if status.showsCamera {
            sectionDivider
            DetailSection(title: "Camera") {
                InstrumentMenuRow(
                    label: "Shot with",
                    value: selectedCameraName ?? "None",
                    valueBright: selectedCameraId != nil,
                    showsDivider: false
                ) {
                    Button("None") { selectedCameraId = nil }
                    ForEach(store.cameras) { camera in
                        Button(camera.name) { selectedCameraId = camera.id }
                    }
                }
            }
        }

        if status == .shotUndeveloped {
            sectionDivider
            DetailSection(title: "Storage") {
                InstrumentEditableRow(label: "Location", showsDivider: false) {
                    TextField("Fridge", text: $storageLocation)
                        .focused($focusedField, equals: .storage)
                }
            }
        }

        if status == .atLab {
            sectionDivider
            DetailSection(title: "Lab") {
                InstrumentEditableRow(label: "Lab name", showsDivider: false) {
                    TextField("Lab", text: $labName)
                        .focused($focusedField, equals: .lab)
                }
            }
        }
    }

    private func stockPickerRow(showsDivider: Bool) -> some View {
        Button {
            showingStockPicker = true
        } label: {
            InstrumentRow(label: "Stock", showsDivider: showsDivider) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if selectedStock != nil {
                        RollPlate(stock: selectedStock, size: 22)
                    }
                    Text(selectedStock?.name ?? "Choose film")
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(
                            selectedStock == nil ? AppTheme.textSecondary : AppTheme.textPrimary
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Image(systemName: "chevron.down")
                        .font(InstrumentFont.mono(9, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
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
    AddRollView()
        .environment(AppStore())
}
