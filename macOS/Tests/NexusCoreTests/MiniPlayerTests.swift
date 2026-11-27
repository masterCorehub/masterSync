@testable import NexusMasterSync
import XCTest

final class MiniPlayerTests: XCTestCase {
    func testNoMediaIsHidden() {
        XCTAssertEqual(MiniPlayerPresentation().view(hasMedia: false, track: nil), .hidden)
        var expanded = MiniPlayerPresentation()
        expanded.expanded = true
        XCTAssertEqual(expanded.view(hasMedia: false, track: "a"), .hidden)
    }

    func testMediaStartsMini() {
        XCTAssertEqual(MiniPlayerPresentation().view(hasMedia: true, track: "a"), .mini)
    }

    func testExpandAndCollapse() {
        var presentation = MiniPlayerPresentation()
        presentation.toggleExpanded()
        XCTAssertEqual(presentation.view(hasMedia: true, track: "a"), .full)
        presentation.toggleExpanded()
        XCTAssertEqual(presentation.view(hasMedia: true, track: "a"), .mini)
    }

    func testClosedStaysHiddenUntilTrackChanges() {
        var presentation = MiniPlayerPresentation()
        presentation.toggleExpanded()
        presentation.dismiss(track: "a")
        XCTAssertEqual(presentation.view(hasMedia: true, track: "a"), .hidden)
        XCTAssertEqual(presentation.view(hasMedia: true, track: "a"), .hidden)
        // A new track brings it back, collapsed.
        XCTAssertEqual(presentation.view(hasMedia: true, track: "b"), .mini)
    }

    func testMediaDisappearingHides() {
        let presentation = MiniPlayerPresentation()
        XCTAssertEqual(presentation.view(hasMedia: true, track: "a"), .mini)
        XCTAssertEqual(presentation.view(hasMedia: false, track: nil), .hidden)
    }

    func testTrackKeyIdentifiesTitleAndArtist() {
        XCTAssertNotEqual(MiniPlayerPresentation.trackKey(title: "A", artist: "X"), MiniPlayerPresentation.trackKey(title: "B", artist: "X"))
        XCTAssertEqual(MiniPlayerPresentation.trackKey(title: "A", artist: nil), MiniPlayerPresentation.trackKey(title: "A", artist: nil))
    }
}
