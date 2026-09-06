import SwiftUI

enum StockProcess: String, CaseIterable, Codable {
    case c41 = "C-41"
    case e6 = "E-6"
    case bw = "B&W"
    case ecn2 = "ECN-2"
    case c41ChromogenicBW = "C-41 chromogenic B&W"
    case k14 = "K-14"

    var label: String { rawValue }
}

enum StockCategory: String, CaseIterable, Codable {
    case all = "All"
    case colorNeg = "Color neg"
    case blackAndWhite = "B&W"
    case slide = "Slide"
}

enum FilmStockType: String, CaseIterable, Codable {
    case colorNegative = "Color negative"
    case bwNegative = "B&W negative"
    case colorReversal = "Color reversal"
    case bwReversal = "B&W reversal"

    var label: String { rawValue }

    static let allTypesLabel = "All types"

    static var filterOptions: [String] {
        [allTypesLabel] + allCases.map(\.label)
    }
}

enum FilmProductionStatus: String, CaseIterable, Codable {
    case inProduction = "In production"
    case discontinued = "Discontinued"
    case paused = "Paused"
    case limitedRun = "Limited run"
    case respooledRebrand = "Respooled / rebrand"

    var label: String { rawValue }

    var isDiscontinued: Bool {
        self == .discontinued
    }
}

enum FilmPriceTier: String, CaseIterable, Codable {
    case budget = "$"
    case mid = "$$"
    case premium = "$$$"

    var label: String { rawValue }
}

enum FilmGrainCharacter: String, CaseIterable, Codable {
    case fine = "Fine"
    case moderate = "Moderate"
    case pronounced = "Pronounced"

    var label: String { rawValue }
}

