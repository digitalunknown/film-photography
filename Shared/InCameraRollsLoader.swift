import Foundation

/// Lightweight decode of `app-data.json` for the home-screen widget.
enum InCameraRollsLoader {
    struct Snapshot: Codable {
        var cameras: [CameraRow]
        var rolls: [RollRow]
        var customStocks: [StockRow]
    }

    struct CameraRow: Codable {
        var id: UUID
        var name: String
    }

    struct RollRow: Codable {
        var id: UUID
        var stockId: UUID
        var cameraId: UUID?
        var status: String
        var frameCount: Int
        var totalExposures: Int
    }

    struct StockRow: Codable {
        var id: UUID
        var name: String
        var manufacturer: String?
    }

    struct CatalogFile: Codable {
        var stocks: [StockRow]
    }

    private struct StockInfo {
        var name: String
        var manufacturer: String
    }

    /// Battery-widget layout: four rings on small/medium, eight on large.
    static let listLimit = 4
    static let gridLimit = 8

    static func loadRows(maxVisible: Int? = nil) -> (rows: [InCameraRollRow], totalCount: Int) {
        let all = loadAllRows()
        let limit = maxVisible ?? (all.count >= gridLimit ? gridLimit : listLimit)
        return (Array(all.prefix(limit)), all.count)
    }

    /// Same walk as My Film: pipeline sections in `activePipelineCases` order, newest
    /// first inside each section. Archived rolls stay out of the widget.
    static func loadAllRows() -> [InCameraRollRow] {
        guard
            let url = AppGroupStorage.sharedDataURL ?? Optional(AppGroupStorage.resolvedDataURL(createDirectories: false)),
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            return []
        }

        var stockById: [UUID: StockInfo] = [:]
        for stock in loadCatalogStocks() {
            stockById[stock.id] = StockInfo(name: stock.name, manufacturer: stock.manufacturer ?? "")
        }
        for stock in snapshot.customStocks {
            stockById[stock.id] = StockInfo(name: stock.name, manufacturer: stock.manufacturer ?? "Custom")
        }

        let cameraById = Dictionary(uniqueKeysWithValues: snapshot.cameras.map { ($0.id, $0.name) })
        let active = snapshot.rolls.filter { normalizeStatus($0.status) != "archived" }

        return Self.pipelineOrder.flatMap { status in
            active
                .filter { normalizeStatus($0.status) == status }
                .reversed()
                .map { roll in
                    let stock = stockById[roll.stockId]
                    let stockName = stock?.name ?? "Unknown stock"
                    let manufacturer = stock?.manufacturer ?? ""
                    let cameraName: String = {
                        guard showsCamera(normalizeStatus(roll.status)), let cameraId = roll.cameraId else {
                            return ""
                        }
                        return cameraById[cameraId] ?? ""
                    }()
                    return InCameraRollRow(
                        id: roll.id,
                        stockName: stockName,
                        cameraName: cameraName,
                        statusLabel: statusDisplayName(normalizeStatus(roll.status)),
                        frameCount: roll.frameCount,
                        totalExposures: max(roll.totalExposures, 1),
                        imageName: RollImageName.resolve(stockName: stockName, manufacturer: manufacturer)
                    )
                }
        }
    }

    /// Mirrors `RollStatus.activePipelineCases`.
    private static let pipelineOrder = [
        "inCamera", "shotUndeveloped", "inFridge", "atLab", "developed", "scanned"
    ]

    private static func normalizeStatus(_ raw: String) -> String {
        raw == "acquired" ? "inFridge" : raw
    }

    private static func showsCamera(_ status: String) -> Bool {
        status != "inFridge"
    }

    private static func statusDisplayName(_ status: String) -> String {
        switch status {
        case "inFridge": "In stock"
        case "inCamera": "In camera"
        case "shotUndeveloped": "Shot, undeveloped"
        case "atLab": "At lab"
        case "developed": "Developed"
        case "scanned": "Scanned"
        case "archived": "Archived"
        default: status
        }
    }

    private static func loadCatalogStocks() -> [StockRow] {
        guard
            let url = Bundle.main.url(forResource: "film-stocks", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else {
            return []
        }
        return catalog.stocks
    }
}

struct InCameraRollRow: Identifiable, Hashable {
    let id: UUID
    let stockName: String
    let cameraName: String
    let statusLabel: String
    let frameCount: Int
    let totalExposures: Int
    let imageName: String?

    var exposuresLabel: String {
        "\(frameCount)/\(totalExposures)"
    }

    /// Inventory has no frames shot yet, so the counter stays off, matching My Film.
    var showsExposures: Bool {
        statusLabel != "In stock"
    }
}
