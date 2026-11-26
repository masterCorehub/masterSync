import AppKit
import Carbon.HIToolbox
@testable import NexusMasterSync
import XCTest

final class KeyComboTests: XCTestCase {
    func testLabelOrder() {
        XCTAssertEqual(KeyCombo.scanDefault.label, "⌃⌥⌘D")
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_S), flags: [.command, .shift, .option, .control], key: "s")
        XCTAssertEqual(combo?.label, "⌃⌥⇧⌘S")
    }

    func testRequiresCommandControlOrOption() {
        XCTAssertNil(KeyCombo(keyCode: UInt16(kVK_ANSI_S), flags: [.shift], key: "s"))
        XCTAssertNil(KeyCombo(keyCode: UInt16(kVK_ANSI_S), flags: [], key: "s"))
        XCTAssertNotNil(KeyCombo(keyCode: UInt16(kVK_ANSI_S), flags: [.option], key: "s"))
    }

    func testCarbonModifiers() {
        XCTAssertEqual(KeyCombo.carbonModifiers([.command]), UInt32(cmdKey))
        XCTAssertEqual(KeyCombo.carbonModifiers([.option]), UInt32(optionKey))
        XCTAssertEqual(KeyCombo.carbonModifiers([.control]), UInt32(controlKey))
        XCTAssertEqual(KeyCombo.carbonModifiers([.shift]), UInt32(shiftKey))
        XCTAssertEqual(KeyCombo.carbonModifiers([.command, .capsLock]), UInt32(cmdKey))
    }

    func testCodableRoundTrip() throws {
        let combo = try XCTUnwrap(KeyCombo(keyCode: UInt16(kVK_ANSI_K), flags: [.command, .option], key: "k"))
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo)), combo)
    }
}
