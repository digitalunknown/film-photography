import Foundation
import Testing
@testable import Film_Photography_App

struct iCloudLibraryMirrorTests {

    @Test func emptyLocalTakesRemoteLibrary() {
        let remote = PersistedAppData(
            cameras: [sampleCamera()],
            rolls: [],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        #expect(iCloudLibraryMirror.resolve(local: emptyLibrary(), remote: remote) == .takeRemote)
        #expect(iCloudLibraryMirror.resolve(local: nil, remote: remote) == .takeRemote)
    }

    @Test func emptyRemoteKeepsLocalLibrary() {
        let local = PersistedAppData(
            cameras: [],
            rolls: [sampleRoll()],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        #expect(iCloudLibraryMirror.resolve(local: local, remote: emptyLibrary()) == .keepLocal)
        #expect(iCloudLibraryMirror.resolve(local: local, remote: nil) == .keepLocal)
    }

    @Test func newestTimestampWinsWhenBothHaveData() {
        let older = PersistedAppData(
            cameras: [sampleCamera(name: "Older")],
            rolls: [],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = PersistedAppData(
            cameras: [sampleCamera(name: "Newer")],
            rolls: [],
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        #expect(iCloudLibraryMirror.resolve(local: older, remote: newer) == .takeRemote)
        #expect(iCloudLibraryMirror.resolve(local: newer, remote: older) == .keepLocal)
    }

    @Test func equalTimestampsKeepLocal() {
        let stamp = Date(timeIntervalSince1970: 50)
        let local = PersistedAppData(
            cameras: [sampleCamera(name: "Local")],
            rolls: [],
            updatedAt: stamp
        )
        let remote = PersistedAppData(
            cameras: [sampleCamera(name: "Remote")],
            rolls: [],
            updatedAt: stamp
        )
        #expect(iCloudLibraryMirror.resolve(local: local, remote: remote) == .keepLocal)
    }

    @Test func bothEmptyDoesNothing() {
        #expect(iCloudLibraryMirror.resolve(local: emptyLibrary(), remote: emptyLibrary()) == .nothing)
        #expect(iCloudLibraryMirror.resolve(local: nil, remote: nil) == .nothing)
    }

    private func emptyLibrary() -> PersistedAppData {
        PersistedAppData(cameras: [], rolls: [], updatedAt: Date())
    }

    private func sampleCamera(name: String = "M6") -> Camera {
        Camera(
            id: UUID(),
            name: name,
            lensSubtitle: "50mm",
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
            lenses: []
        )
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
}
