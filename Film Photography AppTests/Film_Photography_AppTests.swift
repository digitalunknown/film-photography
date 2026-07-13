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

    @Test func addAndRemoveScansFromRoll() throws {
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
        #expect(store.roll(for: rollId)?.scans.isEmpty == true)

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        store.addScans([imageData, imageData], to: rollId)

        let rollAfterAdd = try #require(store.roll(for: rollId))
        #expect(rollAfterAdd.scans.count == 2)
        #expect(rollAfterAdd.status == .scanned)

        let scanId = try #require(rollAfterAdd.scans.first?.id)
        store.removeScan(scanId, from: rollId)

        let rollAfterRemove = try #require(store.roll(for: rollId))
        #expect(rollAfterRemove.scans.count == 1)
        #expect(rollAfterRemove.scans.contains { $0.id == scanId } == false)
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
