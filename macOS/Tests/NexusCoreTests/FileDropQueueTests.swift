import Foundation
import NexusCore
import XCTest
@testable import NexusMasterSync

final class FileDropQueueTests: XCTestCase {
    @MainActor
    func testDropBatchWaitsForConfirmationBeforeOfferingNextFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("Primeiro.txt")
        let second = folder.appendingPathComponent("Segundo.txt")
        try Data("primeiro".utf8).write(to: first)
        try Data("segundo".utf8).write(to: second)
        let peer = Wire.id()
        let firstOffer = expectation(description: "first offer")
        let secondOffer = expectation(description: "second offer")
        var offers: [Message] = []
        let transfers = FileTransfers(storage: folder.appendingPathComponent("Inbox")) { recipient, message in
            XCTAssertEqual(recipient, peer)
            guard message.type == "fileOffer" else { return }
            offers.append(message)
            (offers.count == 1 ? firstOffer : secondOffer).fulfill()
        }
        transfers.allow(peer)
        XCTAssertTrue(transfers.offerBatch([first, second], to: peer))
        await fulfillment(of: [firstOffer], timeout: 5)
        XCTAssertEqual(offers.map(\.name), [first.lastPathComponent])
        XCTAssertEqual(transfers.queued[peer], [second])

        var complete = Message("fileComplete")
        complete.id = offers.first?.id
        transfers.handle(complete, peer: peer)

        await fulfillment(of: [secondOffer], timeout: 5)
        XCTAssertEqual(offers.map(\.name), [first.lastPathComponent, second.lastPathComponent])
        XCTAssertEqual(transfers.sent.map(\.url), [first])
    }
}
