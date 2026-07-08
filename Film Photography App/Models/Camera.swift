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
    var photoData: Data?
    var quirks: [CameraQuirk]
    var repairHistory: [RepairRecord]
    var hasAttentionNeeded: Bool
    var defaultFormat: FilmFormat?
    var lensMinAperture: Double?
    var lensMaxAperture: Double?

    var displaySubtitle: String {
        "\(lensSubtitle) · \(cameraType)"
    }

    /// Subtitle for list rows — lens only; camera type is on the detail page.
    var listSubtitle: String? {
        let lens = lensSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lens.isEmpty, lens != "1", lens.count > 2 else { return nil }
        return lens
    }
}
