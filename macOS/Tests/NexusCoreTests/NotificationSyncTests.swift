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

    @MainActor private func visibleSync() -> NotificationSync {
        let sync = NotificationSync()
        sync.enabled = true
        sync.hideContent = false
        return sync
    }

    @MainActor func testHiddenFixedNoticeStaysHiddenUntilItChanges() throws {
        let sync = visibleSync()
        sync.handle(notice("fixed", at: 10, canDismiss: false, text: "tocando"), peer: "phone")
        sync.hide(try XCTUnwrap(sync.notices.first))
        XCTAssertTrue(sync.notices.isEmpty)

        sync.handle(notice("fixed", at: 11, canDismiss: false, text: "tocando"), peer: "phone")
        XCTAssertTrue(sync.notices.isEmpty)

        sync.handle(notice("fixed", at: 12, canDismiss: false, text: "outra música"), peer: "phone")
        XCTAssertEqual(sync.notices.map(\.body), ["outra música"])
    }

    @MainActor func testHiddenNoticeForgottenWhenRemoved() throws {
        let sync = visibleSync()
        sync.handle(notice("fixed", at: 10, canDismiss: false), peer: "phone")
        sync.hide(try XCTUnwrap(sync.notices.first))
        var removed = Message("noticeRemoved")
        removed.id = "fixed"
        sync.handle(removed, peer: "phone")

        sync.handle(notice("fixed", at: 20, canDismiss: false), peer: "phone")
        XCTAssertEqual(sync.notices.map(\.remoteID), ["fixed"])
    }

    @MainActor func testSnapshotKeepsHiddenNoticeHidden() throws {
        let sync = visibleSync()
        sync.handle(notice("fixed", at: 10, canDismiss: false), peer: "phone")
        sync.hide(try XCTUnwrap(sync.notices.first))

        var snapshot = Message("noticeSnapshot")
        snapshot.id = Wire.id()
        snapshot.offset = 0
        snapshot.more = false
        snapshot.notices = [notice("fixed", at: 10, canDismiss: false), notice("new", at: 30)]
        sync.handle(snapshot, peer: "phone")
        XCTAssertEqual(sync.notices.map(\.remoteID), ["new"])
    }

    @MainActor func testHiddenNoticeSurvivesReconnect() throws {
        let sync = visibleSync()
        sync.handle(notice("fixed", at: 10, canDismiss: false), peer: "phone")
        sync.hide(try XCTUnwrap(sync.notices.first))
        sync.removePeer("phone")

        var snapshot = Message("noticeSnapshot")
        snapshot.id = Wire.id()
        snapshot.offset = 0
        snapshot.more = false
        snapshot.notices = [notice("fixed", at: 10, canDismiss: false)]
        sync.handle(snapshot, peer: "phone")
        XCTAssertTrue(sync.notices.isEmpty)
    }

    @MainActor func testRedactedRepostKeepsHiddenNoticeHidden() throws {
        let sync = visibleSync()
        sync.handle(notice("fixed", at: 10, canDismiss: false, text: "tocando"), peer: "phone")
        sync.hide(try XCTUnwrap(sync.notices.first))
        var locked = notice("fixed", at: 11, canDismiss: false, text: "")
        locked.name = "Notificação recebida"
        sync.handle(locked, peer: "phone")
        XCTAssertTrue(sync.notices.isEmpty)
    }

    @MainActor func testHiddenWhileRedactedStaysHiddenWhenContentArrives() throws {
        let sync = visibleSync()
        var locked = notice("fixed", at: 10, canDismiss: false, text: "")
        locked.name = "Notificação recebida"
        sync.handle(locked, peer: "phone")
        sync.hide(try XCTUnwrap(sync.notices.first))

        sync.handle(notice("fixed", at: 11, canDismiss: false, text: "tocando"), peer: "phone")
        XCTAssertTrue(sync.notices.isEmpty)
        sync.handle(notice("fixed", at: 12, canDismiss: false, text: "outra música"), peer: "phone")
        XCTAssertEqual(sync.notices.map(\.body), ["outra música"])
    }

    @MainActor func testClearAllDismissesClearableAndHidesFixed() {
        let sync = visibleSync()
        var sent: [(String, Message)] = []
        sync.send = { peer, message in sent.append((peer, message)) }
        sync.handle(notice("clear", at: 10), peer: "phone")
        sync.handle(notice("fixed", at: 20, canDismiss: false), peer: "phone")
        sync.handle(notice("elsewhere", at: 30), peer: "other")

        sync.clearAll(peer: "phone")
        XCTAssertEqual(sent.map(\.0), ["phone"])
        XCTAssertEqual(sent.map(\.1.type), ["noticeDismiss"])
        XCTAssertEqual(sent.map(\.1.id), ["clear"])
        XCTAssertEqual(Set(sync.notices.map(\.remoteID)), ["clear", "elsewhere"])
    }

    private func notice(_ id: String, at: Int64, canDismiss: Bool = true, text: String = "t") -> Message {
        var message = Message("notice")
        message.id = id
        message.app = "App"
        message.group = "test.app"
        message.at = at
        message.name = "Título"
        message.text = text
        message.canDismiss = canDismiss
        return message
    }
}