struct FilmStock: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var iso: Int
    var process: StockProcess
    var category: StockCategory
    var notes: String
    var isDiscontinued: Bool

    var manufacturer: String
    var brandLine: String
    var filmType: FilmStockType
    var usableRange: String
    var pushPullTolerance: String
    var productionStatus: FilmProductionStatus
    var formatsAvailable: [String]
    var grainRMS: String?
    var grainCharacter: FilmGrainCharacter
    var yearsActive: String
    var bestFor: [String]
    var priceTier: FilmPriceTier
    /// Other box names and short codes. Search matches `name` or any alias.
    var aliases: [String]
    /// Human library blurb. Empty means the detail page hides the block entirely.
    var libraryDescription: String

    enum CodingKeys: String, CodingKey {
        case id, name, iso, process, category, notes, isDiscontinued
        case manufacturer, brandLine, filmType, usableRange, pushPullTolerance
        case productionStatus, formatsAvailable, grainRMS, grainCharacter
        case yearsActive, bestFor, priceTier, aliases
        case libraryDescription = "description"
    }

    /// Minimal stock created when the user enters film manually (not from the catalog).
    static func custom(name: String, iso: Int, id: UUID = UUID()) -> FilmStock {
        FilmStock(
            id: id,
            name: name,
            iso: iso,
            process: .c41,
            category: .all,
            notes: "",
            isDiscontinued: false,
            manufacturer: "Custom",
            brandLine: "",
            filmType: .colorNegative,
            usableRange: "ISO/ASA \(iso)",
            pushPullTolerance: "",
            productionStatus: .inProduction,
            formatsAvailable: [],
            grainRMS: nil,
            grainCharacter: .moderate,
            yearsActive: "",
            bestFor: [],
            priceTier: .mid,
            aliases: [],
            libraryDescription: ""
        )
    }

    var processISOText: String {
        "\(process.label) · ISO/ASA \(iso)"
    }

    /// Catalog ranges are often bare (`100–1600`); older copy already says `ISO`.
    var usableRangeDisplay: String {
        let trimmed = usableRange.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.localizedCaseInsensitiveContains("ISO") {
            return trimmed.replacingOccurrences(of: "ISO ", with: "ISO/ASA ")
        }
        return "ISO/ASA \(trimmed)"
    }

    var manufacturerLine: String {
        brandLine.isEmpty ? manufacturer : "\(manufacturer) · \(brandLine)"
    }

    var grainSummary: String {
        if let grainRMS, !grainRMS.isEmpty {
            return "\(grainCharacter.label) · RMS \(grainRMS)"
        }
        return grainCharacter.label
    }

    var formatsSummary: String {
        formatsAvailable.joined(separator: ", ")
    }

    var bestForSummary: String {
        Array(bestFor.prefix(3)).joined(separator: " · ")
    }

    var tintColor: Color {
        emulsionTint
    }

    /// Categorical emulsion tint for data visualization.
    var emulsionTint: Color {
        let upper = name.uppercased()
        if upper.contains("PORTRA") || upper.contains("EKTACOLOR PRO") {
            return Color(hue: 0.10, saturation: 0.42, brightness: 0.82)
        }
        if upper.contains("GOLD") || upper.contains("KODACOLOR") {
            return Color(hue: 0.13, saturation: 0.48, brightness: 0.78)
        }
        if upper.contains("HARMAN RED") || upper.contains("RED 125") {
            return Color(hue: 0.98, saturation: 0.62, brightness: 0.72)
        }
        if upper.contains("HP5") {
            return Color(hue: 0.0, saturation: 0.0, brightness: 0.58)
        }
        if upper.contains("800T") || upper.contains("CINESTILL 800") {
            return Color(hue: 0.58, saturation: 0.42, brightness: 0.72)
        }
        if upper.contains("EKTACHROME") || upper.contains("VELVIA") || upper.contains("PROVIA") {
            return Color(hue: 0.98, saturation: 0.50, brightness: 0.78)
        }
        if upper.contains("EKTAR") {
            return Color(hue: 0.02, saturation: 0.55, brightness: 0.80)
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
        if upper.contains("MONOPAN") { return "MP\(iso)" }
        if upper.contains("HARMAN RED") || upper.contains("RED 125") { return "RED" }
        if upper.contains("TRI-X") || upper.contains("TRIX") { return "TX\(iso)" }
        if upper.contains("PORTRA") || upper.contains("EKTACOLOR PRO") { return "P\(iso)" }
        if upper.contains("KODACOLOR") { return "KC\(iso)" }
        if upper.contains("GOLD") { return "G\(iso)" }
        if upper.contains("EKTACHROME") { return "E\(iso)" }
        if upper.contains("EKTAR") { return "EK\(iso)" }
        if upper.contains("VELVIA") { return "V\(iso)" }
        if upper.contains("PROVIA") { return "PR\(iso)" }
        if upper.contains("CINE") || upper.contains("VISION") { return "C\(iso)" }
        if upper.contains("DELTA") { return "D\(iso)" }
        if upper.contains("T-MAX") || upper.contains("TMAX") || upper.contains("EKTAPAN") { return "TM\(iso)" }

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

    /// Negative base color for filmstrip rendering.
    var stripBaseColor: Color {
        switch process {
        case .c41, .ecn2, .c41ChromogenicBW:
            return Color(red: 0.141, green: 0.075, blue: 0.035)
        case .bw:
            return Color(red: 0.12, green: 0.12, blue: 0.12)
        case .e6, .k14:
            return Color(red: 0.04, green: 0.04, blue: 0.05)
        }
    }

    /// Edge-print ink on the strip rails.
    var stripEdgePrintColor: Color {
        switch process {
        case .c41, .ecn2, .c41ChromogenicBW:
            return Color(red: 0.85, green: 0.62, blue: 0.28)
        case .bw:
            return Color(red: 0.55, green: 0.55, blue: 0.55)
        case .e6, .k14:
            return Color(red: 0.45, green: 0.48, blue: 0.52)
        }
    }

    var stripEdgeLabel: String {
        name.uppercased()
    }

    static let allBrandsLabel = "All"

    /// Manufacturer brand for filters and plate art.
    var brand: String { manufacturer }

    /// Brand accent for library filter chips, so a manufacturer is recognisable at a
    /// glance. Sits outside the five-colour palette on purpose — these are the brands'
    /// own colours. `nil` falls back to the neutral chip style used by type filters.
    /// Each sits close to the manufacturer's own identity colour, kept bright enough to
    /// hold its chroma once it is washed over the dark chip surface.
    nonisolated static func brandFilterTint(for brand: String) -> Color? {
        switch brand {
        case "Kodak":
            // Kodak yellow, #FFB81C.
            return Color(red: 1.00, green: 0.72, blue: 0.11)
        case "Fujifilm":
            // Fujifilm green, #009A44, lifted for a dark ground.
            return Color(red: 0.04, green: 0.80, blue: 0.42)
        case "Ilford":
            return Color(red: 0.88, green: 0.89, blue: 0.92)
        case "Lomography":
            // Lomography red, #E30613, lifted for a dark ground.
            return Color(red: 0.95, green: 0.20, blue: 0.18)
        case "CineStill":
            return Color(red: 0.68, green: 0.28, blue: 0.96)
        default:
            return nil
        }
    }

    /// Brands in the catalog, ordered by stock count (most to least).
    static func brandsByCount(in stocks: [FilmStock]) -> [String] {
        let grouped = Dictionary(grouping: stocks, by: \.brand)
        return grouped.keys
            .filter { $0 != "Custom" }
            .sorted { lhs, rhs in
                let leftCount = grouped[lhs]?.count ?? 0
                let rightCount = grouped[rhs]?.count ?? 0
                if leftCount != rightCount { return leftCount > rightCount }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    /// Asset catalog roll canister art, keyed by stock then manufacturer.
    var rollImageName: String? {
        let upper = name.uppercased()

        if upper.contains("BERGGER") || upper.contains("PANCRO") { return "roll_bergger_pancro" }
        if upper.contains("STREETPAN") || manufacturer == "JCH" { return "roll_jch_streetpan" }
        if upper.contains("KOSMO") { return "roll_kosmo_foto_mono" }
        if upper.contains("OPTIMONO") || manufacturer == "Optikoldschool" { return "roll_optimono" }
        if upper.contains("WASHI") { return "roll_film_washi" }
        if upper.contains("SHANGHAI") || upper.contains("GP3") { return "roll_shanghai_gp3" }
        if upper.contains("ARISTA") { return "roll_arista_edu_ultra" }
        if upper.contains("ULTRAFINE") { return "roll_ultrafine_extreme" }
        if upper.contains("EFKE") { return "roll_efke_kb25" }
        if upper.contains("FOMAPAN") || manufacturer == "Foma" { return "roll_fomapan" }
        if upper.contains("FERRANIA") || manufacturer == "Ferrania" { return "roll_ferrania" }
        if upper.contains("ORWO") || manufacturer == "ORWO" { return "roll_orwo" }
        if upper.contains("ADOX") || manufacturer == "Adox" { return "roll_adox" }
        if upper.contains("HARMAN") || manufacturer == "Harman" { return "roll_harman" }

        if manufacturer == "CineStill" || upper.contains("CINESTILL") {
            if upper.contains("BWXX") || upper.contains("BW XX") { return nil }
            if upper.contains("800T") || upper.contains("800 T") { return "roll_cinestill_800t" }
            if upper.contains("400D") || upper.contains("400 D") { return "roll_cinestill_400d" }
            if upper.contains("50D") || upper.contains("50 D") { return "roll_cinestill_50d" }
            return "roll_cinestill_400d"
        }

        switch manufacturer {
        case "Kodak": return "roll_kodak"
        case "Fujifilm": return "roll_fujifilm"
        case "Ilford": return "roll_ilford"
        case "Rollei": return "roll_rollei"
        case "Agfa": return "roll_agfa"
        case "Lomography": return "roll_lomography"
        case "Konica": return "roll_konica_centuria"
        case "Leica": return "roll_leica"
        default: return nil
        }
    }
}

extension FilmStock {
    /// Older persisted custom stocks omit `aliases`; treat a missing key as none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iso = try container.decode(Int.self, forKey: .iso)
        process = try container.decode(StockProcess.self, forKey: .process)
        category = try container.decode(StockCategory.self, forKey: .category)
        notes = try container.decode(String.self, forKey: .notes)
        isDiscontinued = try container.decode(Bool.self, forKey: .isDiscontinued)
        manufacturer = try container.decode(String.self, forKey: .manufacturer)
        brandLine = try container.decode(String.self, forKey: .brandLine)
        filmType = try container.decode(FilmStockType.self, forKey: .filmType)
        usableRange = try container.decode(String.self, forKey: .usableRange)
        pushPullTolerance = try container.decode(String.self, forKey: .pushPullTolerance)
        productionStatus = try container.decode(FilmProductionStatus.self, forKey: .productionStatus)
        formatsAvailable = try container.decode([String].self, forKey: .formatsAvailable)
        grainRMS = try container.decodeIfPresent(String.self, forKey: .grainRMS)
        grainCharacter = try container.decode(FilmGrainCharacter.self, forKey: .grainCharacter)
        yearsActive = try container.decode(String.self, forKey: .yearsActive)
        bestFor = try container.decode([String].self, forKey: .bestFor)
        priceTier = try container.decode(FilmPriceTier.self, forKey: .priceTier)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        libraryDescription = try container.decodeIfPresent(String.self, forKey: .libraryDescription) ?? ""
    }

    /// Case-insensitive match against the picker name or any box-name alias.
    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(query) { return true }
        return aliases.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Other box name for a dual-packaged emulsion (Portra ↔ Ektacolor Pro, T-Max ↔ Ektapan).
    /// Short codes and names already inside `name` stay searchable but do not get a subtitle.
    var alsoSoldAs: String? {
        let needles = ["EKTACOLOR PRO", "EKTAPAN"]
        let matches = aliases.filter { alias in
            let upper = alias.uppercased()
            return needles.contains { upper.contains($0) }
                && !name.localizedCaseInsensitiveContains(alias)
        }
        return matches.min(by: { $0.count < $1.count })
    }

    var alsoSoldAsLine: String? {
        alsoSoldAs.map { "Also sold as \($0)" }
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
        let manufacturer: String
        let brandLine: String
        let filmType: String
        let usableRange: String
        let pushPullTolerance: String
        let productionStatus: String
        let formatsAvailable: [String]
        let grainRMS: String?
        let grainCharacter: String
        let yearsActive: String
        let bestFor: [String]
        let priceTier: String
        let aliases: [String]?
        let description: String?
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
                let category = StockCategory(rawValue: entry.category),
                let filmType = FilmStockType(rawValue: entry.filmType),
                let productionStatus = FilmProductionStatus(rawValue: entry.productionStatus),
                let grainCharacter = FilmGrainCharacter(rawValue: entry.grainCharacter),
                let priceTier = FilmPriceTier(rawValue: entry.priceTier)
            else { return nil }

            return FilmStock(
                id: entry.id,
                name: entry.name,
                iso: entry.iso,
                process: process,
                category: category,
                notes: entry.notes,
                isDiscontinued: productionStatus.isDiscontinued || entry.isDiscontinued,
                manufacturer: entry.manufacturer,
                brandLine: entry.brandLine,
                filmType: filmType,
                usableRange: entry.usableRange,
                pushPullTolerance: entry.pushPullTolerance,
                productionStatus: productionStatus,
                formatsAvailable: entry.formatsAvailable,
                grainRMS: entry.grainRMS,
                grainCharacter: grainCharacter,
                yearsActive: entry.yearsActive,
                bestFor: Array(entry.bestFor.prefix(3)),
                priceTier: priceTier,
                aliases: entry.aliases ?? [],
                libraryDescription: entry.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }
}
