import Foundation

enum StorageMethod: String, CaseIterable, Identifiable, Codable {
    case roomTemperature = "Room temperature"
    case fridge = "Fridge"
    case freezer = "Freezer"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Maps free-text leftovers (`Fridge`, `freezer`, custom notes) onto the three options.
    static func resolved(from stored: String?) -> StorageMethod {
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .fridge
        }
        if let match = allCases.first(where: {
            $0.rawValue.compare(stored, options: .caseInsensitive) == .orderedSame
        }) {
            return match
        }
        let lower = stored.lowercased()
        if lower.contains("freez") { return .freezer }
        if lower.contains("room") { return .roomTemperature }
        return .fridge
    }
}

enum RollStatus: String, CaseIterable, Codable, Comparable {
    case acquired // legacy — migrated to inFridge on load
    case inFridge
    case inCamera
    case shotUndeveloped
    case atLab
    case developed
    case scanned
    case archived

    static var pipelineCases: [RollStatus] {
        [.inFridge, .inCamera, .shotUndeveloped, .atLab, .developed, .scanned]
    }

    /// Section order on the Rolls tab — active shooting first, inventory last among early stages.
    static var activePipelineCases: [RollStatus] {
        [.inCamera, .shotUndeveloped, .inFridge, .atLab, .developed, .scanned]
    }

    var displayName: String {
        switch self {
        case .acquired, .inFridge: "In stock"
        case .inCamera: "In camera"
        case .shotUndeveloped: "Shot, undeveloped"
        case .atLab: "At lab"
        case .developed: "Developed"
        case .scanned: "Scanned"
        case .archived: "Archived"
        }
    }

    var sectionTitle: String { displayName }

    var sortOrder: Int {
        switch self {
        case .acquired, .inFridge: 0
        case .inCamera: 1
        case .shotUndeveloped: 2
        case .atLab: 3
        case .developed: 4
        case .scanned: 5
        case .archived: 6
        }
    }

    static func < (lhs: RollStatus, rhs: RollStatus) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var nextStatus: RollStatus? {
        switch self {
        case .acquired, .inFridge: .inCamera
        case .inCamera: .shotUndeveloped
        case .shotUndeveloped: .atLab
        case .atLab: .developed
        case .developed: .scanned
        case .scanned: .archived
        case .archived: nil
        }
    }

    var previousStatus: RollStatus? {
        switch self {
        case .acquired, .inFridge: nil
        case .inCamera: .inFridge
        case .shotUndeveloped: .inCamera
        case .atLab: .shotUndeveloped
        case .developed: .atLab
        case .scanned: .developed
        case .archived: .scanned
        }
    }

    var pipelineRevertLabel: String? {
        guard let previous = previousStatus else { return nil }
        return "Back to \(previous.displayName)"
    }

    var showsCamera: Bool {
        switch self {
        case .acquired, .inFridge: false
        default: true
        }
    }

    var isInventory: Bool {
        self == .acquired || self == .inFridge
    }

    /// True once the roll has left the camera — finished shooting or beyond.
    var countsAsShot: Bool {
        switch self {
        case .acquired, .inFridge, .inCamera: false
        default: true
        }
    }

    /// True once the roll has been developed (scans can be attached).
    var canImportScans: Bool {
        switch self {
        case .developed, .scanned, .archived: true
        default: false
        }
    }

    /// Label for the action that advances from this status to the next.
    var pipelineActionLabel: String? {
        switch self {
        case .acquired, .inFridge: "Load in camera"
        case .inCamera: "Unload roll"
        case .shotUndeveloped: "Send to lab"
        case .atLab: "Mark developed"
        case .developed: "Receive scans"
        case .scanned: "Archive roll"
        case .archived: nil
        }
    }

    /// Short slide prompt for the advance gate.
    var pipelineSlidePrompt: String? {
        switch self {
        case .acquired, .inFridge: nil // inventory rolls load via the camera picker
        case .inCamera: "slide to unload"
        case .shotUndeveloped: "slide to lab"
        case .atLab: "slide to developed"
        case .developed: "slide for scans"
        case .scanned: "slide to archive"
        case .archived: nil
        }
    }

    /// Compact label for stage strip nodes.
    var pipelineNodeLabel: String {
        switch self {
        case .acquired, .inFridge: "Stock"
        case .inCamera: "Camera"
        case .shotUndeveloped: "Shot"
        case .atLab: "Lab"
        case .developed: "Dev"
        case .scanned: "Scan"
        case .archived: "Arch"
        }
    }

    /// Stages shown on the pipeline rail (inventory → archive).
    static var railCases: [RollStatus] {
        [.inFridge, .inCamera, .shotUndeveloped, .atLab, .developed, .scanned, .archived]
    }

