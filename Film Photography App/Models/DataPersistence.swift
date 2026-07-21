import Foundation

struct PersistedAppData: Codable {
    static let currentVersion = 5

    var version: Int
    var cameras: [Camera]
    var rolls: [Roll]
    var fridgeItems: [FridgeItem]
    var devRecipePresets: [DevRecipePreset]
    var customStocks: [FilmStock]

    init(
        version: Int = currentVersion,
        cameras: [Camera],
        rolls: [Roll],
        fridgeItems: [FridgeItem] = [],
        devRecipePresets: [DevRecipePreset] = [],
        customStocks: [FilmStock] = []
    ) {
        self.version = version
        self.cameras = cameras
        self.rolls = rolls
        self.fridgeItems = fridgeItems
        self.devRecipePresets = devRecipePresets
        self.customStocks = customStocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        cameras = try container.decode([Camera].self, forKey: .cameras)
        rolls = try container.decode([Roll].self, forKey: .rolls)
        fridgeItems = try container.decodeIfPresent([FridgeItem].self, forKey: .fridgeItems) ?? []
        devRecipePresets = try container.decodeIfPresent([DevRecipePreset].self, forKey: .devRecipePresets) ?? []
        customStocks = try container.decodeIfPresent([FilmStock].self, forKey: .customStocks) ?? []
    }
}

enum DataPersistence {
    private static var fileURL: URL {
        AppGroupStorage.resolvedDataURL()
    }

    static func load() -> PersistedAppData? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistedAppData.self, from: data)
        } catch {
            return nil
        }
    }

    static func save(
        cameras: [Camera],
        rolls: [Roll],
        fridgeItems: [FridgeItem],
        devRecipePresets: [DevRecipePreset],
        customStocks: [FilmStock] = []
    ) {
        let payload = PersistedAppData(
            cameras: cameras,
            rolls: rolls,
            fridgeItems: fridgeItems,
            devRecipePresets: devRecipePresets,
            customStocks: customStocks
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Prototype: fail silently; data stays in memory for the session.
        }
    }
}
