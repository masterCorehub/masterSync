@testable import NexusMasterSync
import XCTest

@MainActor
final class ClipboardSyncToggleTests: XCTestCase {
    func testTurningSyncOffClearsTheSwitchAndStopsAdbSync() {
        let model = NexusModel()
        model.setClipboardSync(true)
        XCTAssertTrue(model.clipboardSyncActive)
        model.setClipboardSync(false)
        XCTAssertFalse(model.clipboardEnabled)
        XCTAssertFalse(model.clipboardSyncActive)
        XCTAssertNil(model.adbClipboard.transport)
    }
}
