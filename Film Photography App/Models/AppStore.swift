import SwiftUI
import UIKit

struct LoadRecognitionResult {
    var cameraId: UUID?
    var cameraConfidence: RecognitionConfidence
    var stockId: UUID?
    var stockConfidence: RecognitionConfidence
    var iso: Int?
    var isoFromDX: Bool
    var exposures: Int?
    var isManual: Bool = false
}

enum RecognitionConfidence {
    case matched
    case dxRead
    case low
    case manual

    var badgeLabel: String? {
        switch self {
        case .matched: "Matched"
        case .dxRead: "DX read"
        case .low, .manual: nil
        }
    }
}

struct PendingRollDeletion {
    let roll: Roll
    let deletedAt: Date
}

@Observable
final class AppStore {
    var cameras: [Camera]
    var rolls: [Roll]
    var stocks: [FilmStock]
    var customStocks: [FilmStock]
    var fridgeItems: [FridgeItem]
    var devRecipePresets: [DevRecipePreset]
    var pendingDeletion: PendingRollDeletion?
    var showingAddCamera = false
    var showingAddRoll = false
    var showingLoadFlow = false
    var showingArchive = false
    /// Opens Load Flow past the source chooser (camera already taken or about to open).
    var loadFlowStartWithCamera = false
    var pendingLoadCapture: UIImage?

    private var deletionTask: Task<Void, Never>?

    init() {
        let catalog = StockCatalog.loadStocks()

        if let saved = DataPersistence.load() {
            cameras = saved.cameras
            rolls = saved.rolls.map(Roll.migrate)
            fridgeItems = saved.fridgeItems
            devRecipePresets = saved.devRecipePresets
            let loadedCustom = saved.customStocks
            customStocks = loadedCustom
            stocks = catalog + loadedCustom
            pendingDeletion = nil
            deletionTask = nil
            if saved.version < PersistedAppData.currentVersion {
                persist()
            }
        } else {
            cameras = []
            rolls = []
            fridgeItems = []
            devRecipePresets = []
            customStocks = []
            stocks = catalog
            pendingDeletion = nil
            deletionTask = nil
            persist()
        }
    }

    private func persist() {
        DataPersistence.save(
            cameras: cameras,
            rolls: rolls.map { var r = $0; r.status = $0.status.normalized; return r },
            fridgeItems: fridgeItems,
            devRecipePresets: devRecipePresets,
            customStocks: customStocks
        )
    }

    /// Creates a user-entered stock and keeps it across launches.
    @discardableResult
    func addCustomStock(name: String, iso: Int) -> FilmStock {
        let stock = FilmStock.custom(name: name, iso: iso)
        customStocks.append(stock)
        stocks.append(stock)
        persist()
        return stock
    }

    // MARK: - Lookups

    func camera(for id: UUID?) -> Camera? {
        guard let id else { return nil }
        return cameras.first { $0.id == id }
    }

    func stock(for id: UUID) -> FilmStock? {
        stocks.first { $0.id == id }
    }

    func roll(for id: UUID) -> Roll? {
        rolls.first { $0.id == id }
    }

    func loadedRoll(for cameraId: UUID) -> Roll? {
        rolls.first { $0.cameraId == cameraId && $0.status == .inCamera }
    }

    func rollsForStock(_ stockId: UUID) -> [Roll] {
        rolls.filter { $0.stockId == stockId }
    }

    func shotRollsForStock(_ stockId: UUID) -> [Roll] {
        rollsForStock(stockId).filter { $0.status.countsAsShot }
    }

    func shotRollCount(for stockId: UUID) -> Int {
        shotRollsForStock(stockId).count
    }

    func fridgeCount(for stockId: UUID) -> Int {
        fridgeItems.filter { $0.stockId == stockId }.reduce(0) { $0 + $1.quantity }
    }

