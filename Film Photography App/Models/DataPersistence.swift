import Foundation

struct PersistedAppData: Codable {
    static let currentVersion = 4

    var version: Int
    var cameras: [Camera]
    var rolls: [Roll]
    var fridgeItems: [FridgeItem]
    var devRecipePresets: [DevRecipePreset]

    init(
        version: Int = currentVersion,
        cameras: [Camera],
        rolls: [Roll],
        fridgeItems: [FridgeItem] = [],
        devRecipePresets: [DevRecipePreset] = []
    ) {
        self.version = version
        self.cameras = cameras
        self.rolls = rolls
        self.fridgeItems = fridgeItems
        self.devRecipePresets = devRecipePresets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        cameras = try container.decode([Camera].self, forKey: .cameras)
        rolls = try container.decode([Roll].self, forKey: .rolls)
        fridgeItems = try container.decodeIfPresent([FridgeItem].self, forKey: .fridgeItems) ?? []
        devRecipePresets = try container.decodeIfPresent([DevRecipePreset].self, forKey: .devRecipePresets) ?? []
    }
}

enum DataPersistence {
    private static let fileName = "app-data.json"

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FilmPhotographyApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    static func load() -> PersistedAppData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
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
        devRecipePresets: [DevRecipePreset]
    ) {
        let payload = PersistedAppData(
            cameras: cameras,
            rolls: rolls,
            fridgeItems: fridgeItems,
            devRecipePresets: devRecipePresets
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
