import NexusCore
@testable import NexusMasterSync
import XCTest

final class NotificationSyncTests: XCTestCase {
    @MainActor func testSnapshotReconcilesOnlyItsPeerAndDismissWaitsForAndroid() throws {
        let sync = NotificationSync()
        sync.enabled = true
        sync.handle(notice("stale", at: 30), peer: "phone")
        sync.handle(notice("other", at: 40), peer: "other")

        var snapshot = Message("noticeSnapshot")
        snapshot.id = Wire.id()
        snapshot.offset = 0
        snapshot.more = true
        snapshot.notices = [notice("older", at: 10)]
        sync.handle(snapshot, peer: "phone")
        XCTAssertEqual(sync.notices.map(\.remoteID), ["other", "stale"])

        snapshot.offset = 1
        snapshot.more = false
        snapshot.notices = [notice("newer", at: 20)]
        sync.handle(snapshot, peer: "phone")
        XCTAssertEqual(sync.notices.map(\.remoteID), ["other", "newer", "older"])

        var command: Message?
        sync.send = { _, message in command = message }
        sync.dismiss(try XCTUnwrap(sync.notices.first { $0.remoteID == "newer" }))
        XCTAssertEqual(command?.type, "noticeDismiss")
        XCTAssertTrue(sync.notices.contains { $0.remoteID == "newer" })

        var removed = Message("noticeRemoved")
        removed.id = "newer"
        sync.handle(removed, peer: "phone")
        XCTAssertEqual(sync.notices.map(\.remoteID), ["other", "older"])
    }

    private func notice(_ id: String, at: Int64) -> Message {
        var message = Message("notice")
        message.id = id
        message.app = "App"
        message.group = "test.app"
        message.at = at
        return message
    }
}
