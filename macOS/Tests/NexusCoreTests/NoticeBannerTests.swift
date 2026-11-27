@testable import NexusMasterSync
import NexusCore
import XCTest

final class NoticeBannerTests: XCTestCase {
    func testNewestFirstAndAtMostThree() {
        var queue = NoticeBannerQueue(limit: 3)
        for id in ["a", "b", "c", "d"] { queue.add(id) }
        XCTAssertEqual(queue.ids, ["d", "c", "b"])
    }

    func testSameIdUpdatesInPlaceAndMovesToTop() {
        var queue = NoticeBannerQueue(limit: 3)
        queue.add("a"); queue.add("b"); queue.add("a")
        XCTAssertEqual(queue.ids, ["a", "b"])
    }

    func testRemoveAndEmpty() {
        var queue = NoticeBannerQueue(limit: 3)
        queue.add("a"); queue.add("b")
        queue.remove("a")
        XCTAssertEqual(queue.ids, ["b"])
        queue.remove("zzz")
        queue.remove("b")
        XCTAssertTrue(queue.isEmpty)
    }

    func testStyleStoresAndFallsBackToSystem() {
        XCTAssertEqual(NoticeStyle(stored: "custom"), .custom)
        XCTAssertEqual(NoticeStyle(stored: "system"), .system)
        XCTAssertEqual(NoticeStyle(stored: nil), .system)
        XCTAssertEqual(NoticeStyle(stored: "???"), .system)
        XCTAssertEqual(NoticeStyle.custom.rawValue, "custom")
    }

    @MainActor func testCustomStyleShowsTheCornerCardAndSkipsTheSystemBanner() {
        let sync = NotificationSync()
        sync.enabled = true
        sync.hideContent = false
        var shown: [String] = []
        sync.showCustomBanner = { shown.append($0.remoteID) }
        sync.style = .system
        sync.handle(message("one"), peer: "phone")
        XCTAssertTrue(shown.isEmpty)
        sync.style = .custom
        sync.handle(message("two"), peer: "phone")
        XCTAssertEqual(shown, ["two"])
    }

    @MainActor func testQuietModeSilencesTheCustomCardToo() {
        let sync = NotificationSync()
        sync.enabled = true
        sync.hideContent = false
        sync.quiet = true
        sync.style = .custom
        var shown = 0
        sync.showCustomBanner = { _ in shown += 1 }
        sync.handle(message("x"), peer: "phone")
        XCTAssertEqual(shown, 0)
    }

    func testACardBeingRepliedToDoesNotExpire() {
        var queue = NoticeBannerQueue(limit: 3)
        queue.add("a"); queue.add("b")
        queue.beginReply("a")
        XCTAssertFalse(queue.shouldExpire("a"))
        XCTAssertTrue(queue.shouldExpire("b"))
        queue.endReply()
        XCTAssertTrue(queue.shouldExpire("a"))
    }

    func testRemovingTheCardEndsItsReply() {
        var queue = NoticeBannerQueue(limit: 3)
        queue.add("a")
        queue.beginReply("a")
        queue.remove("a")
        XCTAssertNil(queue.replyingID)
    }

    func testReplyDraftNeedsTextAndFitsTheLimit() {
        XCTAssertFalse(NoticeReplyDraft.canSend(""))
        XCTAssertFalse(NoticeReplyDraft.canSend("   \n "))
        XCTAssertTrue(NoticeReplyDraft.canSend("Já chego"))
        XCTAssertTrue(NoticeReplyDraft.canSend(String(repeating: "a", count: 1024)))
        XCTAssertFalse(NoticeReplyDraft.canSend(String(repeating: "a", count: 1025)))
        XCTAssertFalse(NoticeReplyDraft.canSend(String(repeating: "é", count: 600)))
    }

    private func message(_ id: String) -> Message {
        var message = Message("notice")
        message.id = id; message.app = "App"; message.group = "test.app"; message.at = 10
        message.name = "Título"; message.text = "texto"; message.canDismiss = true
        return message
    }
}