    var availableFridgeItems: [FridgeItem] {
        fridgeItems
            .filter { $0.quantity > 0 }
            .sorted {
                let left = stock(for: $0.stockId)?.name ?? ""
                let right = stock(for: $1.stockId)?.name ?? ""
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
    }

    func fridgeItems(for stockId: UUID) -> [FridgeItem] {
        fridgeItems.filter { $0.stockId == stockId && $0.quantity > 0 }
    }

    func rollsForCamera(_ cameraId: UUID) -> [Roll] {
        rolls.filter { $0.cameraId == cameraId }
    }

    var activeRolls: [Roll] {
        rolls.filter { $0.status != .archived }
    }

    /// Rolls sitting in inventory and ready to load into a camera.
    var inventoryRolls: [Roll] {
        activeRolls
            .filter { $0.status.isInventory || $0.status.normalized == .inFridge }
            .sorted { $0.shortId > $1.shortId }
    }

    var archivedRolls: [Roll] {
        rolls.filter { $0.status == .archived }
            .sorted { ($0.archivedDate ?? .distantPast) > ($1.archivedDate ?? .distantPast) }
    }

    var allTags: [String] {
        var tags = Set<String>()
        for roll in rolls {
            tags.formUnion(roll.tags)
            for marker in roll.frameMarkers {
                tags.formUnion(marker.tags)
            }
        }
        return tags.sorted()
    }

    var nearExpiryFridgeCount: Int {
        fridgeItems.filter { $0.isNearExpiry || $0.isExpired }.reduce(0) { $0 + $1.quantity }
    }

    // MARK: - Summaries

    var loadedCameraCount: Int {
        rolls.filter { $0.status == .inCamera }.count
    }

    var pipelineSummary: String {
        guard !activeRolls.isEmpty else { return "no rolls yet" }
        let segments: [(String, Int)] = [
            ("in stock", activeRolls.filter { $0.status.isInventory }.count),
            ("in camera", activeRolls.filter { $0.status == .inCamera }.count),
            ("waiting", activeRolls.filter { $0.status == .shotUndeveloped }.count),
            ("at lab", activeRolls.filter { $0.status == .atLab }.count),
        ]
        let parts = segments.compactMap { label, count -> String? in
            guard count > 0 else { return nil }
            return "\(count) \(label)"
        }
        return parts.isEmpty ? "no rolls yet" : parts.joined(separator: " · ")
    }

    var camerasSummary: String {
        guard !cameras.isEmpty else { return "No bodies yet" }
        return "\(cameras.count) Bodies · \(loadedCameraCount) Loaded"
    }

    func stockHistoryLine(for stockId: UUID) -> String {
        let fridge = fridgeCount(for: stockId)
        let shot = shotRollCount(for: stockId)
        var parts: [String] = []
        if fridge > 0 {
            parts.append("\(fridge) in stock")
        }
        if shot > 0 {
            parts.append("\(shot) shot")
        }
        if parts.isEmpty {
            return "0 in stock"
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Camera actions

    func addCamera(
        name: String,
        lensSubtitle: String,
        cameraType: String,
        serialNumber: String?,
        purchaseDate: Date?,
        purchasePrice: Double?,
        quirkNote: String?,
        defaultFormat: FilmFormat? = nil
    ) {
        let quirks: [CameraQuirk] = {
            guard let quirkNote, !quirkNote.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
            return [CameraQuirk(id: UUID(), note: quirkNote)]
        }()

        let camera = Camera(
            id: UUID(),
            name: name,
            lensSubtitle: lensSubtitle,
            cameraType: cameraType,
            serialNumber: serialNumber?.isEmpty == true ? nil : serialNumber,
            purchaseDate: purchaseDate,
            purchasePrice: purchasePrice,
            photoData: nil,
            quirks: quirks,
            repairHistory: [],
            hasAttentionNeeded: quirks.isEmpty == false,
            defaultFormat: defaultFormat,
            lensMinAperture: nil,
            lensMaxAperture: nil
        )
        cameras.append(camera)
        persist()
    }

    func updateCamera(_ camera: Camera) {
        guard let index = cameras.firstIndex(where: { $0.id == camera.id }) else { return }
        var updated = camera
        updated.hasAttentionNeeded = !updated.quirks.isEmpty
        cameras[index] = updated
        persist()
    }

    func deleteCamera(_ cameraId: UUID) {
        rolls.removeAll { $0.cameraId == cameraId && $0.status == .inCamera }
        for index in rolls.indices where rolls[index].cameraId == cameraId {
            rolls[index].cameraId = nil
        }
        cameras.removeAll { $0.id == cameraId }
        persist()
    }

    // MARK: - Fridge inventory

    func addFridgeItem(
        stockId: UUID,
        format: FilmFormat,
        quantity: Int,
        expiryDate: Date?
    ) {
        if let index = fridgeItems.firstIndex(where: {
            $0.stockId == stockId && $0.format == format && $0.expiryDate == expiryDate
        }) {
            fridgeItems[index].quantity += max(quantity, 1)
        } else {
            fridgeItems.append(FridgeItem(
                id: UUID(),
                stockId: stockId,
                format: format,
                quantity: max(quantity, 1),
                expiryDate: expiryDate
            ))
        }
        persist()
    }

    func updateFridgeItem(_ item: FridgeItem) {
        guard let index = fridgeItems.firstIndex(where: { $0.id == item.id }) else { return }
        fridgeItems[index] = item
        if item.quantity <= 0 {
            fridgeItems.remove(at: index)
        }
        persist()
    }

    func consumeFridgeItem(_ itemId: UUID) -> FridgeItem? {
        guard let index = fridgeItems.firstIndex(where: { $0.id == itemId }) else { return nil }
        var item = fridgeItems[index]
        guard item.quantity > 0 else { return nil }
        item.quantity -= 1
        if item.quantity == 0 {
            fridgeItems.remove(at: index)
        } else {
            fridgeItems[index] = item
        }
        persist()
        return item
    }

    // MARK: - Roll actions

    func addRoll(
        stockId: UUID,
        status: RollStatus,
        cameraId: UUID?,
        format: FilmFormat = .format35Full,
        exposures: Int,
        pushPull: Int = 0,
        shootingISO: Int? = nil,
        frameCount: Int = 0,
        storageLocation: String? = nil,
        labName: String? = nil,
        expiryDate: Date? = nil,
        tags: [String] = []
    ) {
        let shortId = nextRollShortId()
        let now = Date()
        let normalizedStatus = status.normalized

        var roll = Roll(
            id: UUID(),
            shortId: shortId,
            stockId: stockId,
            cameraId: normalizedStatus.isInventory ? nil : cameraId,
            status: normalizedStatus,
            format: format,
            pushPull: pushPull == 0 ? nil : pushPull,
            shootingISO: shootingISO,
            frameCount: frameCount,
            pinCount: 0,
            totalExposures: exposures,
            loadedDate: normalizedStatus == .inCamera ? now : nil,
            finishedDate: normalizedStatus.countsAsShot ? now : nil,
            storageLocation: storageLocation?.isEmpty == true ? nil : storageLocation,
            expiryDate: expiryDate,
            dropOffDate: normalizedStatus == .atLab ? now : nil,
            labName: labName?.isEmpty == true ? nil : labName,
            developedDate: normalizedStatus == .developed ? now : nil,
            scannedDate: normalizedStatus == .scanned ? now : nil,
            tags: tags,
            frameMarkers: []
        )

        if normalizedStatus == .shotUndeveloped && roll.storageLocation == nil {
            roll.storageLocation = "Fridge"
        }
        if normalizedStatus == .atLab {
            roll.development = DevelopmentRecord(path: .lab, labName: roll.labName ?? "The Darkroom", dropOffDate: now)
            if roll.labName == nil { roll.labName = "The Darkroom" }
        }

        rolls.append(roll)
        persist()
    }

    func requestDeleteRoll(_ rollId: UUID) {
        guard let roll = roll(for: rollId) else { return }
        pendingDeletion = PendingRollDeletion(roll: roll, deletedAt: Date())
        rolls.removeAll { $0.id == rollId }
        persist()

        deletionTask?.cancel()
        deletionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            finalizeDelete()
        }
    }

    func undoDelete() {
        guard let pending = pendingDeletion else { return }
        deletionTask?.cancel()
        rolls.append(pending.roll)
        pendingDeletion = nil
        persist()
    }

    func finalizeDelete() {
        pendingDeletion = nil
        deletionTask?.cancel()
    }

    func deleteRoll(_ rollId: UUID) {
        rolls.removeAll { $0.id == rollId }
        persist()
    }

    func updateRoll(_ roll: Roll) {
        guard let index = rolls.firstIndex(where: { $0.id == roll.id }) else { return }
        var updated = roll
        updated.status = roll.status.normalized
        rolls[index] = updated
        persist()
    }

    /// Assign or clear the camera for a roll. Loading a camera marks the roll as in-camera
    /// so it appears on the Cameras tab.
    func assignRoll(_ rollId: UUID, to cameraId: UUID?) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }

        if let cameraId {
            for i in rolls.indices where rolls[i].cameraId == cameraId
                && rolls[i].status == .inCamera
                && rolls[i].id != rollId {
                rolls[i].status = .inFridge
                rolls[i].cameraId = nil
            }

            var roll = rolls[index]
            roll.cameraId = cameraId

            if roll.status.isInventory || roll.status == .inCamera {
                roll.status = .inCamera
                if roll.loadedDate == nil {
                    roll.loadedDate = Date()
                }
            }

            rolls[index] = roll
        } else {
            var roll = rolls[index]
            if roll.status == .inCamera {
                roll.status = .inFridge
            }
            roll.cameraId = nil
            rolls[index] = roll
        }

        persist()
    }

