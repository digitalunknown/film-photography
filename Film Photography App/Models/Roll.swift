import Foundation

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

    static var activePipelineCases: [RollStatus] {
        pipelineCases
    }

    var displayName: String {
        switch self {
        case .acquired, .inFridge: "In fridge"
        case .inCamera: "In camera"
        case .shotUndeveloped: "Shot, undeveloped"
        case .atLab: "At lab"
        case .developed: "Developed"
        case .scanned: "Scanned"
        case .archived: "Archived"
        }
    }

    var sectionTitle: String {
        switch self {
        case .acquired, .inFridge: "In fridge"
        case .inCamera: "In camera"
        case .shotUndeveloped: "Waiting to develop"
        case .atLab: "At lab"
        case .developed: "Developed"
        case .scanned: "Ready to import"
        case .archived: "Archived"
        }
    }

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

    /// Label for the action that advances from this status to the next.
    var pipelineActionLabel: String? {
        switch self {
        case .acquired, .inFridge: "Load in camera"
        case .inCamera: "Mark finished"
        case .shotUndeveloped: "Drop at lab"
        case .atLab: "Mark developed"
        case .developed: "Scans received"
        case .scanned: "Import scans"
        case .archived: nil
        }
    }

    var normalized: RollStatus {
        self == .acquired ? .inFridge : self
    }
}

struct FrameMarker: Identifiable, Codable, Hashable {
    let id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var aperture: Double?
    var shutterSpeed: Double?
    var notes: String?
    var tags: [String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double = 0,
        longitude: Double = 0,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        notes: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.notes = notes
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        aperture = try container.decodeIfPresent(Double.self, forKey: .aperture)
        shutterSpeed = try container.decodeIfPresent(Double.self, forKey: .shutterSpeed)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

struct Roll: Identifiable, Codable, Hashable {
    let id: UUID
    var shortId: String
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

    var pushPullLabel: String? {
        guard let pushPull, pushPull != 0 else { return nil }
        let sign = pushPull > 0 ? "+" : ""
        return "Pushed \(sign)\(pushPull)"
    }

    var isExpired: Bool {
        guard let expiryDate else { return false }
        return Calendar.current.startOfDay(for: expiryDate) < Calendar.current.startOfDay(for: Date())
    }

    var isNearExpiry: Bool {
        guard let expiryDate, !isExpired else { return false }
        guard let threshold = Calendar.current.date(byAdding: .day, value: FridgeItem.nearExpiryDays, to: Date()) else {
            return false
        }
        return expiryDate <= threshold
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
        shortId: String,
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
        expiryDate: Date?,
        dropOffDate: Date?,
        labName: String?,
        developedDate: Date?,
        scannedDate: Date?,
        archivedDate: Date? = nil,
        development: DevelopmentRecord? = nil,
        tags: [String] = [],
        notes: String? = nil,
        frameMarkers: [FrameMarker]
    ) {
        self.id = id
        self.shortId = shortId
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        shortId = try container.decode(String.self, forKey: .shortId)
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
    }
}

extension Roll {
    static func migrate(_ roll: Roll) -> Roll {
        var updated = roll
        updated.status = roll.status.normalized
        return updated
    }
}