    var normalized: RollStatus {
        self == .acquired ? .inFridge : self
    }
}

struct FrameMarker: Identifiable, Codable, Hashable {
    let id: UUID
    var frameIndex: Int
    var timestamp: Date
    /// Date the frame was shot, as entered by the photographer. `timestamp` stays the
    /// record's own creation time so marker ordering and exports are unaffected.
    var captureDate: Date?
    var latitude: Double
    var longitude: Double
    var aperture: Double?
    var shutterSpeed: Double?
    var iso: Int?
    var location: String?
    var notes: String?
    var tags: [String]
    /// Glass on this frame. `lensId` points at a `CameraLens` on the roll's body;
    /// `lensName` is the EXIF string so a deleted lens still exports.
    var lensId: UUID?
    var lensName: String?

    init(
        id: UUID = UUID(),
        frameIndex: Int = 1,
        timestamp: Date = Date(),
        captureDate: Date? = nil,
        latitude: Double = 0,
        longitude: Double = 0,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        iso: Int? = nil,
        location: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        lensId: UUID? = nil,
        lensName: String? = nil
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.captureDate = captureDate
        self.latitude = latitude
        self.longitude = longitude
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.location = location
        self.notes = notes
        self.tags = tags
        self.lensId = lensId
        self.lensName = lensName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frameIndex = try container.decodeIfPresent(Int.self, forKey: .frameIndex) ?? 1
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        captureDate = try container.decodeIfPresent(Date.self, forKey: .captureDate)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        aperture = try container.decodeIfPresent(Double.self, forKey: .aperture)
        shutterSpeed = try container.decodeIfPresent(Double.self, forKey: .shutterSpeed)
        iso = try container.decodeIfPresent(Int.self, forKey: .iso)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        lensId = try container.decodeIfPresent(UUID.self, forKey: .lensId)
        lensName = try container.decodeIfPresent(String.self, forKey: .lensName)
    }
}

struct Roll: Identifiable, Codable, Hashable {
    let id: UUID
    var stockId: UUID
    var cameraId: UUID?
    var status: RollStatus
    var format: FilmFormat
    var pushPull: Int?
    var shootingISO: Int?
    var frameCount: Int
    var pinCount: Int
    var totalExposures: Int
    var loadedDate: Date?
    var finishedDate: Date?
    var storageLocation: String?
    var frozenDate: Date?
    var expiryDate: Date?
    var dropOffDate: Date?
    var labName: String?
    var developedDate: Date?
    var scannedDate: Date?
    var archivedDate: Date?
    var development: DevelopmentRecord?
    var tags: [String]
    var notes: String?
    var frameMarkers: [FrameMarker]
    var scanFileNames: [String]
    var scanAlignmentOffset: Int
    /// Per-frame preview photos keyed by frame index string ("1", "2", …).
    var framePhotoFileNames: [String: String]

    var pushPullLabel: String? {
        guard let pushPull, pushPull != 0 else { return nil }
        if pushPull > 0 {
            return "Push +\(pushPull)"
        }
        return "Pull \(pushPull)"
    }

    var pushPullDisplayValue: String {
        pushPullLabel ?? "Box speed"
    }

    var storageMethod: StorageMethod {
        StorageMethod.resolved(from: storageLocation)
    }

    var isExpired: Bool {
        guard let expiryDate else { return false }
        return ExpirationDate.isExpired(expiryDate)
    }

    var isNearExpiry: Bool {
        guard let expiryDate, !isExpired else { return false }
        let end = ExpirationDate.endOfMonth(containing: expiryDate)
        guard let threshold = Calendar.current.date(byAdding: .day, value: FridgeItem.nearExpiryDays, to: Date()) else {
            return false
        }
        return end <= threshold
    }

    /// Best date to show when this roll was used or entered the pipeline.
    var historyDate: Date? {
        switch status.normalized {
        case .inFridge:
            return expiryDate
        case .inCamera:
            return loadedDate
        case .shotUndeveloped, .atLab, .developed, .scanned, .archived:
            return finishedDate ?? loadedDate ?? dropOffDate ?? developedDate ?? scannedDate ?? archivedDate
        default:
            return nil
        }
    }

    var historySummary: String {
        if let historyDate {
            return "\(DateFormatters.medium.string(from: historyDate)) · \(status.displayName)"
        }
        return status.displayName
    }

