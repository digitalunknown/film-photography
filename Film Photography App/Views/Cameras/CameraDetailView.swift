import PhotosUI
import SwiftUI
import UIKit

struct CameraDetailView: View {
    @Environment(AppStore.self) private var store
    let cameraId: UUID

    @State private var photoItem: PhotosPickerItem?

    private let cameraTypes = ["Rangefinder", "SLR", "Point & shoot", "TLR", "Large format", "Instant"]

    private var camera: Camera? {
        store.camera(for: cameraId)
    }

    private var cameraRollHistory: [Roll] {
        store.rollsForCamera(cameraId)
            .sorted { ($0.loadedDate ?? .distantPast) > ($1.loadedDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if let camera {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heroSection(camera)
                        photoSection(camera)
                        bodySection(camera)
                        collectionSection(camera)
                        quirksSection(camera)
                        repairSection(camera)
                        loadedSection(camera)
                        rollHistorySection
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
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
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(from: newItem) }
        }
    }

    @ViewBuilder
    private func heroSection(_ camera: Camera) -> some View {
        if let roll = store.loadedRoll(for: camera.id) {
            HeroMetric(
                label: "Frame",
                sublabel: store.stock(for: roll.stockId)?.name,
                value: String(format: "%02d", roll.frameCount)
            )
            .padding(.top, 8)
            .padding(.bottom, 28)
            UnderlineMeter(
                label: "Exposures",
                value: "\(roll.frameCount)/\(roll.totalExposures)",
                progress: Double(roll.frameCount) / Double(max(roll.totalExposures, 1))
            )
            .padding(.bottom, 28)
            HairlineRule().padding(.bottom, 28)
        } else {
            Text(camera.name)
                .font(InstrumentFont.display(28, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Sections

    private func photoSection(_ camera: Camera) -> some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                CameraPhotoPlate(photoData: camera.photoData, size: 120)
            }
            .buttonStyle(.plain)

            Text("Tap to add photo")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)

            if camera.photoData != nil {
                TextAction(label: "Remove photo →") {
                    update(camera) { $0.photoData = nil }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
    }

    private func bodySection(_ camera: Camera) -> some View {
        DetailSection(title: "Body") {
            EditableField(label: "Name") {
                TextField("Camera name", text: binding(camera, \.name))
            }
            EditableField(label: "Lens") {
                TextField("38mm f/1.8", text: binding(camera, \.lensSubtitle))
            }
            EditableField(label: "Type") {
                Picker("Type", selection: binding(camera, \.cameraType)) {
                    ForEach(cameraTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            EditableField(label: "Default format") {
                Picker("Format", selection: defaultFormatBinding(camera)) {
                    Text("None").tag(nil as FilmFormat?)
                    ForEach(FilmFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt as FilmFormat?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private func collectionSection(_ camera: Camera) -> some View {
        DetailSection(title: "Collection") {
            EditableField(label: "Serial number") {
                TextField("Optional", text: optionalStringBinding(camera, \.serialNumber))
            }
            EditableField(label: "Purchase date") {
                DatePicker(
                    "Date",
                    selection: purchaseDateBinding(camera),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
            EditableField(label: "Purchase price") {
                TextField("Optional", text: priceBinding(camera))
                    .keyboardType(.decimalPad)
            }
        }
    }

    private func quirksSection(_ camera: Camera) -> some View {
        DetailSection(title: "Quirks") {
            if camera.quirks.isEmpty {
                Text("No quirks recorded")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(quirkIndices(camera), id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("△")
                            .font(InstrumentFont.mono(11))
                            .foregroundStyle(AppTheme.textSecondary)
                        TextField("Quirk", text: quirkBinding(camera, index: index), axis: .vertical)
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2...4)
                        Button {
                            removeQuirk(at: index, from: camera)
                        } label: {
                            Text("⨯")
                                .font(InstrumentFont.mono(12))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextAction(label: "Add quirk →") { addQuirk(to: camera) }
                .padding(.top, 4)
        }
    }

    private func repairSection(_ camera: Camera) -> some View {
        DetailSection(title: "Repairs") {
            if camera.repairHistory.isEmpty {
                Text("No repairs recorded")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(repairIndices(camera), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Description", text: repairDescriptionBinding(camera, index: index), axis: .vertical)
                            .lineLimit(2...3)
                        DatePicker(
                            "Date",
                            selection: repairDateBinding(camera, index: index),
                            displayedComponents: .date
                        )
                        .font(.caption)
                        TextAction(label: "Remove →") {
                            removeRepair(at: index, from: camera)
                        }
                    }
                    .padding(.vertical, 4)

                    if index < camera.repairHistory.count - 1 {
                        HairlineRule().padding(.vertical, 8)
                    }
                }
            }

            TextAction(label: "Add repair →") { addRepair(to: camera) }
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func loadedSection(_ camera: Camera) -> some View {
        if let roll = store.loadedRoll(for: camera.id),
           let stock = store.stock(for: roll.stockId) {
            DetailSection(title: "Loaded") {
                LoadedRollRow(stock: stock, roll: roll)
            }
        }
    }

    private var rollHistorySection: some View {
        DetailSection(title: "History") {
            RollHistoryList(rolls: cameraRollHistory)
        }
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

    private func purchaseDateBinding(_ camera: Camera) -> Binding<Date> {
        Binding(
            get: { store.camera(for: cameraId)?.purchaseDate ?? Date() },
            set: { newValue in
                update(camera) { $0.purchaseDate = newValue }
            }
        )
    }

    private func defaultFormatBinding(_ camera: Camera) -> Binding<FilmFormat?> {
        Binding(
            get: { store.camera(for: cameraId)?.defaultFormat },
            set: { newValue in
                update(camera) { $0.defaultFormat = newValue }
            }
        )
    }

    private func priceBinding(_ camera: Camera) -> Binding<String> {
        Binding(
            get: {
                guard let price = store.camera(for: cameraId)?.purchasePrice else { return "" }
                return String(format: "%.0f", price)
            },
            set: { newValue in
                update(camera) { $0.purchasePrice = Double(newValue) }
            }
        )
    }

    private func quirkIndices(_ camera: Camera) -> Range<Int> {
        0..<(store.camera(for: cameraId)?.quirks.count ?? camera.quirks.count)
    }

    private func quirkBinding(_ camera: Camera, index: Int) -> Binding<String> {
        Binding(
            get: { store.camera(for: cameraId)?.quirks[index].note ?? "" },
            set: { newValue in
                update(camera) { cam in
                    guard cam.quirks.indices.contains(index) else { return }
                    cam.quirks[index].note = newValue
                }
            }
        )
    }

    private func repairIndices(_ camera: Camera) -> Range<Int> {
        0..<(store.camera(for: cameraId)?.repairHistory.count ?? camera.repairHistory.count)
    }

    private func repairDescriptionBinding(_ camera: Camera, index: Int) -> Binding<String> {
        Binding(
            get: { store.camera(for: cameraId)?.repairHistory[index].description ?? "" },
            set: { newValue in
                update(camera) { cam in
                    guard cam.repairHistory.indices.contains(index) else { return }
                    cam.repairHistory[index].description = newValue
                }
            }
        )
    }

    private func repairDateBinding(_ camera: Camera, index: Int) -> Binding<Date> {
        Binding(
            get: { store.camera(for: cameraId)?.repairHistory[index].date ?? Date() },
            set: { newValue in
                update(camera) { cam in
                    guard cam.repairHistory.indices.contains(index) else { return }
                    cam.repairHistory[index].date = newValue
                }
            }
        )
    }

    // MARK: - Mutations

    private func update(_ camera: Camera, _ transform: (inout Camera) -> Void) {
        guard var current = store.camera(for: cameraId) else { return }
        transform(&current)
        store.updateCamera(current)
    }

    private func addQuirk(to camera: Camera) {
        update(camera) { $0.quirks.append(CameraQuirk(id: UUID(), note: "")) }
    }

    private func removeQuirk(at index: Int, from camera: Camera) {
        update(camera) { cam in
            guard cam.quirks.indices.contains(index) else { return }
            cam.quirks.remove(at: index)
        }
    }

    private func addRepair(to camera: Camera) {
        update(camera) {
            $0.repairHistory.append(RepairRecord(id: UUID(), date: Date(), description: ""))
        }
    }

    private func removeRepair(at index: Int, from camera: Camera) {
        update(camera) { cam in
            guard cam.repairHistory.indices.contains(index) else { return }
            cam.repairHistory.remove(at: index)
        }
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

private struct LoadedRollRow: View {
    let stock: FilmStock
    let roll: Roll

    var body: some View {
        VStack(spacing: 8) {
            DataRow(label: "Stock", value: stock.name)
            DataRow(label: "Frame", value: String(format: "%02d/%02d", roll.frameCount, roll.totalExposures))
            DataRow(label: "Pins", value: "\(roll.pinCount)")
        }
    }
}

private struct RollHistoryList: View {
    @Environment(AppStore.self) private var store
    let rolls: [Roll]

    var body: some View {
        if rolls.isEmpty {
            Text("No rolls yet")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rolls.enumerated()), id: \.element.id) { index, roll in
                    if let stock = store.stock(for: roll.stockId) {
                        RollTimelineRow(roll: roll, stockName: stock.name)

                        if index < rolls.count - 1 {
                            HairlineRule()
                                .padding(.vertical, 16)
                        }
                    }
                }
            }
        }
    }
}

private struct RollTimelineRow: View {
    let roll: Roll
    let stockName: String

    private var events: [(label: String, date: Date)] {
        var items: [(String, Date)] = []
        if let date = roll.loadedDate { items.append(("Loaded", date)) }
        if let date = roll.finishedDate { items.append(("Finished", date)) }
        if let date = roll.dropOffDate { items.append(("At lab", date)) }
        if let date = roll.developedDate { items.append(("Developed", date)) }
        if let date = roll.scannedDate { items.append(("Scanned", date)) }
        return items.sorted { $0.1 < $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(stockName) · \(roll.shortId)")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)

            if events.isEmpty {
                Text(roll.status.displayName)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(index == events.count - 1 ? AppTheme.textPrimary : AppTheme.textSecondary)
                                    .frame(width: 5, height: 5)
                                if index < events.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.rule)
                                        .frame(width: 0.5)
                                        .frame(height: 28)
                                }
                            }
                            .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.label)
                                    .font(InstrumentFont.mono(11))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(DateFormatters.medium.string(from: event.date))
                                    .font(InstrumentFont.mono(12))
                                    .foregroundStyle(AppTheme.textPrimary)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CameraDetailView(cameraId: AppStore().cameras[0].id)
    }
    .environment(AppStore())
}
