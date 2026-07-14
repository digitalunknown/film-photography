import Foundation

struct FridgeItem: Identifiable, Codable, Hashable {
    let id: UUID
    var stockId: UUID
    var format: FilmFormat
    var quantity: Int
    var expiryDate: Date?

    static let nearExpiryDays = 60

    var isExpired: Bool {
        guard let expiryDate else { return false }
        return ExpirationDate.isExpired(expiryDate)
    }

    var isNearExpiry: Bool {
        guard let expiryDate, !isExpired else { return false }
        let end = ExpirationDate.endOfMonth(containing: expiryDate)
        guard let threshold = Calendar.current.date(byAdding: .day, value: Self.nearExpiryDays, to: Date()) else {
            return false
        }
        return end <= threshold
    }

    var expiryLabel: String? {
        guard let expiryDate else { return nil }
        if isExpired { return "Expired" }
        if isNearExpiry { return "Exp soon" }
        return "Exp \(DateFormatters.monthYear.string(from: expiryDate))"
    }
}
