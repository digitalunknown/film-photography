import SwiftUI
import PhotosUI
import CoreLocation
import UIKit

struct ScanFrameView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let rollId: UUID
    let frame: StripFrame
    let stock: FilmStock?

    @State private var showingDeleteConfirm = false
    @State private var showingPhotoPicker = false
    @State private var uploadPickerItem: PhotosPickerItem?
    @State private var isoText = ""
    @State private var apertureIndex: Int?
    @State private var shutterIndex: Int?
    @State private var locationText = ""
    @State private var notesText = ""
    @State private var placeCoordinate: CLLocationCoordinate2D?
    @State private var captureDate: Date?
    @State private var lensId: UUID?
    @State private var lensName: String?
    @State private var loadedFields = FieldSnapshot()

    @State private var showingLocationSearch = false
    @State private var isLocating = false
    @State private var locationErrorMessage = ""
    @State private var showingLocationError = false
    @State private var showingDatePicker = false
    @State private var dateDraft = Date()
    @State private var gateImage: UIImage?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case iso, notes
    }

    /// Editable state captured at load time. Comparing against it keeps a plain visit
    /// from writing a marker, which would otherwise push the roll's exposure counter on.
    private struct FieldSnapshot: Equatable {
        var iso = ""
        var apertureIndex: Int?
        var shutterIndex: Int?
        var location = ""
        var notes = ""
        var captureDate: Date?
        var lensId: UUID?
        var lensName: String?
    }

    private var roll: Roll? {
        store.roll(for: rollId)
    }

    private var camera: Camera? {
        roll?.cameraId.flatMap { store.camera(for: $0) }
    }

    private var liveMarker: FrameMarker? {
        guard let roll else { return frame.marker }
        return StripFrameBuilder.frames(for: roll)
            .first(where: { $0.index == frame.index })?
            .marker ?? frame.marker
    }

    /// Read live from the store, including when it comes back empty. `frame` is the
    /// snapshot the sheet was opened with, so treating it as a fallback put a scan that
    /// had just been removed straight back on screen.
    private var scanFileName: String? {
        guard let roll else { return frame.scanFileName }
        return StripFrameBuilder.frames(for: roll)
            .first(where: { $0.index == frame.index })?
            .scanFileName
    }

    private var hasScan: Bool {
        scanFileName != nil
    }

    private var hasRemovablePhoto: Bool {
        guard let fileName = scanFileName else { return false }
        if roll?.framePhotoFileName(forFrame: frame.index) != nil {
            return true
        }
        return roll?.scanFileNames.contains(fileName) == true
    }

    private var defaultISO: Int {
        roll?.shootingISO ?? stock?.iso ?? 100
    }

    var body: some View {
        chrome
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $uploadPickerItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onAppear { loadFields() }
            .task(id: scanFileName) { await loadGateImage() }
            .onChange(of: frame.index) { _, _ in loadFields() }
            .onChange(of: camera?.id) { _, _ in loadFields() }
            .onChange(of: liveMarker?.location) { _, place in adoptStampedLocation(place) }
            .onChange(of: isoText) { _, _ in saveFieldsIfNeeded() }
            .task(id: dialSelection) { await saveWhenDialSettles() }
            .onDisappear { saveFieldsIfNeeded() }
            .onChange(of: notesText) { _, _ in saveFieldsIfNeeded() }
            .onChange(of: uploadPickerItem) { _, item in
                guard let item else { return }
                Task { await importScan(item) }
            }
    }

    private var chrome: some View {
        presentations
            .navigationTitle("Frame \(frame.index)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
    }

    private var presentations: some View {
        scrollContent
            .sheet(isPresented: $showingLocationSearch) {
                LocationSearchSheet(onSelect: { apply($0) })
            }
            .sheet(isPresented: $showingDatePicker) { datePickerSheet }
            .alert("Location unavailable", isPresented: $showingLocationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(locationErrorMessage)
            }
            .alert("Remove scan?", isPresented: $showingDeleteConfirm) {
                Button("Remove", role: .destructive) { deletePhoto() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the photo from frame \(frame.index).")
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                scanBlock
                    .padding(.bottom, AppTheme.tableGap)
                HairlineRule()
                exifCard
                HairlineRule()
                metadataBlock
                HairlineRule()
                notesBlock
            }
            .instrumentDetailContent()
        }
        .instrumentDetailScroll()
        .instrumentDetailChrome()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { closeButton }
        ToolbarItemGroup(placement: .keyboard) { keyboardDoneButton }
    }

    private var exportedScan: ExportedScan? {
        guard let roll, let fileName = scanFileName else { return nil }
        return ExportedScan(
            rollId: rollId,
            fileName: fileName,
            exportName: ScanExport.exportName(rollLabel: stock?.name ?? "scan", frameIndex: frame.index),
            metadata: exportMetadata(for: roll)
        )
    }

    /// Read off the editor rather than the saved marker. The dials write on a delay, so a
    /// scan exported straight after a turn would otherwise carry the previous reading
    /// instead of the one the photographer is looking at.
    private func exportMetadata(for roll: Roll) -> ScanMetadata {
        var metadata = ScanMetadata(
            roll: roll,
            frameIndex: frame.index,
            marker: liveMarker,
            camera: camera,
            stock: stock
        )
        metadata.captureDate = captureDate
        metadata.aperture = apertureIndex.map { ExposureScale.aperture.notches[$0].value }
        metadata.shutterSpeed = shutterIndex.map { ExposureScale.shutter.notches[$0].value }
        metadata.place = locationText
        metadata.notes = notesText
        if let iso = Int(isoText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            metadata.iso = iso
        }
        if let placeCoordinate {
            metadata.latitude = placeCoordinate.latitude
            metadata.longitude = placeCoordinate.longitude
        }
        var draft = liveMarker ?? FrameMarker(frameIndex: frame.index)
        draft.lensId = lensId
        draft.lensName = lensName
        metadata.lens = ScanMetadata.lensModel(marker: draft, camera: camera)
        metadata.focalLength = ScanMetadata.focalLength(marker: draft, camera: camera)
        return metadata
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            LucideIcon(.x)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .accessibilityLabel("Close")
    }

    private var keyboardDoneButton: some View {
        HStack {
            Spacer()
            InstrumentKeyboardDoneButton {
                focusedField = nil
            }
        }
    }

    // MARK: - Scan

    /// Frame gate: full width inside the 16pt page margins, 3:2 like a 35mm negative.
    private static let gateAspect: CGFloat = 3.0 / 2.0
    private static let gateCorner: CGFloat = AppTheme.Spacing.sm
    /// Long edge of the decoded scan — a full-width gate on the largest phone at @3x.
    private static let gatePixelSize: CGFloat = 1400

    /// Scans only exist once the roll is off the camera, so while it is still being shot
    /// the gate is just a placeholder with no way to attach anything to it.
    private var canAttachScan: Bool {
        roll?.status.countsAsShot == true
    }

    private var scanBlock: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            gateControl
            if canAttachScan {
                HStack(spacing: AppTheme.Spacing.md) {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        PillButtonLabel(
                            title: hasScan ? "Replace" : "Add scan",
                            icon: .imageUp
                        )
                    }
                    .buttonStyle(.plain)

                    saveButton
                }
            }
        }
    }

    /// Sends this one frame's scan out with its own record written in. Nothing to save
    /// until a scan is attached, so it appears alongside Replace rather than on its own.
    @ViewBuilder
    private var saveButton: some View {
        if let export = exportedScan {
            ExportScansButton(
                scans: [export],
                label: "Save scan",
                style: .pill(title: "Save")
            )
        }
    }

    /// An empty gate goes straight to the picker; a filled one offers replace/remove.
    @ViewBuilder
    private var gateControl: some View {
        if !canAttachScan {
            frameGate
        } else if !hasScan {
            Button {
                showingPhotoPicker = true
            } label: {
                frameGate
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add scan")
        } else {
            Menu {
                Button("Replace scan", lucide: .imageUp) {
                    showingPhotoPicker = true
                }
                .font(AppType.body)
                if hasRemovablePhoto {
                    Button(destructive: "Remove scan", lucide: .trash) {
                        showingDeleteConfirm = true
                    }
                    .font(AppType.body)
                }
            } label: {
                frameGate
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan options")
        }
    }

    private var frameGate: some View {
        Rectangle()
            .fill(AppTheme.bg)
            .aspectRatio(Self.gateAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { gateContent }
            .clipShape(RoundedRectangle(cornerRadius: Self.gateCorner))
            .instrumentStroke(RoundedRectangle(cornerRadius: Self.gateCorner))
            .overlay { cornerBrackets }
            .contentShape(Rectangle())
    }

    /// Scans fill the gate so the corner brackets frame the image itself.
    @ViewBuilder
    private var gateContent: some View {
        if let gateImage {
            Image(uiImage: gateImage)
                .resizable()
                .scaledToFill()
        } else {
            LucideIcon(.scan)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    /// Decoding happens off the main thread and only when the file changes, so typing in
    /// the fields below never re-reads the scan.
    private func loadGateImage() async {
        guard let fileName = scanFileName else {
            gateImage = nil
            return
        }
        let rollId = rollId
        let maxSize = Self.gatePixelSize
        gateImage = await Task.detached(priority: .userInitiated) {
            ScanStorage.thumbnail(
                for: rollId,
                fileName: fileName,
                maxSize: maxSize,
                laidOnSide: true
            )
        }.value
    }

    private var cornerBrackets: some View {
        FrameCornerStroke(
            length: FilmStripFrameMetrics.bracketArm,
            lineWidth: FilmStripFrameMetrics.bracketWidth,
            cornerRadius: Self.gateCorner
        )
        .stroke(
            AppTheme.textPrimary,
            style: StrokeStyle(
                lineWidth: FilmStripFrameMetrics.bracketWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    // MARK: - EXIF

    private var exifCard: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ExposureDial(unit: "A", scale: .aperture, selection: $apertureIndex)
            ExposureDial(unit: "S/S", scale: .shutter, selection: $shutterIndex)
        }
    }

    // MARK: - Metadata

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            locationRow
            HairlineRule()
            dateRow
            HairlineRule()
            filmRow
            HairlineRule()
            isoRow
            HairlineRule()
            cameraRow
            if showsFocalLengthRow {
                HairlineRule()
                focalLengthRow
            }
        }
    }

    /// Left behind when shutter and aperture became dials — ISO is typed far less often,
    /// and it already defaults to the roll's rated speed.
    private var isoRow: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Text("ISO/ASA")
                .font(AppType.body)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(placeholder: "\(defaultISO)", text: $isoText)
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .fixedSize()
                .focused($focusedField, equals: .iso)
        }
    }

    private var locationRow: some View {
        let hasLocation = !locationText.isEmpty
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            StackedFieldRow(
                label: "Location",
                accessory: hasLocation ? .mapPinMinus : .mapPinPlus,
                accessoryLabel: hasLocation ? "Clear location" : "Use current location",
                accessoryAction: hasLocation ? clearLocation : useCurrentLocation
            ) {
                fieldValueButton(
                    text: locationDisplay,
                    isPlaceholder: !hasLocation
                ) {
                    showingLocationSearch = true
                }
            }

            if let coordinate = mapCoordinate {
                FrameLocationMap(coordinate: coordinate)
            }
        }
    }

    /// A named place with no fix still shows the field; the map only appears once we
    /// have a real coordinate (zero is treated as unset).
    private var mapCoordinate: CLLocationCoordinate2D? {
        if let placeCoordinate { return placeCoordinate }
        guard let marker = liveMarker, marker.latitude != 0 || marker.longitude != 0 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
    }

    private var locationDisplay: String {
        if isLocating { return "Locating…" }
        return locationText.isEmpty ? "Add a location" : locationText
    }

    private var dateRow: some View {
        let hasDate = captureDate != nil
        return StackedFieldRow(
            label: "Date",
            accessory: hasDate ? .calendarMinus : .calendarPlus,
            accessoryLabel: hasDate ? "Clear date" : "Use the current date and time",
            accessoryAction: hasDate ? clearDate : stampNow
        ) {
            fieldValueButton(
                text: captureDate.map { Self.dateLabel($0) } ?? "Add a date",
                isPlaceholder: !hasDate
            ) {
                dateDraft = captureDate ?? Date()
                showingDatePicker = true
            }
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    private var filmRow: some View {
        StackedFieldRow(label: "Film") {
            if let stock {
                NavigationLink {
                    StockDetailView(stockId: stock.id)
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(stock.name)
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                        LucideIcon(.chevronRight)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Not set")
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    /// Camera is roll-level data; editing it here corrects the whole roll.
    private var cameraRow: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Text("Camera")
                .font(AppType.body)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("None") { store.setRollCamera(rollId, to: nil) }
                ForEach(store.cameras) { option in
                    Button(option.name) { store.setRollCamera(rollId, to: option.id) }
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(camera?.name ?? "Choose camera")
                        .font(AppType.body)
                        .foregroundStyle(camera == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Camera")
        }
    }

    /// Focal length sits under the body. One lens is a label; several become a dropdown.
    private var showsFocalLengthRow: Bool {
        guard let camera, !camera.lenses.isEmpty else { return false }
        return true
    }

    private var selectedLens: CameraLens? {
        if let lensId, let lens = camera?.lenses.first(where: { $0.id == lensId }) {
            return lens
        }
        return camera?.primaryLens
    }

    private var focalLengthLabel: String {
        if let selectedLens {
            return selectedLens.focalLengthDisplay
        }
        if let lensName, !lensName.isEmpty { return lensName }
        return "Not set"
    }

    @ViewBuilder
    private var focalLengthRow: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            Text("Focal length")
                .font(AppType.body)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if (camera?.lenses.count ?? 0) > 1 {
                Menu {
                    ForEach(camera?.lenses ?? []) { lens in
                        Button(lens.focalLengthDisplay) { setLens(lens) }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(focalLengthLabel)
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.trailing)
                        LucideIcon(.chevronsUpDown)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focal length")
            } else {
                Text(focalLengthLabel)
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func setLens(_ lens: CameraLens?) {
        lensId = lens?.id
        lensName = lens?.exifModel
        saveFieldsIfNeeded()
    }

    // MARK: - Notes

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SectionLabel(title: "Notes", style: .detail)
            TextField(placeholder: "Add notes", text: $notesText, axis: .vertical)
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2...)
                .focused($focusedField, equals: .notes)
        }
    }

    private func fieldValueButton(
        text: String,
        isPlaceholder: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .font(AppType.body)
                .foregroundStyle(isPlaceholder ? AppTheme.textSecondary : AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.lg) {
                DatePicker(
                    "Date",
                    selection: $dateDraft,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(AppTheme.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.top, AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .instrumentScreen()
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingDatePicker = false }
                        .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        setDate(dateDraft)
                        showingDatePicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .instrumentSheetChrome()
    }

    // MARK: - Location & date actions

    private func useCurrentLocation() {
        guard !isLocating else { return }
        isLocating = true
        Task {
            do {
                let place = try await CurrentLocation.resolve()
                isLocating = false
                apply(place)
            } catch {
                isLocating = false
                locationErrorMessage = message(for: error)
                showingLocationError = true
            }
        }
    }

    private func message(for error: Error) -> String {
        if case CurrentLocationError.denied = error {
            return "Location access is off. Turn it on in Settings to tag frames with where you shot them."
        }
        return "Couldn't work out where you are. Try again in a moment."
    }

    private func apply(_ place: ResolvedPlace) {
        locationText = place.name
        placeCoordinate = place.coordinate
        saveFields()
    }

    private func clearLocation() {
        locationText = ""
        placeCoordinate = nil
        saveFields()
    }

    private func stampNow() {
        setDate(Date())
    }

    private func clearDate() {
        setDate(nil)
    }

    private func setDate(_ date: Date?) {
        captureDate = date
        saveFields()
    }

    private func deletePhoto() {
        if roll?.framePhotoFileName(forFrame: frame.index) != nil {
            store.removeFramePhoto(from: rollId, frameIndex: frame.index)
        } else if let fileName = scanFileName {
            store.removeScan(from: rollId, fileName: fileName)
        }
    }

    // MARK: - Persistence

    private var currentFields: FieldSnapshot {
        FieldSnapshot(
            iso: isoText,
            apertureIndex: apertureIndex,
            shutterIndex: shutterIndex,
            location: locationText,
            notes: notesText,
            captureDate: captureDate,
            lensId: lensId,
            lensName: lensName
        )
    }

    /// The shutter's location lookup runs in the background, so a fix can land while this
    /// sheet is already open on the frame it belongs to. Take it on as though it had been
    /// there at load time: without this the next save would write the still-empty field
    /// back over it and the stamp would disappear.
    private func adoptStampedLocation(_ place: String?) {
        guard let place, locationText.isEmpty, loadedFields.location.isEmpty else { return }
        locationText = place
        loadedFields.location = place
        if let marker = liveMarker, marker.latitude != 0 || marker.longitude != 0 {
            placeCoordinate = CLLocationCoordinate2D(
                latitude: marker.latitude,
                longitude: marker.longitude
            )
        }
    }

    private func loadFields() {
        let marker = liveMarker
        isoText = marker?.iso.map(String.init)
            ?? (roll?.shootingISO ?? stock?.iso).map(String.init)
            ?? ""
        apertureIndex = marker?.aperture.map { ExposureScale.aperture.nearestIndex(to: $0) }
        shutterIndex = marker?.shutterSpeed.map { ExposureScale.shutter.nearestIndex(to: $0) }
        locationText = marker?.location ?? ""
        notesText = marker?.notes ?? ""
        captureDate = marker?.captureDate
        lensId = marker?.lensId
        lensName = marker?.lensName
        if let marker, marker.latitude != 0 || marker.longitude != 0 {
            placeCoordinate = CLLocationCoordinate2D(
                latitude: marker.latitude,
                longitude: marker.longitude
            )
        } else {
            placeCoordinate = nil
        }
        loadedFields = currentFields
    }

    private var dialSelection: [Int?] {
        [apertureIndex, shutterIndex]
    }

    /// A dial reports every notch it passes. Waiting for the turn to settle keeps one
    /// sweep from writing the roll to disk a dozen times over.
    private func saveWhenDialSettles() async {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        saveFieldsIfNeeded()
    }

    private func saveFieldsIfNeeded() {
        guard currentFields != loadedFields else { return }
        saveFields()
    }

    private func saveFields() {
        loadedFields = currentFields

        var marker = liveMarker ?? FrameMarker(frameIndex: frame.index)
        marker.frameIndex = frame.index
        marker.iso = Int(isoText.trimmingCharacters(in: .whitespacesAndNewlines))
        marker.aperture = apertureIndex.map { ExposureScale.aperture.notches[$0].value }
        marker.shutterSpeed = shutterIndex.map { ExposureScale.shutter.notches[$0].value }
        marker.location = locationText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        marker.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        marker.captureDate = captureDate
        marker.lensId = lensId
        marker.lensName = lensName

        if let placeCoordinate {
            marker.latitude = placeCoordinate.latitude
            marker.longitude = placeCoordinate.longitude
        } else if marker.location == nil {
            marker.latitude = 0
            marker.longitude = 0
        }

        let hasData = marker.iso != nil
            || marker.aperture != nil
            || marker.shutterSpeed != nil
            || marker.location != nil
            || marker.notes != nil
            || marker.captureDate != nil
            || marker.lensId != nil
            || marker.lensName != nil
            || liveMarker != nil

        guard hasData else { return }
        store.upsertFrameMarker(rollId, marker: marker)
    }

    private func importScan(_ item: PhotosPickerItem) async {
        defer {
            Task { @MainActor in
                uploadPickerItem = nil
            }
        }
        guard let data = await loadImageData(from: item),
              let jpeg = ScanStorage.normalizedJPEG(from: data)
        else { return }

        await MainActor.run {
            store.setFramePhoto(on: rollId, frameIndex: frame.index, imageData: jpeg)
        }
    }

    private func loadImageData(from item: PhotosPickerItem) async -> Data? {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        if let transfer = try? await item.loadTransferable(type: ScanFrameImageTransfer.self) {
            return transfer.data
        }
        return nil
    }
}

private struct ScanFrameImageTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { ScanFrameImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .png) { ScanFrameImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .heic) { ScanFrameImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .image) { ScanFrameImageTransfer(data: $0) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
