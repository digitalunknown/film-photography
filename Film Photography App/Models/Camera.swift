import Foundation

struct CameraQuirk: Identifiable, Codable, Hashable {
    let id: UUID
    var note: String
}

struct RepairRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var description: String
}

struct Camera: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var lensSubtitle: String
    var cameraType: String
    var serialNumber: String?
    var purchaseDate: Date?
    var purchasePrice: Double?
    var purchaseCurrency: String
    var photoData: Data?
    var quirks: [CameraQuirk]
    var repairHistory: [RepairRecord]
    var hasAttentionNeeded: Bool
    var defaultFormat: FilmFormat?
    var lensMinAperture: Double?
    var lensMaxAperture: Double?
    var notes: String?

    var displaySubtitle: String {
        "\(lensSubtitle) · \(cameraType)"
    }

    /// Subtitle for list rows — lens only; camera type is on the detail page.
    var listSubtitle: String? {
        let lens = lensSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lens.isEmpty, lens != "1", lens.count > 2 else { return nil }
        return lens
    }

    init(
        id: UUID,
        name: String,
        lensSubtitle: String,
        cameraType: String,
        serialNumber: String?,
        purchaseDate: Date?,
        purchasePrice: Double?,
        purchaseCurrency: String = Locale.current.currency?.identifier ?? "USD",
        photoData: Data?,
        quirks: [CameraQuirk],
        repairHistory: [RepairRecord],
        hasAttentionNeeded: Bool,
        defaultFormat: FilmFormat?,
        lensMinAperture: Double?,
        lensMaxAperture: Double?,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lensSubtitle = lensSubtitle
        self.cameraType = cameraType
        self.serialNumber = serialNumber
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.purchaseCurrency = purchaseCurrency
        self.photoData = photoData
        self.quirks = quirks
        self.repairHistory = repairHistory
        self.hasAttentionNeeded = hasAttentionNeeded
        self.defaultFormat = defaultFormat
        self.lensMinAperture = lensMinAperture
        self.lensMaxAperture = lensMaxAperture
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lensSubtitle = try container.decode(String.self, forKey: .lensSubtitle)
        cameraType = try container.decode(String.self, forKey: .cameraType)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
        purchasePrice = try container.decodeIfPresent(Double.self, forKey: .purchasePrice)
        purchaseCurrency = try container.decodeIfPresent(String.self, forKey: .purchaseCurrency)
            ?? Locale.current.currency?.identifier
            ?? "USD"
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        quirks = try container.decodeIfPresent([CameraQuirk].self, forKey: .quirks) ?? []
        repairHistory = try container.decodeIfPresent([RepairRecord].self, forKey: .repairHistory) ?? []
        hasAttentionNeeded = try container.decodeIfPresent(Bool.self, forKey: .hasAttentionNeeded) ?? false
        defaultFormat = try container.decodeIfPresent(FilmFormat.self, forKey: .defaultFormat)
        lensMinAperture = try container.decodeIfPresent(Double.self, forKey: .lensMinAperture)
        lensMaxAperture = try container.decodeIfPresent(Double.self, forKey: .lensMaxAperture)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}
