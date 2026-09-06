import Foundation
import Testing
@testable import Film_Photography_App

struct LibraryBackupTests {
    @Test func zipRoundtripsLibraryAndScan() throws {
        let rollId = UUID()
        let stockId = UUID()
        let lensId = UUID()
        let lens = CameraLens(
            id: lensId,
            name: "Elmarit",
            focalLength: "28mm",
            maxAperture: "f/2.8",
            notes: "",
            isPrimary: false
        )
        let camera = Camera(
            id: UUID(),
            name: "M6",
            lensSubtitle: "Elmarit",
            cameraType: "Rangefinder",
            serialNumber: nil,
            purchaseDate: nil,
            purchasePrice: nil,
            photoData: nil,
            quirks: [],
            repairHistory: [],
            hasAttentionNeeded: false,
            defaultFormat: nil,
            lensMinAperture: nil,
            lensMaxAperture: nil,
            lenses: [lens]
        )
        let marker = FrameMarker(frameIndex: 6, lensId: lensId, lensName: lens.exifModel)
        let roll = Roll(
            id: rollId,
            stockId: stockId,
            cameraId: camera.id,
            status: .scanned,
            pushPull: nil,
            frameCount: 6,
            pinCount: 1,
            totalExposures: 36,
            loadedDate: nil,
            finishedDate: nil,
            storageLocation: nil,
            expiryDate: nil,
            dropOffDate: nil,
            labName: nil,
            developedDate: nil,
            scannedDate: nil,
            frameMarkers: [marker],
            scanFileNames: ["frame-6.jpg"]
        )
        let payload = PersistedAppData(
            cameras: [camera],
            rolls: [roll],
            fridgeItems: [],
            devRecipePresets: [],
            customStocks: []
        )

        let scanDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-scan-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(rollId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
        let scanURL = scanDir.appendingPathComponent("frame-6.jpg")
        try Data("jpeg-bytes".utf8).write(to: scanURL)

        let zip = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString).zip")
        defer {
            try? FileManager.default.removeItem(at: zip)
            try? FileManager.default.removeItem(at: scanDir.deletingLastPathComponent())
        }

        try LibraryBackup.write(
            payload: payload,
            scans: [(rollId, "frame-6.jpg", scanURL)],
            to: zip
        )

        let restored = try LibraryBackup.read(from: zip)
        #expect(restored.payload.cameras.map(\.id) == [camera.id])
        #expect(restored.payload.rolls.first?.frameMarkers.first?.lensId == lensId)
        #expect(restored.payload.rolls.first?.frameMarkers.first?.lensName == lens.exifModel)
        let restoredScan = restored.scansDirectory?
            .appendingPathComponent(rollId.uuidString)
            .appendingPathComponent("frame-6.jpg")
        #expect(try Data(contentsOf: try #require(restoredScan)) == Data("jpeg-bytes".utf8))
    }

    @Test func legacyMarkerDecodesWithoutLens() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "frameIndex": 1,
          "timestamp": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let marker = try decoder.decode(FrameMarker.self, from: Data(json.utf8))
        #expect(marker.lensId == nil)
        #expect(marker.lensName == nil)
    }
}
