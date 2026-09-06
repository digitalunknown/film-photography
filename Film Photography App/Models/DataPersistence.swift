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

enum DataPersistenceError: LocalizedError {
    case encodeFailed(Error)
    case writeFailed(Error)
    case verificationFailed
    case unreadable(Error)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            "Couldn't prepare your rolls for saving."
        case .writeFailed:
            "Couldn't write your rolls to disk."
        case .verificationFailed:
            "The saved file couldn't be verified."
        case .unreadable:
            "Couldn't read your saved rolls."
        }
    }
}

/// Where a successful load came from. Backup recovery should rewrite the primary file
/// so the next launch doesn't have to fall back again.
enum DataPersistenceSource {
    case primary
    case backup
}

enum DataPersistenceLoad {
    case empty
    case loaded(PersistedAppData, source: DataPersistenceSource)
    case unreadable(String)
}

enum DataPersistence {
    private static let fileName = "app-data.json"
    private static let backupName = "app-data.json.bak"
    private static let tempName = "app-data.json.tmp"

    /// Tests point this at an isolated file so they never touch the live store.
    /// Production leaves it nil and writes to the App Group container.
    nonisolated(unsafe) static var fileURLOverride: URL?

    static var fileURL: URL {
        fileURLOverride ?? AppGroupStorage.resolvedDataURL()
    }

    static var backupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
    }

    private static var tempURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(tempName)
    }

    static func load() -> DataPersistenceLoad {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            do {
                return .loaded(try decode(from: fileURL), source: .primary)
            } catch {
                if fm.fileExists(atPath: backupURL.path),
                   let recovered = try? decode(from: backupURL) {
                    return .loaded(recovered, source: .backup)
                }
                return .unreadable(DataPersistenceError.unreadable(error).localizedDescription)
            }
        }

        if fm.fileExists(atPath: backupURL.path) {
            do {
                return .loaded(try decode(from: backupURL), source: .backup)
            } catch {
                return .unreadable(DataPersistenceError.unreadable(error).localizedDescription)
            }
        }

        return .empty
    }

    static func save(
        cameras: [Camera],
        rolls: [Roll],
        fridgeItems: [FridgeItem],
        devRecipePresets: [DevRecipePreset],
        customStocks: [FilmStock] = []
    ) throws {
        let payload = PersistedAppData(
            cameras: cameras,
            rolls: rolls,
            fridgeItems: fridgeItems,
            devRecipePresets: devRecipePresets,
            customStocks: customStocks
        )
        try write(payload)
    }

    /// Moves an unreadable primary file aside instead of writing over it. A later
    /// successful save can then create a new store without destroying the last one.
    static func quarantineUnreadablePrimary() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("app-data.unreadable-\(stamp).json")
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: fileURL, to: destination)
    }

    static func encode(_ payload: PersistedAppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(payload)
        } catch {
            throw DataPersistenceError.encodeFailed(error)
        }
    }

    static func decode(_ data: Data) throws -> PersistedAppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PersistedAppData.self, from: data)
        } catch {
            throw DataPersistenceError.unreadable(error)
        }
    }

    private static func write(_ payload: PersistedAppData) throws {
        let data: Data
        do {
            data = try encode(payload)
        } catch let error as DataPersistenceError {
            throw error
        } catch {
            throw DataPersistenceError.encodeFailed(error)
        }

        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DataPersistenceError.writeFailed(error)
        }

        let temp = tempURL
        if fm.fileExists(atPath: temp.path) {
            try? fm.removeItem(at: temp)
        }

        do {
            try data.write(to: temp, options: .atomic)
            _ = try decode(from: temp)
        } catch let error as DataPersistenceError {
            try? fm.removeItem(at: temp)
            throw error
        } catch {
            try? fm.removeItem(at: temp)
            throw DataPersistenceError.writeFailed(error)
        }

        do {
            if fm.fileExists(atPath: fileURL.path) {
                // Only back up a file we can still read. Copying a corrupt primary over
                // a good backup would erase the last recoverable copy.
                if (try? decode(from: fileURL)) != nil {
                    if fm.fileExists(atPath: backupURL.path) {
                        try fm.removeItem(at: backupURL)
                    }
                    try fm.copyItem(at: fileURL, to: backupURL)
                }
                _ = try fm.replaceItemAt(fileURL, withItemAt: temp, backupItemName: nil, options: [])
            } else {
                try fm.moveItem(at: temp, to: fileURL)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw DataPersistenceError.writeFailed(error)
        }

        guard fm.fileExists(atPath: fileURL.path),
              (try? decode(from: fileURL)) != nil else {
            throw DataPersistenceError.verificationFailed
        }
    }

    private static func decode(from url: URL) throws -> PersistedAppData {
        try decode(try Data(contentsOf: url))
    }
}
