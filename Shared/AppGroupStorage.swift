import Foundation

enum AppGroupStorage {
    static let appGroupIdentifier = "group.digitalunknown.Film-Photography-App"
    static let widgetKind = "InCameraRollsWidget"

    private static let directoryName = "FilmPhotographyApp"
    private static let fileName = "app-data.json"

    /// Shared App Group location for `app-data.json`.
    static var sharedDataURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        let directory = container.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    /// Pre-App-Group path used by older app versions.
    static var legacyDataURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Resolves the file to read/write, migrating from the legacy sandbox path once if needed.
    static func resolvedDataURL(createDirectories: Bool = true) -> URL {
        if let shared = sharedDataURL {
            if createDirectories {
                let directory = shared.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            migrateLegacyDataIfNeeded(to: shared)
            return shared
        }
        // Fallback when the App Group container is unavailable (e.g. misconfigured entitlements).
        let legacyDirectory = legacyDataURL.deletingLastPathComponent()
        if createDirectories {
            try? FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        }
        return legacyDataURL
    }

    private static func migrateLegacyDataIfNeeded(to sharedURL: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: sharedURL.path) else { return }
        let legacy = legacyDataURL
        guard fm.fileExists(atPath: legacy.path) else { return }
        try? fm.copyItem(at: legacy, to: sharedURL)
    }
}
