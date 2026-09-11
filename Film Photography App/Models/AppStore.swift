import CoreLocation
import Network
import SwiftUI
import UIKit
import WidgetKit

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

struct PersistProblem: Equatable {
    enum Kind {
        case save
        case load
    }

    let kind: Kind
    let message: String

    var retryTitle: String {
        kind == .load ? "Retry load" : "Retry"
    }
}

/// What a frame is being given when a roll's scans are laid out: a scan already written
/// to the roll, or one picked from the library and still only in memory.
enum ScanAssignment {
    case existing(fileName: String)
    case new(Data)
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
    /// How the user chose to add a roll. Set to open the add-roll sheet on that path.
    var addRollEntry: AddRollEntry?
    var showingLoadFlow = false
    var showingSettings = false
    /// Set when a widget (or other deep link) asks to show a roll.
    var pendingOpenRollId: UUID?
    var showingArchive = false
    /// Opens Load Flow past the source chooser (camera already taken or about to open).
    var loadFlowStartWithCamera = false
    var pendingLoadCapture: UIImage?

    /// Set when a disk read or write fails. The in-memory rolls stay as they are; the
    /// last good file on disk is left untouched until a retry succeeds.
    var persistProblem: PersistProblem?

    var iCloudSyncEnabled: Bool {
        get { iCloudLibraryMirror.isEnabled }
        set {
            guard iCloudLibraryMirror.isEnabled != newValue else { return }
            iCloudLibraryMirror.isEnabled = newValue
            if newValue {
                reconcileiCloud()
            } else {
                iCloudPushTask?.cancel()
                iCloudPushTask = nil
                if case .syncing = iCloudSyncStatus {
                    iCloudSyncStatus = iCloudLibraryMirror.rememberedStatus
                }
            }
        }
    }

    var iCloudSyncStatus: iCloudSyncStatus = iCloudLibraryMirror.rememberedStatus

    var iCloudStatusLine: String {
        displayediCloudStatus.line
    }

    private var displayediCloudStatus: iCloudSyncStatus {
        if case .syncing = iCloudSyncStatus { return .syncing }
        if iCloudSyncEnabled, !canUseiCloud { return .unavailable }
        return iCloudSyncStatus
    }

    private var canUseiCloud: Bool {
        !iCloudLibraryMirror.isDisabled
            && DataPersistence.fileURLOverride == nil
            && iCloudLibraryMirror.isAvailable
    }

    private var deletionTask: Task<Void, Never>?
    /// After a failed load we must not write a new store over the unreadable file.
    private var didFailToLoadStore = false
    private var libraryUpdatedAt: Date?
    @ObservationIgnored private var iCloudPushTask: Task<Void, Never>?
    @ObservationIgnored private var iCloudReconcileTask: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    /// How long a location fix stays good enough to reuse for the next frame.
    private static let fixLifetime: TimeInterval = 90

    @ObservationIgnored private var cachedFix: (place: ResolvedPlace, at: Date)?
    @ObservationIgnored private var pendingFix: Task<ResolvedPlace?, Never>?

    init() {
        cameras = []
        rolls = []
        fridgeItems = []
        devRecipePresets = []
        customStocks = []
        stocks = StockCatalog.loadStocks()
        pendingDeletion = nil
        deletionTask = nil
        loadFromDisk()
        startNetworkMonitor()
        reconcileiCloud()
    }

    /// Retries a failed save, or reloads from disk after a failed read.
    func retryPersist() {
        if persistProblem?.kind == .load {
            loadFromDisk()
            return
        }
        persist()
    }

    private func loadFromDisk() {
        switch DataPersistence.load() {
        case .loaded(let saved, let source):
            apply(saved)
            didFailToLoadStore = false
            persistProblem = nil
            if saved.version < PersistedAppData.currentVersion || source == .backup {
                persist()
            }
        case .empty:
            didFailToLoadStore = false
            persistProblem = nil
            // Leave the file unwritten so a reinstall can still pull iCloud data.
        case .unreadable(let message):
            didFailToLoadStore = true
            persistProblem = PersistProblem(
                kind: .load,
                message: "\(message) Your last save is still on disk — nothing new has been written over it."
            )
        }
    }

