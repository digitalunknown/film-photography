import Foundation
import Testing
@testable import Film_Photography_App

@Suite(.serialized)
struct DataPersistenceTests {

    @Test func saveThenLoadRoundtripsRolls() throws {
        try withIsolatedStore { _ in
            let roll = sampleRoll()
            try DataPersistence.save(
                cameras: [],
                rolls: [roll],
                fridgeItems: [],
                devRecipePresets: [],
                customStocks: []
            )

            guard case .loaded(let saved, .primary) = DataPersistence.load() else {
                Issue.record("expected a loaded store")
                return
            }
            #expect(saved.rolls.map(\.id) == [roll.id])
        }
    }

    @Test func corruptPrimaryRecoversFromBackup() throws {
        try withIsolatedStore { url in
            let first = sampleRoll()
            let second = sampleRoll()
            try DataPersistence.save(
                cameras: [],
                rolls: [first],
                fridgeItems: [],
                devRecipePresets: []
            )
            try DataPersistence.save(
                cameras: [],
                rolls: [second],
                fridgeItems: [],
                devRecipePresets: []
            )

            try Data("{".utf8).write(to: url, options: .atomic)

            guard case .loaded(let saved, .backup) = DataPersistence.load() else {
                Issue.record("expected backup recovery")
                return
            }
            #expect(saved.rolls.map(\.id) == [first.id])
        }
    }

    @Test func unreadableStoreIsNotTreatedAsEmpty() throws {
        try withIsolatedStore { url in
            try Data("{".utf8).write(to: url, options: .atomic)

            guard case .unreadable = DataPersistence.load() else {
                Issue.record("corrupt JSON must not look like a first launch")
                return
            }
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try Data(contentsOf: url) == Data("{".utf8))
        }
    }

    @Test func appStoreDoesNotOverwriteAnUnreadableSave() throws {
        try withIsolatedStore { url in
            let roll = sampleRoll()
            try DataPersistence.save(
                cameras: [],
                rolls: [roll],
                fridgeItems: [],
                devRecipePresets: []
            )
            try Data("{".utf8).write(to: url, options: .atomic)
            try? FileManager.default.removeItem(at: DataPersistence.backupURL)

            let store = AppStore()

            #expect(store.persistProblem?.kind == .load)
            #expect(store.rolls.isEmpty)
            #expect(try Data(contentsOf: url) == Data("{".utf8))
        }
    }

    @Test func retryReloadsFromARepairedFile() throws {
        try withIsolatedStore { url in
            let roll = sampleRoll()
            try Data("{".utf8).write(to: url, options: .atomic)

            let store = AppStore()
            #expect(store.persistProblem?.kind == .load)

            try DataPersistence.save(
                cameras: [],
                rolls: [roll],
                fridgeItems: [],
                devRecipePresets: []
            )
            store.retryPersist()

            #expect(store.persistProblem == nil)
            #expect(store.rolls.map(\.id) == [roll.id])
        }
    }

    private func sampleRoll() -> Roll {
        Roll(
            id: UUID(),
            stockId: UUID(),
            cameraId: nil,
            status: .inFridge,
            pushPull: nil,
            frameCount: 0,
            pinCount: 0,
            totalExposures: 36,
            loadedDate: nil,
            finishedDate: nil,
            storageLocation: nil,
            expiryDate: nil,
            dropOffDate: nil,
            labName: nil,
            developedDate: nil,
            scannedDate: nil,
            frameMarkers: []
        )
    }

    private func withIsolatedStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("persist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("app-data.json")
        iCloudLibraryMirror.isDisabled = true
        defer {
            iCloudLibraryMirror.isDisabled = false
            try? FileManager.default.removeItem(at: directory)
        }
        try DataPersistence.$fileURLOverride.withValue(url) {
            try body(url)
        }
    }
}
