//
//  Film_Photography_AppTests.swift
//  Film Photography AppTests
//
//  Created by Piotr Osmenda on 7/7/26.
//

import Testing
import Foundation
@testable import Film_Photography_App

struct Film_Photography_AppTests {

    @Test func addAndRemoveScanFilesFromRoll() throws {
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
}