    private func apply(_ saved: PersistedAppData) {
        cameras = saved.cameras
        rolls = saved.rolls.map(Roll.migrate)
        fridgeItems = saved.fridgeItems
        devRecipePresets = saved.devRecipePresets
        customStocks = saved.customStocks
        stocks = StockCatalog.loadStocks() + saved.customStocks
        pendingDeletion = nil
        libraryUpdatedAt = saved.updatedAt
    }

    private func persist(touchUpdatedAt: Bool = true, pushToiCloud: Bool = true) {
        do {
            if didFailToLoadStore {
                try DataPersistence.quarantineUnreadablePrimary()
            }
            if touchUpdatedAt {
                libraryUpdatedAt = Date()
            }
            try DataPersistence.save(
                cameras: cameras,
                rolls: rolls.map { var r = $0; r.status = $0.status.normalized; return r },
                fridgeItems: fridgeItems,
                devRecipePresets: devRecipePresets,
                customStocks: customStocks,
                updatedAt: libraryUpdatedAt
            )
            didFailToLoadStore = false
            persistProblem = nil
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStorage.widgetKind)
            if pushToiCloud {
                scheduleiCloudPush()
            }
        } catch {
            persistProblem = PersistProblem(
                kind: didFailToLoadStore ? .load : .save,
                message: didFailToLoadStore
                    ? "Couldn't replace the unreadable save. Your last file is still on disk."
                    : "Couldn't save your rolls. They're still in this session — tap Retry so they aren't lost."
            )
        }
    }

    /// Opens the roll named by a widget tap. Returns false if the URL is not ours.
    @discardableResult
    func openRoll(from url: URL) -> Bool {
        guard let id = AppDeepLink.rollId(from: url) else { return false }
        pendingOpenRollId = id
        showingSettings = false
        showingAddCamera = false
        showingLoadFlow = false
        addRollEntry = nil
        return true
    }

    func reconcileiCloud() {
        guard iCloudSyncEnabled, canUseiCloud else {
            if iCloudSyncEnabled, !canUseiCloud {
                iCloudSyncStatus = .unavailable
            }
            return
        }
        iCloudReconcileTask?.cancel()
        iCloudReconcileTask = Task { await runiCloudReconcile() }
    }

    private func currentPayload() -> PersistedAppData {
        PersistedAppData(
            cameras: cameras,
            rolls: rolls.map { var r = $0; r.status = $0.status.normalized; return r },
            fridgeItems: fridgeItems,
            devRecipePresets: devRecipePresets,
            customStocks: customStocks,
            updatedAt: libraryUpdatedAt
        )
    }

    private func scheduleiCloudPush() {
        guard iCloudSyncEnabled, canUseiCloud else { return }
        iCloudPushTask?.cancel()
        iCloudPushTask = Task { await runiCloudPush() }
    }

    private func runiCloudPush() async {
        guard iCloudSyncEnabled, canUseiCloud else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        iCloudSyncStatus = .syncing
        do {
            try await iCloudLibraryMirror.push(currentPayload())
            iCloudSyncStatus = iCloudLibraryMirror.rememberedStatus
        } catch {
            iCloudSyncStatus = .failed
        }
    }

    private func runiCloudReconcile() async {
        guard iCloudSyncEnabled, canUseiCloud else { return }
        iCloudSyncStatus = .syncing
        do {
            let remote = try await iCloudLibraryMirror.fetchRemote()
            guard !Task.isCancelled else { return }
            let local = currentPayload()
            switch iCloudLibraryMirror.resolve(local: local, remote: remote) {
            case .takeRemote:
                if let remote {
                    apply(remote)
                    persist(touchUpdatedAt: false, pushToiCloud: false)
                }
                iCloudLibraryMirror.lastSyncedAt = Date()
                iCloudSyncStatus = iCloudLibraryMirror.rememberedStatus
            case .keepLocal:
                try await iCloudLibraryMirror.push(local)
                iCloudSyncStatus = iCloudLibraryMirror.rememberedStatus
            case .nothing:
                iCloudSyncStatus = iCloudLibraryMirror.rememberedStatus
            }
        } catch {
            guard !Task.isCancelled else { return }
            iCloudSyncStatus = .failed
        }
    }

    private func startNetworkMonitor() {
        guard DataPersistence.fileURLOverride == nil, pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                self?.reconcileiCloud()
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor

        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileiCloud()
            }
        }
    }

    /// Writes cameras, rolls, fridge, recipes, custom stocks, and scan files to a zip.
    /// The zip is built off the main thread so the settings button can keep spinning.
    func exportLibraryBackup() async throws -> URL {
        let payload = PersistedAppData(
            cameras: cameras,
            rolls: rolls.map { var r = $0; r.status = $0.status.normalized; return r },
            fridgeItems: fridgeItems,
            devRecipePresets: devRecipePresets,
            customStocks: customStocks
        )
        let libraryJSON = try DataPersistence.encode(payload)
        let scans = ScanStorage.allScanFiles()
        let fileName = LibraryBackup.suggestedFileName

        return try await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try LibraryBackup.write(libraryJSON: libraryJSON, scans: scans, to: url)
            return url
        }.value
    }

    /// Replaces the on-device library. `persist()` copies the current JSON to `.bak`
    /// before writing, so a failed import can still be recovered from that file.
    func restoreLibrary(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let backup = try LibraryBackup.read(from: url)
        apply(backup.payload)
        didFailToLoadStore = false
        persist()
        try ScanStorage.replaceAll(with: backup.scansDirectory)
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
        stocks.first { $0.id == id } ?? customStocks.first { $0.id == id }
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

    /// Rolls sitting in inventory and ready to load into a camera, most recently added
    /// first. Rolls are appended as they are created, so the array's own order is the
    /// order they arrived in.
    var inventoryRolls: [Roll] {
        Array(
            activeRolls
                .filter { $0.status.isInventory || $0.status.normalized == .inFridge }
                .reversed()
        )
    }

    /// What to call a roll on screen: the film loaded in it.
    func label(for roll: Roll) -> String {
        stock(for: roll.stockId)?.name ?? "Roll"
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
            lensMaxAperture: nil,
            lenses: {
                let name = lensSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return [] }
                return [
                    CameraLens(
                        id: UUID(),
                        name: name,
                        focalLength: "",
                        maxAperture: "",
                        notes: "",
                        isPrimary: true
                    )
                ]
            }()
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

    func addLens(
        to cameraId: UUID,
        name: String,
        focalLength: String,
        maxAperture: String,
        notes: String
    ) {
        guard var camera = camera(for: cameraId) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        camera.lenses.append(
            CameraLens(
                id: UUID(),
                name: trimmed,
                focalLength: focalLength.trimmingCharacters(in: .whitespacesAndNewlines),
                maxAperture: maxAperture.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrimary: camera.lenses.isEmpty
            )
        )
        camera.syncPrimaryLensSubtitle()
        updateCamera(camera)
    }

    func updateLens(_ lens: CameraLens, on cameraId: UUID) {
        guard var camera = camera(for: cameraId),
              let index = camera.lenses.firstIndex(where: { $0.id == lens.id }) else { return }
        camera.lenses[index] = lens
        camera.syncPrimaryLensSubtitle()
        updateCamera(camera)
        refreshFrameLensName(lensId: lens.id, to: lens.exifModel)
    }

    func deleteLens(_ lensId: UUID, from cameraId: UUID) {
        guard var camera = camera(for: cameraId) else { return }
        let wasPrimary = camera.lenses.first(where: { $0.id == lensId })?.isPrimary == true
        camera.lenses.removeAll { $0.id == lensId }
        if wasPrimary, let first = camera.lenses.indices.first {
            camera.lenses[first].isPrimary = true
        }
        camera.syncPrimaryLensSubtitle()
        updateCamera(camera)
        dropFrameLensId(lensId)
    }

    func setPrimaryLens(_ lensId: UUID, on cameraId: UUID) {
        guard var camera = camera(for: cameraId) else { return }
        for index in camera.lenses.indices {
            camera.lenses[index].isPrimary = camera.lenses[index].id == lensId
        }
        camera.syncPrimaryLensSubtitle()
        updateCamera(camera)
    }

    func deleteCamera(_ cameraId: UUID) {
        rolls.removeAll { $0.cameraId == cameraId && $0.status == .inCamera }
        for index in rolls.indices where rolls[index].cameraId == cameraId {
            rolls[index].cameraId = nil
            revalidateFrameLenses(on: &rolls[index], cameraId: nil)
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
        frozenDate: Date? = nil,
        labName: String? = nil,
        expiryDate: Date? = nil,
        tags: [String] = []
    ) {
        let now = Date()
        let normalizedStatus = status.normalized

        var roll = Roll(
            id: UUID(),
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
            frozenDate: StorageMethod.resolved(from: storageLocation) == .freezer ? frozenDate : nil,
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
                // Fresh load from inventory — no exposures taken yet; focus frame 1 at 0/N.
                if roll.status.isInventory {
                    roll.frameCount = 0
                }
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

    /// Corrects which camera a roll was shot on. Unlike `assignRoll` this is a plain
    /// metadata edit — status, frame count and loaded date are left untouched — so it is
    /// safe to expose from places like the frame detail screen.
    func setRollCamera(_ rollId: UUID, to cameraId: UUID?) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        guard rolls[index].cameraId != cameraId else { return }

        // A camera holds at most one loaded roll, so displace the current occupant.
        if let cameraId, rolls[index].status == .inCamera {
            for i in rolls.indices where rolls[i].cameraId == cameraId
                && rolls[i].status == .inCamera
                && rolls[i].id != rollId {
                rolls[i].status = .inFridge
                rolls[i].cameraId = nil
            }
        }

        rolls[index].cameraId = cameraId
        revalidateFrameLenses(on: &rolls[index], cameraId: cameraId)
        persist()
    }

    /// Frames keep a lens only when it still belongs to the roll's body.
    private func revalidateFrameLenses(on roll: inout Roll, cameraId: UUID?) {
        let allowed = Set(camera(for: cameraId)?.lenses.map(\.id) ?? [])
        for index in roll.frameMarkers.indices {
            guard let lensId = roll.frameMarkers[index].lensId else { continue }
            if !allowed.contains(lensId) {
                roll.frameMarkers[index].lensId = nil
                roll.frameMarkers[index].lensName = nil
            }
        }
    }

    private func refreshFrameLensName(lensId: UUID, to name: String) {
        var changed = false
        for rollIndex in rolls.indices {
            for markerIndex in rolls[rollIndex].frameMarkers.indices
            where rolls[rollIndex].frameMarkers[markerIndex].lensId == lensId {
                rolls[rollIndex].frameMarkers[markerIndex].lensName = name
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Keep the printed name so EXIF still has something after the glass is deleted.
    private func dropFrameLensId(_ lensId: UUID) {
        var changed = false
        for rollIndex in rolls.indices {
            for markerIndex in rolls[rollIndex].frameMarkers.indices
            where rolls[rollIndex].frameMarkers[markerIndex].lensId == lensId {
                rolls[rollIndex].frameMarkers[markerIndex].lensId = nil
                changed = true
            }
        }
        if changed { persist() }
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
            marker.iso = last.iso
            marker.location = last.location
            marker.notes = last.notes
            marker.tags = last.tags
            marker.lensId = last.lensId
            marker.lensName = last.lensName
        }

        if marker.iso == nil {
            let stockISO = stocks.first(where: { $0.id == roll.stockId })?.iso
            marker.iso = roll.shootingISO ?? stockISO
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
        let shotFrame = rolls[index].frameCount
        persist()
        stampCapture(on: rollId, frameIndex: shotFrame)
    }

    /// Records when — and where — a frame was shot at the moment the shutter is logged.
    /// The date lands straight away; the location follows once a fix arrives. The lens
    /// copies the previous frame, or the body's default. All three stay empty until
    /// filled, so a later edit by the photographer wins.
    private func stampCapture(on rollId: UUID, frameIndex: Int) {
        guard let roll = roll(for: rollId), frameIndex > 0 else { return }

        let existing = roll.frameMarkers.first { $0.frameIndex == frameIndex }
        var marker = existing ?? FrameMarker(frameIndex: frameIndex)
        if marker.captureDate == nil {
            marker.captureDate = Date()
        }
        if marker.lensId == nil, (marker.lensName?.isEmpty ?? true) {
            if let inherited = inheritedLens(on: roll, before: frameIndex) {
                marker.lensId = inherited.id
                marker.lensName = inherited.name
            }
        }
        applyPointAndShootDefaults(to: &marker, on: roll)
        if marker != existing {
            upsertFrameMarker(rollId, marker: marker)
        }

        // A fix can take a while to arrive, or be refused outright, so a frame can end up
        // dated but unplaced. Ask again on any later shutter press for the same frame
        // rather than treating the date as proof the whole stamp already happened.
        guard marker.location == nil else { return }
        Task { await stampLocation(on: rollId, frameIndex: frameIndex) }
    }

    /// A P&S picks the stop itself. Only empty readings are filled, so a later
    /// edit on the dials still wins.
    private func applyPointAndShootDefaults(to marker: inout FrameMarker, on roll: Roll) {
        guard let camera = roll.cameraId.flatMap({ camera(for: $0) }), camera.isPointAndShoot else {
            return
        }
        if marker.aperture == nil {
            marker.aperture = ExposureScale.autoValue
        }
        if marker.shutterSpeed == nil {
            marker.shutterSpeed = ExposureScale.autoValue
        }
    }

    /// Previous frame's glass, then the body's default. A new shot keeps the last
    /// lens until the photographer picks another one on that frame.
    private func inheritedLens(on roll: Roll, before frameIndex: Int) -> (id: UUID?, name: String?)? {
        let previous = roll.frameMarkers
            .filter { $0.frameIndex < frameIndex }
            .max { $0.frameIndex < $1.frameIndex }
        if let previous, previous.lensId != nil || !(previous.lensName?.isEmpty ?? true) {
            return (previous.lensId, previous.lensName)
        }
        guard let lens = roll.cameraId.flatMap({ camera(for: $0) })?.primaryLens else {
            return nil
        }
        return (lens.id, lens.exifModel)
    }

    private func stampLocation(on rollId: UUID, frameIndex: Int) async {
        guard let place = await currentFix() else { return }
        guard let roll = roll(for: rollId),
              var marker = roll.frameMarkers.first(where: { $0.frameIndex == frameIndex }),
              marker.location == nil
        else { return }

        marker.location = place.name
        if let coordinate = place.coordinate {
            marker.latitude = coordinate.latitude
            marker.longitude = coordinate.longitude
        }
        upsertFrameMarker(rollId, marker: marker)
    }

    /// Shared fix for the shutter. Rapid frames reuse a recent result rather than each
    /// starting its own location stream, and a lookup already in flight is awaited.
    private func currentFix() async -> ResolvedPlace? {
        if let cachedFix, Date().timeIntervalSince(cachedFix.at) < Self.fixLifetime {
            return cachedFix.place
        }
        if let pendingFix {
            return await pendingFix.value
        }

        let task = Task<ResolvedPlace?, Never> { try? await CurrentLocation.resolve() }
        pendingFix = task
        let place = await task.value
        pendingFix = nil

        if let place {
            cachedFix = (place, Date())
        }
        return place
    }

    func setFramePhoto(on rollId: UUID, frameIndex: Int, imageData: Data) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }), frameIndex > 0 else { return }
        let key = String(frameIndex)
        if let existing = rolls[index].framePhotoFileNames[key] {
            ScanStorage.deleteScan(rollId: rollId, fileName: existing)
        }
        let fileName = "frame-\(frameIndex)-\(UUID().uuidString.prefix(8)).jpg"
        guard ScanStorage.saveScan(data: imageData, rollId: rollId, fileName: fileName) != nil else { return }
        rolls[index].framePhotoFileNames[key] = fileName
        if rolls[index].frameCount < frameIndex {
            rolls[index].frameCount = frameIndex
        }
        persist()
    }

    func removeFramePhoto(from rollId: UUID, frameIndex: Int) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }
        let key = String(frameIndex)
        guard let fileName = rolls[index].framePhotoFileNames.removeValue(forKey: key) else { return }
        ScanStorage.deleteScan(rollId: rollId, fileName: fileName)
        persist()
    }

    /// Lays out every scan on a roll at once: which frame each one belongs to, whether it
    /// is already on the roll or has just been picked. Frames left out of `placement` end
    /// up empty.
    ///
    /// This has to be done in a single pass. `setFramePhoto` deletes whatever a frame was
    /// holding before it writes, so replaying a rearrangement frame by frame would throw
    /// away a scan that another frame is about to claim — swapping two frames would lose
    /// one of them. Working out what survives first means a file is only deleted once
    /// nothing points at it any more.
    func setScanPlacement(on rollId: UUID, placement: [Int: ScanAssignment]) {
        guard let index = rolls.firstIndex(where: { $0.id == rollId }) else { return }

        flattenScanList(at: index)

        let previous = Set(rolls[index].framePhotoFileNames.values)
        var mapping: [String: String] = [:]

        for frameIndex in placement.keys.sorted() where frameIndex > 0 {
            switch placement[frameIndex] {
            case .existing(let fileName):
                mapping[String(frameIndex)] = fileName
            case .new(let data):
                let fileName = "frame-\(frameIndex)-\(UUID().uuidString.prefix(8)).jpg"
                if ScanStorage.saveScan(data: data, rollId: rollId, fileName: fileName) != nil {
                    mapping[String(frameIndex)] = fileName
                }
            case nil:
                continue
            }
        }

        for orphan in previous.subtracting(mapping.values) {
            ScanStorage.deleteScan(rollId: rollId, fileName: orphan)
        }

        rolls[index].framePhotoFileNames = mapping
        if let highest = mapping.keys.compactMap(Int.init).max(), rolls[index].frameCount < highest {
            rolls[index].frameCount = highest
        }
        persist()
    }

    /// Folds a roll's positional scan list into the per-frame mapping.
    ///
    /// The list assigns scans to frames by their order in it, so the only way to move one
    /// is to shift every scan along with it. A scan can't be put on an arbitrary frame
    /// while it lives there. Both representations already render the same way, and no
    /// file is touched — only which frame each name is filed under.
    private func flattenScanList(at index: Int) {
        let roll = rolls[index]
        guard !roll.scanFileNames.isEmpty else { return }

        for (offset, fileName) in roll.scanFileNames.enumerated() {
            let frameIndex = offset + 1 + roll.scanAlignmentOffset
            guard frameIndex > 0, rolls[index].framePhotoFileNames[String(frameIndex)] == nil else { continue }
            rolls[index].framePhotoFileNames[String(frameIndex)] = fileName
        }
        rolls[index].scanFileNames = []
        rolls[index].scanAlignmentOffset = 0
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
            "roll_id,\(roll.id.uuidString)",
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
            let aperture = marker.aperture.map { ExposureFormat.aperture($0) } ?? ""
            let shutter = marker.shutterSpeed.map { ExposureFormat.shutter($0) } ?? ""
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

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
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

}
