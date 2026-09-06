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

/// A glass a body can carry. Cameras used to store a single `lensSubtitle` string;
/// that still seeds the first lens on decode so existing bodies don't go empty.
struct CameraLens: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var focalLength: String
    var maxAperture: String
    var notes: String
    var isPrimary: Bool

    var specLine: String? {
        let parts = [focalLength, maxAperture]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Millimetres parsed from `focalLength` (`50mm`, `50`, `28–70mm` → first number).
    var focalLengthMillimeters: Double? {
        let normalized = focalLength.replacingOccurrences(of: ",", with: ".")
        var digits = ""
        var started = false
        for character in normalized {
            if character.isNumber || (character == "." && !digits.contains(".")) {
                digits.append(character)
                started = true
            } else if started {
                break
            }
        }
        guard let value = Double(digits), value > 0 else { return nil }
        return value
    }

    var focalLengthDisplay: String {
        let trimmed = focalLength.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    /// What EXIF `LensModel` should say: the name, plus focal / aperture when they
    /// are not already sitting in the name.
    var exifModel: String {
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let spec = specLine else { return named }
        if named.localizedCaseInsensitiveContains(spec) { return named }
        return named.isEmpty ? spec : "\(named) · \(spec)"
    }
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
    var lenses: [CameraLens]

    var primaryLens: CameraLens? {
        lenses.first(where: \.isPrimary) ?? lenses.first
    }

    var primaryLensName: String {
        let named = primaryLens?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !named.isEmpty { return named }
        return lensSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displaySubtitle: String {
        let lens = primaryLensName
        return lens.isEmpty ? cameraType : "\(lens) · \(cameraType)"
    }

    /// Subtitle for list rows — primary lens only; camera type is on the detail page.
    var listSubtitle: String? {
        let lens = primaryLensName
        guard !lens.isEmpty, lens != "1", lens.count > 2 else { return nil }
        return lens
    }

    mutating func syncPrimaryLensSubtitle() {
        let name = primaryLensName
        if !name.isEmpty { lensSubtitle = name }
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
        notes: String? = nil,
        lenses: [CameraLens] = []
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
        self.lenses = lenses
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
        let storedLenses = try container.decodeIfPresent([CameraLens].self, forKey: .lenses) ?? []
        if storedLenses.isEmpty {
            let legacy = lensSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty, legacy != "1", legacy.count > 2 {
                lenses = [
                    CameraLens(
                        id: UUID(),
                        name: legacy,
                        focalLength: "",
                        maxAperture: "",
                        notes: "",
                        isPrimary: true
                    )
                ]
            } else {
                lenses = []
            }
        } else {
            lenses = storedLenses
        }
    }
}
