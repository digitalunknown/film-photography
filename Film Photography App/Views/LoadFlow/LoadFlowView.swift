import SwiftUI
import UIKit

struct LoadFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step: LoadStep
    @State private var isRecognizing = false
    @State private var recognitionResult: LoadRecognitionResult?
    @State private var selectedCameraId: UUID?
    @State private var selectedStockId: UUID?
    @State private var selectedFridgeItemId: UUID?
    @State private var format: FilmFormat = .format35Full
    @State private var shootingISO: Int = 400
    @State private var exposuresText = "36"
    @State private var pushPull: Int = 0
    @State private var showingCameraPicker = false
    @State private var showingStockPicker = false
    @State private var showingPushPicker = false
    @State private var showingDeviceCamera = false
    @State private var capturedImage: UIImage?
    @State private var openedWithPendingCapture = false

    enum LoadStep {
        case source
        case capture
        case confirm
    }

    init(startWithCamera: Bool = false) {
        _step = State(initialValue: startWithCamera ? .capture : .source)
    }

    private var exposures: Int {
        max(Int(exposuresText.filter(\.isNumber)) ?? format.defaultExposures, 1)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .source:
                    sourceView
                case .capture:
                    captureView
                case .confirm:
                    confirmView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppType.body)
                }
            }
            .instrumentScreen()
            .fullScreenCover(isPresented: $showingDeviceCamera) {
                DeviceCameraPicker(
                    onCapture: { image in
                        capturedImage = image
                        showingDeviceCamera = false
                        processCapture()
                    },
                    onCancel: {
                        showingDeviceCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .onAppear {
                guard !openedWithPendingCapture else { return }
                guard store.loadFlowStartWithCamera || store.pendingLoadCapture != nil else { return }
                openedWithPendingCapture = true
                capturedImage = store.pendingLoadCapture
                store.pendingLoadCapture = nil
                store.loadFlowStartWithCamera = false
                processCapture()
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .source: "Load Roll"
        case .capture: "Load Roll"
        case .confirm: "Confirm"
        }
    }

    // MARK: - Source

    private var sourceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("How are you loading?")
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.bottom, AppTheme.Spacing.xl)

                if !store.availableFridgeItems.isEmpty {
                    TextAction(label: "From stock") {
                        step = .confirm
                        if let first = store.availableFridgeItems.first {
                            applyFridgeItem(first)
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.xl)
                }

                TextAction(label: "Scan camera + canister") {
                    step = .capture
                    presentDeviceCameraIfAvailable()
                }
                .padding(.bottom, AppTheme.Spacing.xl)

                TextAction(label: "Enter manually") {
                    startManualEntry()
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.vertical, AppTheme.Spacing.xl)
        }
    }

    // MARK: - Capture

    private var captureView: some View {
        VStack(spacing: 0) {
            ZStack {
                AppTheme.bg

                VStack(spacing: AppTheme.Spacing.xl) {
                    Spacer()

                    HStack(spacing: AppTheme.Spacing.lg) {
                        framingGuide(label: "Camera", icon: .camera)
                        framingGuide(label: "Film canister", icon: .film)
                    }

                    Spacer()

                    if isRecognizing {
                        ProgressView()
                            .tint(AppTheme.textPrimary)
                            .scaleEffect(1.2)
                        Text("Recognizing…")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingDeviceCamera = true
                            } else {
                                processCapture()
                            }
                        } label: {
                            Circle()
                                .strokeBorder(AppTheme.textPrimary, lineWidth: 4)
                                .background(Circle().fill(AppTheme.textPrimary.opacity(0.2)))
                                .frame(width: 72, height: 72)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Or add manually") {
                        startManualEntry()
                    }
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(AppTheme.bg)
    }

    private func framingGuide(label: String, icon: Lucide) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    AppTheme.textSecondary,
                    style: StrokeStyle(lineWidth: AppTheme.strokeWidth, dash: [8])
                )
                .frame(width: 140, height: 100)
                .overlay {
                    LucideIcon(icon)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            Text(label)
                .font(AppType.callout)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if capturedImage != nil {
                    capturedPhotoPreview
                        .padding(.bottom, AppTheme.Spacing.xl)
                    HairlineRule().padding(.bottom, AppTheme.Spacing.xl)
                }

                if !store.availableFridgeItems.isEmpty {
                    Picker("From stock", selection: $selectedFridgeItemId) {
                        Text("Not from stock").tag(nil as UUID?)
                        ForEach(store.availableFridgeItems) { item in
                            let name = store.stock(for: item.stockId)?.name ?? "Stock"
                            Text("\(name) · \(item.format.displayName) ×\(item.quantity)").tag(item.id as UUID?)
                        }
                    }
                    .font(AppType.body)
                    .onChange(of: selectedFridgeItemId) { _, newId in
                        if let newId, let item = store.fridgeItems.first(where: { $0.id == newId }) {
                            applyFridgeItem(item)
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.xl)
                }

                VStack(spacing: AppTheme.Spacing.lg) {
                    confirmField(
                        label: "Camera",
                        value: selectedCamera?.name ?? "Select",
                        badge: recognitionResult?.cameraConfidence.badgeLabel
                    ) { showingCameraPicker = true }

                    confirmField(
                        label: "Stock",
                        value: selectedStock?.name ?? "Select",
                        badge: recognitionResult?.stockConfidence.badgeLabel
                    ) { showingStockPicker = true }

                    Picker("Format", selection: $format) {
                        ForEach(FilmFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .font(AppType.body)
                    .onChange(of: format) { _, newFormat in
                        if selectedFridgeItemId == nil {
                            exposuresText = String(newFormat.defaultExposures)
                        }
                    }

                    confirmISOField

                    HStack {
                        Text("Expected frames")
                            .font(AppType.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        TextField(placeholder: "36", text: $exposuresText)
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 64)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.xl)

                TextAction(label: "Load roll") { confirmLoad() }
                    .opacity(selectedCameraId == nil || selectedStockId == nil ? 0.35 : 1)
                    .disabled(selectedCameraId == nil || selectedStockId == nil)
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.vertical, AppTheme.Spacing.xl)
        }
        .sheet(isPresented: $showingCameraPicker) {
            ChooseCameraSheet(
                onSelect: { camera in
                    selectedCameraId = camera.id
                    if let defaultFormat = camera.defaultFormat {
                        format = defaultFormat
                        exposuresText = String(defaultFormat.defaultExposures)
                    }
                    recognitionResult?.cameraConfidence = .manual
                    showingCameraPicker = false
                },
                onDismiss: { showingCameraPicker = false }
            )
        }
        .sheet(isPresented: $showingStockPicker) {
            pickerSheet(title: "Stock", items: store.stocks.map { ($0.id, $0.name) }) { id in
                selectedStockId = id
                if let stock = store.stock(for: id) {
                    shootingISO = stock.iso
                }
                recognitionResult?.stockConfidence = .manual
            }
        }
        .confirmationDialog("Shooting ISO/ASA", isPresented: $showingPushPicker) {
            Button("Box speed (\(selectedStock?.iso ?? shootingISO))") { pushPull = 0 }
            Button("Push +1") { pushPull = 1 }
            Button("Push +2") { pushPull = 2 }
            Button("Pull −1") { pushPull = -1 }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if selectedCameraId == nil, let camera = store.cameras.first {
                selectedCameraId = camera.id
                if let defaultFormat = camera.defaultFormat {
                    format = defaultFormat
                    exposuresText = String(defaultFormat.defaultExposures)
                }
            }
            if selectedStockId == nil {
                selectedStockId = store.stocks.first?.id
            }
        }
    }

    private var capturedPhotoPreview: some View {
        Group {
            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().strokeBorder(AppTheme.rule, lineWidth: AppTheme.strokeWidth)
                    Text("Load photo captured")
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(height: 140)
        .clipped()
    }

    private var confirmISOField: some View {
        Button { showingPushPicker = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Shooting ISO/ASA")
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(isoDisplayText)
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textPrimary)
                        if pushPull == 0 && recognitionResult?.isoFromDX == true {
                            Text("DX read")
                                .font(AppType.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                Spacer()
                Text("Tap to push")
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var isoDisplayText: String {
        if pushPull == 0 {
            return "ISO/ASA \(shootingISO)"
        }
        let sign = pushPull > 0 ? "+" : ""
        let effectiveISO = shootingISO * Int(pow(2.0, Double(abs(pushPull))))
        return "ISO/ASA \(effectiveISO) (pushed \(sign)\(pushPull))"
    }

    @ViewBuilder
    private func confirmField(
        label: String,
        value: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                HStack(spacing: 8) {
                    if let badge {
                        Text(badge)
                            .font(AppType.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Text(value)
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textPrimary)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func pickerSheet(
        title: String,
        items: [(UUID, String)],
        onSelect: @escaping (UUID) -> Void
    ) -> some View {
        NavigationStack {
            List(items, id: \.0) { id, name in
                Button(name) {
                    onSelect(id)
                    showingCameraPicker = false
                    showingStockPicker = false
                }
                .font(AppType.body)
            }
            .instrumentFormStyle()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCameraPicker = false
                        showingStockPicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Actions

    private var selectedCamera: Camera? {
        guard let id = selectedCameraId else { return nil }
        return store.camera(for: id)
    }

    private var selectedStock: FilmStock? {
        guard let id = selectedStockId else { return nil }
        return store.stock(for: id)
    }

    private func applyFridgeItem(_ item: FridgeItem) {
        selectedFridgeItemId = item.id
        selectedStockId = item.stockId
        format = item.format
        exposuresText = String(item.format.defaultExposures)
        if let stock = store.stock(for: item.stockId) {
            shootingISO = stock.iso
        }
        recognitionResult = LoadRecognitionResult(
            cameraId: selectedCameraId,
            cameraConfidence: .manual,
            stockId: item.stockId,
            stockConfidence: .manual,
            iso: shootingISO,
            isoFromDX: false,
            exposures: item.format.defaultExposures,
            isManual: true
        )
    }

    private func presentDeviceCameraIfAvailable() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        showingDeviceCamera = true
    }

    private func processCapture() {
        isRecognizing = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            let result = store.mockRecognize()
            recognitionResult = result
            selectedCameraId = result.cameraId
            selectedStockId = result.stockId
            shootingISO = result.iso ?? 400
            if let camera = store.camera(for: result.cameraId), let defaultFormat = camera.defaultFormat {
                format = defaultFormat
                exposuresText = String(defaultFormat.defaultExposures)
            } else {
                exposuresText = String(result.exposures ?? 36)
            }
            isRecognizing = false
            step = .confirm
        }
    }

    private func startManualEntry() {
        recognitionResult = LoadRecognitionResult(
            cameraId: nil,
            cameraConfidence: .manual,
            stockId: nil,
            stockConfidence: .manual,
            iso: nil,
            isoFromDX: false,
            exposures: nil,
            isManual: true
        )
        step = .confirm
    }

    private func confirmLoad() {
        guard let cameraId = selectedCameraId,
              let stockId = selectedStockId else { return }
        let fridgeItem = selectedFridgeItemId.flatMap { id in
            store.fridgeItems.first { $0.id == id }
        }
        store.loadRoll(
            cameraId: cameraId,
            stockId: stockId,
            format: format,
            iso: shootingISO,
            exposures: exposures,
            pushPull: pushPull,
            expiryDate: fridgeItem?.expiryDate,
            fromFridgeItemId: selectedFridgeItemId
        )
        dismiss()
    }
}

#Preview {
    LoadFlowView()
        .environment(AppStore())
}