    func setRollStatus(_ rollId: UUID, to newStatus: RollStatus, cameraId: UUID? = nil) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]
        let target = newStatus.normalized
        guard target != roll.status else { return }

        if target.sortOrder > roll.status.sortOrder {
            while roll.status != target, let next = roll.status.nextStatus {
                applyAdvance(to: &roll, next: next, cameraId: cameraId)
                roll.status = next
                if roll.status == target { break }
            }
        } else {
            while roll.status != target, let previous = roll.status.previousStatus {
                if !canRevert(roll, to: previous) { break }
                applyRevert(from: &roll, current: roll.status)
                roll.status = previous
                if roll.status == target { break }
            }
        }

        rolls[index] = roll
        persist()
    }

    func loadRoll(
        cameraId: UUID,
        stockId: UUID,
        format: FilmFormat,
        iso: Int,
        exposures: Int,
        pushPull: Int = 0,
        expiryDate: Date? = nil,
        fromFridgeItemId: UUID? = nil
    ) {
        if let fromFridgeItemId {
            _ = consumeFridgeItem(fromFridgeItemId)
        }

        let newRoll = Roll(
            id: UUID(),
            shortId: nextRollShortId(),
            stockId: stockId,
            cameraId: cameraId,
            status: .inCamera,
            format: format,
            pushPull: pushPull == 0 ? nil : pushPull,
            shootingISO: iso,
            frameCount: 0,
            pinCount: 0,
            totalExposures: exposures,
            loadedDate: Date(),
            finishedDate: nil,
            storageLocation: nil,
            expiryDate: expiryDate,
            dropOffDate: nil,
            labName: nil,
            developedDate: nil,
            scannedDate: nil,
            frameMarkers: []
        )
        rolls.append(newRoll)
        persist()
    }

    func advanceRollStatus(_ rollId: UUID, cameraId: UUID? = nil) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]
        guard let next = roll.status.nextStatus else { return }
        applyAdvance(to: &roll, next: next, cameraId: cameraId)
        roll.status = next
        rolls[index] = roll
        persist()
    }

    func revertRollStatus(_ rollId: UUID) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]
        guard let previous = roll.status.previousStatus else { return }
        guard canRevert(roll, to: previous) else { return }
        applyRevert(from: &roll, current: roll.status)
        roll.status = previous
        rolls[index] = roll
        persist()
    }

    private func applyAdvance(to roll: inout Roll, next: RollStatus, cameraId: UUID?) {
        let now = Date()
        switch next {
        case .inCamera:
            if let cameraId { roll.cameraId = cameraId }
            if roll.loadedDate == nil { roll.loadedDate = now }
        case .shotUndeveloped:
            if roll.finishedDate == nil { roll.finishedDate = now }
            if roll.storageLocation == nil { roll.storageLocation = "Fridge" }
        case .atLab:
            if roll.dropOffDate == nil { roll.dropOffDate = now }
            if roll.labName == nil { roll.labName = "The Darkroom" }
            if roll.development == nil {
                roll.development = DevelopmentRecord(path: .lab, labName: roll.labName, dropOffDate: roll.dropOffDate)
            }
        case .developed:
            if roll.developedDate == nil { roll.developedDate = now }
            roll.development?.developedDate = roll.developedDate
        case .scanned:
            if roll.scannedDate == nil { roll.scannedDate = now }
        case .archived:
            if roll.archivedDate == nil { roll.archivedDate = now }
        default:
            break
        }
    }

    private func applyRevert(from roll: inout Roll, current: RollStatus) {
        switch current {
        case .inCamera:
            roll.cameraId = nil
            roll.loadedDate = nil
        case .shotUndeveloped:
            roll.finishedDate = nil
            roll.storageLocation = nil
        case .atLab:
            roll.dropOffDate = nil
            roll.labName = nil
            roll.development = nil
        case .developed:
            roll.developedDate = nil
            roll.development?.developedDate = nil
        case .scanned:
            roll.scannedDate = nil
        case .archived:
            roll.archivedDate = nil
        default:
            break
        }
    }

    private func canRevert(_ roll: Roll, to previous: RollStatus) -> Bool {
        if roll.status == .shotUndeveloped, previous == .inCamera,
           let cameraId = roll.cameraId, loadedRoll(for: cameraId) != nil {
            return false
        }
        return true
    }

    func dropPin(on rollId: UUID, at timestamp: Date = Date(), duplicateLast: Bool = false) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]

        let frameIndex: Int
        if roll.frameCount == 0 {
            frameIndex = 1
            roll.frameCount = 1
        } else if roll.frameMarkers.contains(where: { $0.frameIndex == roll.frameCount }) {
            frameIndex = roll.frameCount + 1
            roll.frameCount = frameIndex
        } else {
            frameIndex = roll.frameCount
        }

        var marker = FrameMarker(
            frameIndex: frameIndex,
            timestamp: timestamp,
            latitude: 40.7580 + Double.random(in: -0.01...0.01),
            longitude: -73.9855 + Double.random(in: -0.01...0.01)
        )

        if duplicateLast, let last = roll.frameMarkers.last {
            marker.aperture = last.aperture
            marker.shutterSpeed = last.shutterSpeed
            marker.location = last.location
            marker.notes = last.notes
            marker.tags = last.tags
        }

        roll.frameMarkers.removeAll { $0.frameIndex == frameIndex }
        roll.frameMarkers.append(marker)
        roll.frameMarkers = Roll.normalizeFrameMarkerIndices(roll.frameMarkers)
        roll.pinCount = roll.frameMarkers.count
        rolls[index] = roll
        persist()
    }

    func addFrameMarker(to rollId: UUID, at timestamp: Date = Date(), duplicateLast: Bool = false) {
        dropPin(on: rollId, at: timestamp, duplicateLast: duplicateLast)
    }

    func advanceExposure(on rollId: UUID) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        let cap = max(rolls[index].totalExposures, 1)
        guard rolls[index].frameCount < cap else { return }
        rolls[index].frameCount += 1
        persist()
    }

    func shiftScanAlignment(for rollId: UUID, by delta: Int) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        rolls[index].scanAlignmentOffset += delta
        persist()
    }

    func importScans(to rollId: UUID, fileNames: [String]) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        rolls[index].scanFileNames = fileNames
        if rolls[index].status == .developed {
            rolls[index].status = .scanned
            if rolls[index].scannedDate == nil {
                rolls[index].scannedDate = Date()
            }
        }
        persist()
    }

    func appendScans(to rollId: UUID, fileNames: [String]) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }), !fileNames.isEmpty else { return }
        rolls[index].scanFileNames.append(contentsOf: fileNames)
        if rolls[index].status == .developed {
            rolls[index].status = .scanned
            if rolls[index].scannedDate == nil {
                rolls[index].scannedDate = Date()
            }
        }
        persist()
    }

    func addScanFile(to rollId: UUID, fileName: String) {
        appendScans(to: rollId, fileNames: [fileName])
    }

    func removeScan(from rollId: UUID, fileName: String) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        rolls[index].scanFileNames.removeAll { $0 == fileName }
        ScanStorage.deleteScan(rollId: rollId, fileName: fileName)
        if rolls[index].scanFileNames.isEmpty,
           rolls[index].status == .scanned {
            rolls[index].status = .developed
            rolls[index].scannedDate = nil
        }
        persist()
    }

    func removeLastFrame(from rollId: UUID) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]
        guard roll.frameCount > 0 else { return }

        if let markerIndex = roll.frameMarkers.firstIndex(where: { $0.frameIndex == roll.frameCount }) {
            roll.frameMarkers.remove(at: markerIndex)
            roll.pinCount = roll.frameMarkers.count
        }
        roll.frameCount -= 1
        rolls[index] = roll
        persist()
    }

    func setFrameCount(_ count: Int, for rollId: UUID) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]
        let cap = max(roll.totalExposures, 1)
        let clamped = min(max(count, 0), cap)
        roll.frameCount = clamped
        if roll.frameMarkers.count > clamped {
            roll.frameMarkers = Array(roll.frameMarkers.prefix(clamped))
        }
        roll.pinCount = roll.frameMarkers.count
        rolls[index] = roll
        persist()
    }

    func updateFrameMarker(_ rollId: UUID, marker: FrameMarker) {
        guard let rollIndex = rolls.firstIndex(where: { $0.id == rollId }),
              let markerIndex = rolls[rollIndex].frameMarkers.firstIndex(where: { $0.id == marker.id }) else { return }
        rolls[rollIndex].frameMarkers[markerIndex] = marker
        persist()
    }

    func upsertFrameMarker(_ rollId: UUID, marker: FrameMarker) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        var roll = rolls[index]
        roll.frameMarkers.removeAll { $0.frameIndex == marker.frameIndex }
        roll.frameMarkers.append(marker)
        roll.frameMarkers = Roll.normalizeFrameMarkerIndices(roll.frameMarkers)
        roll.frameCount = max(roll.frameCount, roll.frameMarkers.map(\.frameIndex).max() ?? 0)
        roll.pinCount = roll.frameMarkers.count
        rolls[index] = roll
        persist()
    }

    func addDevRecipePreset(_ preset: DevRecipePreset) {
        devRecipePresets.append(preset)
        persist()
    }

    func applyDevPreset(_ presetId: UUID, to rollId: UUID) {
        guard let preset = devRecipePresets.first(where: { $0.id == presetId }),
              var roll = roll(for: rollId) else { return }
        roll.development = DevelopmentRecord(
            path: .diy,
            developer: preset.developer,
            dilution: preset.dilution,
            timeMinutes: preset.timeMinutes,
            temperatureC: preset.temperatureC,
            agitationNotes: preset.agitationNotes
        )
        updateRoll(roll)
    }

    // MARK: - Export

    func csvExport(for rollId: UUID) -> String? {
        guard let roll = roll(for: rollId),
              let stock = stock(for: roll.stockId) else { return nil }
        let camera = camera(for: roll.cameraId)

        var lines = [
            "field,value",
            "roll_id,\(roll.shortId)",
            "stock,\(csvEscape(stock.name))",
            "iso,\(roll.shootingISO ?? stock.iso)",
            "format,\(roll.format.displayName)",
            "camera,\(csvEscape(camera?.name ?? ""))",
            "status,\(roll.status.displayName)",
            "tags,\(csvEscape(roll.tags.joined(separator: "; ")))",
            "loaded,\(roll.loadedDate.map { DateFormatters.telemetry.string(from: $0) } ?? "")",
            "finished,\(roll.finishedDate.map { DateFormatters.telemetry.string(from: $0) } ?? "")",
            "developed,\(roll.developedDate.map { DateFormatters.telemetry.string(from: $0) } ?? "")",
            "development,\(csvEscape(roll.development?.summary ?? ""))",
            "notes,\(csvEscape(roll.notes ?? ""))",
            "",
            "frame,timestamp,latitude,longitude,aperture,shutter,tags,notes"
        ]

        for (index, marker) in roll.frameMarkers.enumerated() {
            let aperture = marker.aperture.map { "f/\($0)" } ?? ""
            let shutter = marker.shutterSpeed.map { formatShutter($0) } ?? ""
            lines.append([
                "\(index + 1)",
                DateFormatters.telemetry.string(from: marker.timestamp),
                "\(marker.latitude)",
                "\(marker.longitude)",
                csvEscape(aperture),
                csvEscape(shutter),
                csvEscape(marker.tags.joined(separator: "; ")),
                csvEscape(marker.notes ?? "")
            ].joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    func rollDataSheetText(for rollId: UUID) -> String? {
        guard let roll = roll(for: rollId),
              let stock = stock(for: roll.stockId) else { return nil }
        let camera = camera(for: roll.cameraId)

        var lines: [String] = [
            roll.shortId,
            stock.name,
            roll.format.displayName,
            camera?.name ?? "—",
            "",
            "Loaded: \(roll.loadedDate.map { DateFormatters.medium.string(from: $0) } ?? "—")",
            "Finished: \(roll.finishedDate.map { DateFormatters.medium.string(from: $0) } ?? "—")",
        ]

        if let development = roll.development {
            lines.append("Development: \(development.summary)")
        }

        if !roll.tags.isEmpty {
            lines.append("Tags: \(roll.tags.joined(separator: ", "))")
        }

        if !roll.frameMarkers.isEmpty {
            lines.append("")
            lines.append("Frames")
            for (index, marker) in roll.frameMarkers.enumerated() {
                lines.append("  \(index + 1). \(DateFormatters.telemetry.string(from: marker.timestamp))")
            }
        }

        if let notes = roll.notes, !notes.isEmpty {
            lines.append("")
            lines.append("Notes")
            lines.append(notes)
        }

        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        return "1/\(Int(round(1 / seconds)))"
    }

    func mockRecognize() -> LoadRecognitionResult {
        let matchedCamera = cameras.first
        let matchedStock = stocks.first(where: {
            $0.name.contains("Portra 400") || $0.name.contains("Ektacolor Pro 400")
        }) ?? stocks.first
        return LoadRecognitionResult(
            cameraId: matchedCamera?.id,
            cameraConfidence: matchedCamera != nil ? .matched : .low,
            stockId: matchedStock?.id,
            stockConfidence: matchedStock != nil ? .dxRead : .low,
            iso: matchedStock?.iso ?? 400,
            isoFromDX: matchedStock != nil,
            exposures: 36
        )
    }

    func nextRollShortId() -> String {
        let numbers = rolls.compactMap { roll -> Int? in
            guard roll.shortId.hasPrefix("R-") else { return nil }
            return Int(roll.shortId.dropFirst(2))
        }
        let next = (numbers.max() ?? 0) + 1
        return "R-\(next)"
    }
}
