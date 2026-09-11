import Foundation

enum iCloudSyncStatus: Equatable {
    case syncing
    case lastSynced(Date)
    case notSyncedYet
    case unavailable
    case failed

    var line: String {
        switch self {
        case .syncing:
            "Syncing…"
        case .lastSynced(let date):
            "Last synced \(DateFormatters.synced.string(from: date))"
        case .notSyncedYet:
            "Not synced yet"
        case .unavailable:
            "iCloud unavailable — check Settings → [Apple ID] → iCloud"
        case .failed:
            "Sync failed — will retry"
        }
    }
}

enum iCloudSyncDecision: Equatable {
    case takeRemote
    case keepLocal
    case nothing
}

/// Mirrors `library.json` into the app's iCloud Drive container.
///
/// Conflict rule (v1): an empty side always yields to a side that has library
/// content. When both have content, the newest `updatedAt` wins. Equal stamps
/// keep the local copy — the on-device store is source of truth while editing.
enum iCloudLibraryMirror {
    static let containerIdentifier = "iCloud.digitalunknown.Film-Photography-App"
    static let fileName = "library.json"

    private static let enabledKey = "iCloudSync.enabled"
    private static let lastSyncedKey = "iCloudSync.lastSyncedAt"

    /// Tests set this so they never touch a real ubiquity container.
    nonisolated(unsafe) static var isDisabled = false

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncedKey) }
    }

    static var rememberedStatus: iCloudSyncStatus {
        if let lastSyncedAt { return .lastSynced(lastSyncedAt) }
        return .notSyncedYet
    }

    /// Signed into iCloud and the ubiquity container is reachable.
    static var isAvailable: Bool {
        guard !isDisabled else { return false }
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        return containerURL != nil
    }

    static var containerURL: URL? {
        guard !isDisabled else { return nil }
        return FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
    }

    static var documentURL: URL? {
        containerURL?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Empty + data → take the data. Both populated → newest `updatedAt` wins.
    static func resolve(local: PersistedAppData?, remote: PersistedAppData?) -> iCloudSyncDecision {
        let localHas = local?.hasLibraryContent == true
        let remoteHas = remote?.hasLibraryContent == true
        switch (localHas, remoteHas) {
        case (false, true):
            return .takeRemote
        case (true, false):
            return .keepLocal
        case (false, false):
            return .nothing
        case (true, true):
            let localAt = local?.syncTimestamp ?? .distantPast
            let remoteAt = remote?.syncTimestamp ?? .distantPast
            return remoteAt > localAt ? .takeRemote : .keepLocal
        }
    }

    static func fetchRemote() async throws -> PersistedAppData? {
        guard !isDisabled, let url = documentURL else { return nil }
        try await downloadIfNeeded(url)
        return try await Task.detached {
            try readCoordinated(from: url)
        }.value
    }

    static func push(_ payload: PersistedAppData) async throws {
        guard !isDisabled, isEnabled, let url = documentURL else { return }
        let encoded = try DataPersistence.encode(payload)
        try await Task.detached {
            try writeCoordinated(encoded, to: url)
        }.value
        lastSyncedAt = Date()
    }

    private static func downloadIfNeeded(_ url: URL) async throws {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        let isUbiquitous = values?.isUbiquitousItem == true
        let status = values?.ubiquitousItemDownloadingStatus
        if !fm.fileExists(atPath: url.path) && !isUbiquitous {
            return
        }
        if status == .current { return }

        do {
            try fm.startDownloadingUbiquitousItem(at: url)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileNoSuchFileError {
                return
            }
            throw error
        }

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            let next = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemDownloadingErrorKey,
            ])
            if let downloadError = next?.ubiquitousItemDownloadingError {
                throw downloadError
            }
            if next?.ubiquitousItemDownloadingStatus == .current { return }
            if fm.fileExists(atPath: url.path),
               next?.ubiquitousItemDownloadingStatus == nil {
                return
            }
        }
    }

    private static func readCoordinated(from url: URL) throws -> PersistedAppData? {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var payload: PersistedAppData?
        var readError: Error?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { newURL in
            guard FileManager.default.fileExists(atPath: newURL.path) else { return }
            do {
                payload = try DataPersistence.decode(try Data(contentsOf: newURL))
            } catch {
                readError = error
            }
        }
        if let coordError { throw coordError }
        if let readError { throw readError }
        return payload
    }

    private static func writeCoordinated(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var writeError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordError
        ) { newURL in
            do {
                try FileManager.default.createDirectory(
                    at: newURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: newURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }
}
