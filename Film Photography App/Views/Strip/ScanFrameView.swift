import SwiftUI
import PhotosUI
import UIKit

struct ScanFrameView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let rollId: UUID
    let frame: StripFrame
    let stock: FilmStock?

    @State private var showingDeleteConfirm = false
    @State private var uploadPickerItem: PhotosPickerItem?
    @State private var isoText = ""
    @State private var apertureText = ""
    @State private var shutterText = ""
    @State private var locationText = ""
    @State private var isLoadingFields = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case iso, aperture, shutter, location
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

    private var scanFileName: String? {
        if let roll,
           let name = StripFrameBuilder.frames(for: roll)
            .first(where: { $0.index == frame.index })?
            .scanFileName {
            return name
        }
        return frame.scanFileName
    }

    private var image: UIImage? {
        guard let fileName = scanFileName else { return nil }
        return ScanStorage.thumbnail(for: rollId, fileName: fileName, maxSize: 4096)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photoBlock
                metadataSection
                if hasRemovablePhoto {
                    deleteButton
                }
            }
            .instrumentDetailContent()
        }
        .instrumentDetailScroll()
        .instrumentDetailChrome()
        .navigationTitle("Frame \(frame.index)")
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                InstrumentKeyboardDoneButton {
                    focusedField = nil
                }
            }
        }
        .alert("Delete photo?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if roll?.framePhotoFileName(forFrame: frame.index) != nil {
                    store.removeFramePhoto(from: rollId, frameIndex: frame.index)
                } else if let fileName = scanFileName {
                    store.removeScan(from: rollId, fileName: fileName)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the photo from frame \(frame.index).")
        }
        .onAppear { loadFields() }
        .onChange(of: frame.index) { _, _ in loadFields() }
        .onChange(of: isoText) { _, _ in saveFieldsIfNeeded() }
        .onChange(of: apertureText) { _, _ in saveFieldsIfNeeded() }
        .onChange(of: shutterText) { _, _ in saveFieldsIfNeeded() }
        .onChange(of: locationText) { _, _ in saveFieldsIfNeeded() }
        .onChange(of: uploadPickerItem) { _, item in
            guard let item else { return }
            Task { await importScan(item) }
        }
    }

    private var photoBlock: some View {
        DetailHeroBlock {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    PhotosPicker(
                        selection: $uploadPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        emptyPhotoPlaceholder
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipped()
        }
    }

    private var emptyPhotoPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(FilmStripView.filmBase)
            Rectangle()
                .strokeBorder(AppTheme.rule, lineWidth: 1)
            VStack(spacing: AppTheme.Spacing.md) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(AppTheme.textTertiary, lineWidth: 1)
                    .frame(width: 56, height: 56)
                Text("Upload scan")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var metadataSection: some View {
        DetailSection(title: "Technical Specifications") {
            VStack(spacing: 0) {
                DataRow(label: "Frame", value: "\(frame.index)", showsDivider: false)

                if let stock {
                    DataRow(label: "Stock", value: stock.name)
                }

                DataRow(
                    label: "Camera",
                    value: camera?.name ?? "Not Set",
                    valueBright: camera != nil
                )

                if let lens = camera?.listSubtitle {
                    DataRow(label: "Lens", value: lens)
                }

                if let roll {
                    DataRow(label: "Format", value: roll.format.displayName)
                    DataRow(
                        label: "Push / pull",
                        value: roll.pushPullDisplayValue,
                        valueBright: roll.pushPull != nil && roll.pushPull != 0
                    )
                }

                InstrumentEditableRow(label: "ISO") {
                    TextField("\(defaultISO)", text: $isoText)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textPrimary)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .iso)
                }

                InstrumentEditableRow(label: "Aperture") {
                    TextField("f/8", text: $apertureText)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textPrimary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .aperture)
                }

                InstrumentEditableRow(label: "Shutter Speed") {
                    TextField("1/125", text: $shutterText)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textPrimary)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .shutter)
                }

                InstrumentEditableRow(label: "Location") {
                    TextField("Not Set", text: $locationText)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textPrimary)
                        .focused($focusedField, equals: .location)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            showingDeleteConfirm = true
        } label: {
            Text("Delete")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay {
                    Rectangle()
                        .strokeBorder(AppTheme.rule, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .padding(.top, AppTheme.Spacing.md)
    }

    private func loadFields() {
        isLoadingFields = true
        defer { isLoadingFields = false }

        let marker = liveMarker
        isoText = marker?.iso.map(String.init)
            ?? (roll?.shootingISO ?? stock?.iso).map(String.init)
            ?? ""
        apertureText = marker?.aperture.map { formatAperture($0) } ?? ""
        shutterText = marker?.shutterSpeed.map(ExposureFormat.shutter) ?? ""
        locationText = marker?.location ?? ""
    }

    private func saveFieldsIfNeeded() {
        guard !isLoadingFields else { return }
        saveFields()
    }

    private func saveFields() {
        var marker = liveMarker ?? FrameMarker(frameIndex: frame.index)
        marker.frameIndex = frame.index
        marker.iso = Int(isoText.trimmingCharacters(in: .whitespacesAndNewlines))
        marker.aperture = parseAperture(apertureText)
        marker.shutterSpeed = ExposureFormat.parseShutter(shutterText)
        marker.location = locationText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Seed ISO from the roll when the field is left blank so rows stay populated.
        if marker.iso == nil {
            marker.iso = roll?.shootingISO ?? stock?.iso
        }

        let hasData = marker.iso != nil
            || marker.aperture != nil
            || marker.shutterSpeed != nil
            || marker.location != nil
            || liveMarker != nil

        guard hasData else { return }
        store.upsertFrameMarker(rollId, marker: marker)
    }

    private func formatAperture(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }

    private func parseAperture(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "f/", with: "")
            .replacingOccurrences(of: "F/", with: "")
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
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
