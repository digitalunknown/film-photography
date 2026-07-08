import SwiftUI

enum StockProcess: String, CaseIterable, Codable {
    case c41 = "C-41"
    case e6 = "E-6"
    case bw = "B&W"

    var label: String { rawValue }
}

enum StockCategory: String, CaseIterable, Codable {
    case all = "All"
    case colorNeg = "Color neg"
    case blackAndWhite = "B&W"
    case slide = "Slide"
}

struct FilmStock: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var iso: Int
    var process: StockProcess
    var category: StockCategory
    var notes: String
    var isDiscontinued: Bool

    var processISOText: String {
        "\(process.label) · ISO \(iso)"
    }

    var tintColor: Color {
        emulsionTint
    }

    /// Categorical emulsion tint for data visualization.
    var emulsionTint: Color {
        let upper = name.uppercased()
        if upper.contains("PORTRA") {
            return Color(hue: 0.10, saturation: 0.42, brightness: 0.82)
        }
        if upper.contains("GOLD") {
            return Color(hue: 0.13, saturation: 0.48, brightness: 0.78)
        }
        if upper.contains("HP5") {
            return Color(hue: 0.0, saturation: 0.0, brightness: 0.58)
        }
        if upper.contains("800T") || upper.contains("CINESTILL 800") {
            return Color(hue: 0.58, saturation: 0.42, brightness: 0.72)
        }
        if upper.contains("EKTA") || upper.contains("VELVIA") || upper.contains("PROVIA") {
            return Color(hue: 0.98, saturation: 0.50, brightness: 0.78)
        }
        if upper.contains("TRI-X") || upper.contains("TRIX") {
            return Color(hue: 0.0, saturation: 0.0, brightness: 0.68)
        }
        switch category {
        case .colorNeg:
            return Color(hue: 0.08, saturation: 0.35, brightness: 0.82)
        case .slide:
            return Color(hue: 0.98, saturation: 0.40, brightness: 0.80)
        case .blackAndWhite:
            return Color(hue: 0.0, saturation: 0.0, brightness: 0.62)
        case .all:
            return Color(hue: 0.08, saturation: 0.35, brightness: 0.82)
        }
    }

    /// Typographic stand-in for plate art — e.g. P400, HP5, E100.
    var shortCode: String {
        let upper = name.uppercased()
        let iso = isoFromName ?? iso

        if upper.contains("HP5") { return "HP5" }
        if upper.contains("TRI-X") || upper.contains("TRIX") { return "TX\(iso)" }
        if upper.contains("PORTRA") { return "P\(iso)" }
        if upper.contains("GOLD") { return "G\(iso)" }
        if upper.contains("EKTA") { return "E\(iso)" }
        if upper.contains("VELVIA") { return "V\(iso)" }
        if upper.contains("PROVIA") { return "PR\(iso)" }
        if upper.contains("CINE") { return "C\(iso)" }
        if upper.contains("DELTA") { return "D\(iso)" }
        if upper.contains("T-MAX") || upper.contains("TMAX") { return "TM\(iso)" }

        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
        if letters.isEmpty {
            return "F\(iso)"
        }
        return "\(letters)\(iso)"
    }

    private var isoFromName: Int? {
        let pattern = #"\d+"#
        guard let range = name.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(name[range])
    }

    var categoryFilter: StockCategory {
        switch category {
        case .all: return .colorNeg
        case .colorNeg, .blackAndWhite, .slide: return category
        }
    }
}

private struct FilmStockCatalog: Codable {
    struct Entry: Codable {
        let id: UUID
        let name: String
        let iso: Int
        let category: String
        let process: String
        let notes: String
        let isDiscontinued: Bool
    }

    let stocks: [Entry]
}

enum StockCatalog {
    static func loadStocks() -> [FilmStock] {
        guard
            let url = Bundle.main.url(forResource: "film-stocks", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(FilmStockCatalog.self, from: data)
        else {
            return []
        }

        return catalog.stocks.compactMap { entry in
            guard
                let process = StockProcess(rawValue: entry.process),
                let category = StockCategory(rawValue: entry.category)
            else { return nil }

            return FilmStock(
                id: entry.id,
                name: entry.name,
                iso: entry.iso,
                process: process,
                category: category,
                notes: entry.notes,
                isDiscontinued: entry.isDiscontinued
            )
        }
    }
}
