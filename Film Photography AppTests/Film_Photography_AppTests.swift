import Testing
import Foundation
import UIKit
@testable import Film_Photography_App

struct Film_Photography_AppTests {

    @Test func addAndRemoveScanFilesFromRoll() throws {
        iCloudLibraryMirror.isDisabled = true
        defer { iCloudLibraryMirror.isDisabled = false }

        let store = AppStore()
        store.rolls.removeAll()

        let stockId = try #require(store.stocks.first?.id)
        store.addRoll(
            stockId: stockId,
            status: .developed,
            cameraId: nil,
            exposures: 36
        )

        let rollId = try #require(store.rolls.last?.id)
        #expect(store.roll(for: rollId)?.scanFileNames.isEmpty == true)

        store.appendScans(to: rollId, fileNames: ["scan-a.jpg", "scan-b.jpg"])

        let rollAfterAdd = try #require(store.roll(for: rollId))
        #expect(rollAfterAdd.scanFileNames.count == 2)
        #expect(rollAfterAdd.status == .scanned)

        store.removeScan(from: rollId, fileName: "scan-a.jpg")

        let rollAfterRemove = try #require(store.roll(for: rollId))
        #expect(rollAfterRemove.scanFileNames == ["scan-b.jpg"])
    }

    @Test func requestDeleteRollRemovesFromStore() throws {
        iCloudLibraryMirror.isDisabled = true
        defer { iCloudLibraryMirror.isDisabled = false }

        let store = AppStore()
        store.rolls.removeAll()

        let stockId = try #require(store.stocks.first?.id)
        store.addRoll(
            stockId: stockId,
            status: .scanned,
            cameraId: nil,
            exposures: 36
        )

        let rollId = try #require(store.rolls.last?.id)
        store.requestDeleteRoll(rollId)

        #expect(store.roll(for: rollId) == nil)
        #expect(store.pendingDeletion?.roll.id == rollId)

        store.undoDelete()
        #expect(store.roll(for: rollId) != nil)
        #expect(store.pendingDeletion == nil)
    }

    @Test func pointAndShootStampsAutoOnAdvance() throws {
        iCloudLibraryMirror.isDisabled = true
        defer { iCloudLibraryMirror.isDisabled = false }

        let store = AppStore()
        store.rolls.removeAll()
        store.addCamera(
            name: "Mju II",
            lensSubtitle: "35mm",
            cameraType: "Point & shoot",
            serialNumber: nil,
            purchaseDate: nil,
            purchasePrice: nil,
            quirkNote: nil
        )
        let cameraId = try #require(store.cameras.last?.id)
        #expect(store.camera(for: cameraId)?.isPointAndShoot == true)

        let stockId = try #require(store.stocks.first?.id)
        store.addRoll(
            stockId: stockId,
            status: .inCamera,
            cameraId: cameraId,
            exposures: 36
        )
        let rollId = try #require(store.rolls.last?.id)

        store.advanceExposure(on: rollId)

        let marker = try #require(store.roll(for: rollId)?.frameMarkers.first)
        #expect(marker.aperture == ExposureScale.autoValue)
        #expect(marker.shutterSpeed == ExposureScale.autoValue)
    }

    @Test func addInventoryRollsCreatesInStockCopies() throws {
        iCloudLibraryMirror.isDisabled = true
        defer { iCloudLibraryMirror.isDisabled = false }

        let store = AppStore()
        store.rolls.removeAll()
        let stockId = try #require(store.stocks.first?.id)

        store.addInventoryRolls(
            stockId: stockId,
            quantity: 3,
            format: .format35Full,
            storage: .fridge,
            expiryDate: nil
        )

        let added = store.rolls.filter { $0.stockId == stockId && $0.status == .inFridge }
        #expect(added.count == 3)
        #expect(added.allSatisfy { $0.storageMethod == .fridge })
        #expect(added.allSatisfy { $0.cameraId == nil })
        #expect(added.allSatisfy { $0.totalExposures == FilmFormat.format35Full.defaultExposures })
    }

    @Test func widgetAddFilmDeepLinkOpensInventorySheet() {
        iCloudLibraryMirror.isDisabled = true
        defer { iCloudLibraryMirror.isDisabled = false }

        let store = AppStore()
        #expect(AppDeepLink.isAddFilm(AppDeepLink.addFilm))
        #expect(store.openAddFilm(from: AppDeepLink.addFilm))
        #expect(store.showingAddInventory)
        #expect(store.openRoll(from: AppDeepLink.addFilm) == false)
    }

    @Test func pipelineActionLabelsMatchLifecycle() {
        #expect(RollStatus.inFridge.pipelineActionLabel == "Load to Camera")
        #expect(RollStatus.inCamera.pipelineActionLabel == "Finish Roll")
        #expect(RollStatus.shotUndeveloped.pipelineActionLabel == "Send to lab")
        #expect(RollStatus.atLab.pipelineActionLabel == "Mark developed")
        #expect(RollStatus.developed.pipelineActionLabel == "Add scans")
        #expect(RollStatus.scanned.pipelineActionLabel == nil)
    }

    @Test func instrumentSansFacesAreRegistered() {
        let faces = [
            InstrumentFont.regularName,
            InstrumentFont.mediumName,
            InstrumentFont.semiBoldName,
            InstrumentFont.boldName,
            InstrumentFont.italicName,
            InstrumentFont.mediumItalicName,
            InstrumentFont.semiBoldItalicName,
            InstrumentFont.boldItalicName,
        ]
        for name in faces {
            #expect(UIFont(name: name, size: 15) != nil, "Missing face \(name)")
        }
    }
}
