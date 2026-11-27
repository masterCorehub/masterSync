@testable import NexusMasterSync
import SwiftUI
import XCTest

@MainActor
final class MenuBarSummaryTests: XCTestCase {
    func testLabelShowsBatteryAndUnreadCount() {
        XCTAssertEqual(MenuBarSummary.labelText(battery: 82, unread: 0), "82%")
        XCTAssertEqual(MenuBarSummary.labelText(battery: 82, unread: 3), "82% · 3")
        XCTAssertEqual(MenuBarSummary.labelText(battery: nil, unread: 2), "2")
        XCTAssertNil(MenuBarSummary.labelText(battery: nil, unread: 0))
    }

    func testUnreadCapsAtNinetyNinePlus() {
        XCTAssertEqual(MenuBarSummary.labelText(battery: nil, unread: 250), "99+")
        XCTAssertEqual(MenuBarSummary.unread(notices: 4, sms: 3), 7)
        XCTAssertEqual(MenuBarSummary.unread(notices: 0, sms: 0), 0)
    }

    func testPreviewKeepsNewestFirstAndLimits() {
        let now = Date()
        let items = (0..<6).map { (id: "n\($0)", date: now.addingTimeInterval(Double($0))) }
        XCTAssertEqual(MenuBarSummary.preview(items, limit: 3).map(\.id), ["n5", "n4", "n3"])
        XCTAssertTrue(MenuBarSummary.preview([(id: String, date: Date)](), limit: 3).isEmpty)
    }

    func testPanelRendersConnectedAndDisconnected() throws {
        let model = NexusModel()
        let shell = ShellRenderTests()
        for scheme in [ColorScheme.dark, .light] {
            _ = try shell.render(MenuBarPanel(model: model, open: { _ in }, quit: {}),
                                 name: "barra-de-menu", scheme: scheme, width: 360, height: 720)
        }
    }
}