    init(
        id: UUID,
        stockId: UUID,
        cameraId: UUID?,
        status: RollStatus,
        format: FilmFormat = .format35Full,
        pushPull: Int?,
        shootingISO: Int? = nil,
        frameCount: Int,
        pinCount: Int,
        totalExposures: Int,
        loadedDate: Date?,
        finishedDate: Date?,
        storageLocation: String?,
        frozenDate: Date? = nil,
        expiryDate: Date?,
        dropOffDate: Date?,
        labName: String?,
        developedDate: Date?,
        scannedDate: Date?,
        archivedDate: Date? = nil,
        development: DevelopmentRecord? = nil,
        tags: [String] = [],
        notes: String? = nil,
        frameMarkers: [FrameMarker],
        scanFileNames: [String] = [],
        scanAlignmentOffset: Int = 0,
        framePhotoFileNames: [String: String] = [:]
    ) {
        self.id = id
        self.stockId = stockId
        self.cameraId = cameraId
        self.status = status.normalized
        self.format = format
        self.pushPull = pushPull
        self.shootingISO = shootingISO
        self.frameCount = frameCount
        self.pinCount = pinCount
        self.totalExposures = totalExposures
        self.loadedDate = loadedDate
        self.finishedDate = finishedDate
        self.storageLocation = storageLocation
        self.frozenDate = frozenDate
        self.expiryDate = expiryDate
        self.dropOffDate = dropOffDate
        self.labName = labName
        self.developedDate = developedDate
        self.scannedDate = scannedDate
        self.archivedDate = archivedDate
        self.development = development
        self.tags = tags
        self.notes = notes
        self.frameMarkers = frameMarkers
        self.scanFileNames = scanFileNames
        self.scanAlignmentOffset = scanAlignmentOffset
        self.framePhotoFileNames = framePhotoFileNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        stockId = try container.decode(UUID.self, forKey: .stockId)
        cameraId = try container.decodeIfPresent(UUID.self, forKey: .cameraId)
        let decodedStatus = try container.decode(RollStatus.self, forKey: .status)
        status = decodedStatus.normalized
        format = try container.decodeIfPresent(FilmFormat.self, forKey: .format) ?? .format35Full
        pushPull = try container.decodeIfPresent(Int.self, forKey: .pushPull)
        shootingISO = try container.decodeIfPresent(Int.self, forKey: .shootingISO)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
        pinCount = try container.decode(Int.self, forKey: .pinCount)
        totalExposures = try container.decode(Int.self, forKey: .totalExposures)
        loadedDate = try container.decodeIfPresent(Date.self, forKey: .loadedDate)
        finishedDate = try container.decodeIfPresent(Date.self, forKey: .finishedDate)
        storageLocation = try container.decodeIfPresent(String.self, forKey: .storageLocation)
        frozenDate = try container.decodeIfPresent(Date.self, forKey: .frozenDate)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        dropOffDate = try container.decodeIfPresent(Date.self, forKey: .dropOffDate)
        labName = try container.decodeIfPresent(String.self, forKey: .labName)
        developedDate = try container.decodeIfPresent(Date.self, forKey: .developedDate)
        scannedDate = try container.decodeIfPresent(Date.self, forKey: .scannedDate)
        archivedDate = try container.decodeIfPresent(Date.self, forKey: .archivedDate)
        development = try container.decodeIfPresent(DevelopmentRecord.self, forKey: .development)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        frameMarkers = try container.decode([FrameMarker].self, forKey: .frameMarkers)
        scanFileNames = try container.decodeIfPresent([String].self, forKey: .scanFileNames) ?? []
        scanAlignmentOffset = try container.decodeIfPresent(Int.self, forKey: .scanAlignmentOffset) ?? 0
        framePhotoFileNames = try container.decodeIfPresent([String: String].self, forKey: .framePhotoFileNames) ?? [:]
    }

    func framePhotoFileName(forFrame frameIndex: Int) -> String? {
        framePhotoFileNames[String(frameIndex)]
    }
}

extension Roll {
    static func migrate(_ roll: Roll) -> Roll {
        var updated = roll
        updated.status = roll.status.normalized
        updated.frameMarkers = normalizeFrameMarkerIndices(updated.frameMarkers)
        return updated
    }

    /// Ensures each pin maps to a unique frame index. Heals legacy data where every marker decoded as frame 1.
    static func normalizeFrameMarkerIndices(_ markers: [FrameMarker]) -> [FrameMarker] {
        guard !markers.isEmpty else { return markers }

        let indices = markers.map(\.frameIndex)
        let hasDuplicates = Set(indices).count != indices.count
        let allDefaultedToOne = indices.allSatisfy { $0 == 1 } && markers.count > 1

        guard hasDuplicates || allDefaultedToOne else { return markers }

        var normalized = markers.sorted { $0.timestamp < $1.timestamp }
        for i in normalized.indices {
            normalized[i].frameIndex = i + 1
        }
        return normalized
    }
}
