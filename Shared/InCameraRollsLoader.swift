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

    static func loadRows(maxVisible: Int = 5) -> (rows: [InCameraRollRow], totalCount: Int) {
        let all = loadAllRows()
        if all.count <= maxVisible {
            return (all, all.count)
        }
        return (Array(all.prefix(maxVisible)), all.count)
    }

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

        let rows: [InCameraRollRow] = snapshot.rolls.compactMap { roll in
            guard roll.status == "inCamera" else { return nil }
            let stock = stockById[roll.stockId]
            let stockName = stock?.name ?? "Unknown stock"
            let manufacturer = stock?.manufacturer ?? ""
            let cameraName: String = {
                guard let cameraId = roll.cameraId else { return "No camera" }
                return cameraById[cameraId] ?? "Unknown camera"
            }()
            return InCameraRollRow(
                id: roll.id,
                stockName: stockName,
                cameraName: cameraName,
                frameCount: roll.frameCount,
                totalExposures: max(roll.totalExposures, 1),
                imageName: RollImageName.resolve(stockName: stockName, manufacturer: manufacturer)
            )
        }

        return rows.sorted {
            if $0.cameraName != $1.cameraName {
                return $0.cameraName.localizedCaseInsensitiveCompare($1.cameraName) == .orderedAscending
            }
            return $0.stockName.localizedCaseInsensitiveCompare($1.stockName) == .orderedAscending
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
    let frameCount: Int
    let totalExposures: Int
    let imageName: String?

    var exposuresLabel: String {
        "\(frameCount)/\(totalExposures)"
    }
}
