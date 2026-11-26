@testable import NexusMasterSync
import XCTest

final class ScrcpyControlTests: XCTestCase {
    func testKeycodeBytes() {
        let home = ScrcpyControl.keycode(action: ScrcpyControl.Action.down, keycode: ScrcpyControl.Key.home)
        XCTAssertEqual(Array(home), [0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(home.count, 14)
        let enterUp = ScrcpyControl.keycode(action: ScrcpyControl.Action.up, keycode: ScrcpyControl.Key.enter, metaState: 1)
        XCTAssertEqual(Array(enterUp), [0, 1, 0, 0, 0, 66, 0, 0, 0, 0, 0, 0, 0, 1])
    }

    func testTouchDownAndUpBytes() {
        let down = ScrcpyControl.touch(action: ScrcpyControl.Action.down, x: 540, y: 1170, width: 1080, height: 2340, pressed: true)
        XCTAssertEqual(Array(down), [2, 0] + [UInt8](repeating: 0xFF, count: 8)
            + [0, 0, 2, 0x1C] + [0, 0, 4, 0x92] + [0x04, 0x38] + [0x09, 0x24] + [0xFF, 0xFF] + [0, 0, 0, 1] + [0, 0, 0, 1])
        XCTAssertEqual(down.count, 32)
        let up = ScrcpyControl.touch(action: ScrcpyControl.Action.up, x: 540, y: 1170, width: 1080, height: 2340, pressed: false)
        XCTAssertEqual(Array(up.suffix(10)), [0, 0] + [0, 0, 0, 1] + [0, 0, 0, 0])
        XCTAssertEqual(up[1], 1)
        let move = ScrcpyControl.touch(action: ScrcpyControl.Action.move, x: 1, y: 2, width: 1080, height: 2340, pressed: true)
        XCTAssertEqual(Array(move.suffix(10)), [0xFF, 0xFF] + [0, 0, 0, 0] + [0, 0, 0, 1])
    }

    func testScrollBytesAreClamped() {
        func vertical(_ value: Float) -> [UInt8] {
            Array(ScrcpyControl.scroll(x: 10, y: 20, width: 1080, height: 2340, horizontal: 0, vertical: value)[15..<17])
        }
        XCTAssertEqual(vertical(100), [0x7F, 0xFF])
        XCTAssertEqual(vertical(-100), [0x80, 0x01])
        XCTAssertEqual(vertical(1), [0x07, 0xFF])
        let message = ScrcpyControl.scroll(x: 10, y: 20, width: 1080, height: 2340, horizontal: 0, vertical: 0)
        XCTAssertEqual(message.count, 21)
        XCTAssertEqual(message[0], 3)
    }

    func testTextRules() throws {
        let text = try XCTUnwrap(ScrcpyControl.text("olá"))
        XCTAssertEqual(Array(text), [1, 0, 0, 0, 4] + Array("olá".utf8))
        XCTAssertNil(ScrcpyControl.text(""))
        XCTAssertNil(ScrcpyControl.text(String(repeating: "a", count: 301)))
        XCTAssertNotNil(ScrcpyControl.text(String(repeating: "a", count: 300)))
    }

    func testSingleByteMessages() {
        XCTAssertEqual(Array(ScrcpyControl.collapsePanels), [7])
        XCTAssertEqual(Array(ScrcpyControl.expandNotifications), [5])
        XCTAssertEqual(Array(ScrcpyControl.backOrScreenOn(action: ScrcpyControl.Action.down)), [4, 0])
    }
}
