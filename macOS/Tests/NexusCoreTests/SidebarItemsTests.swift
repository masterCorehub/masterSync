@testable import NexusMasterSync
import XCTest

final class SidebarItemsTests: XCTestCase {
    func testMainGroupOrder() {
        XCTAssertEqual(sidebarItems(group: .main, badges: [:]).map(\.section),
                       [.overview, .conversation, .notifications, .gallery, .documents, .files, .remote, .apps])
    }

    func testComingSoonSectionsAreOnlyInSoonGroup() {
        XCTAssertEqual(sidebarItems(group: .soon, badges: [:]).map(\.section), [.calls, .sms, .webcam])
        XCTAssertTrue(Section.allCases.filter(\.isComingSoon).allSatisfy { [.calls, .sms, .webcam].contains($0) })
        XCTAssertEqual(sidebarItems(group: .footer, badges: [:]).map(\.section), [.devices, .settings])
        let listed = [SidebarGroup.main, .soon, .footer].flatMap { sidebarItems(group: $0, badges: [:]) }.map(\.section)
        XCTAssertFalse(listed.contains { $0.isComingSoon && sidebarItems(group: .main, badges: [:]).map(\.section).contains($0) })
    }

    func testClipboardIsNotListed() {
        let listed = [SidebarGroup.main, .soon, .footer].flatMap { sidebarItems(group: $0, badges: [:]) }.map(\.section)
        XCTAssertFalse(listed.contains(.clipboard))
    }

    func testBadgeOnlyWhenPositive() {
        let items = sidebarItems(group: .main, badges: [.notifications: 3, .files: 0])
        XCTAssertEqual(items.first { $0.section == .notifications }?.badge, 3)
        XCTAssertNil(items.first { $0.section == .files }?.badge)
        XCTAssertNil(items.first { $0.section == .overview }?.badge)
    }

    func testEverySectionHasTitleAndSubtitle() {
        for section in Section.allCases {
            XCTAssertFalse(section.title.isEmpty, "\(section)")
            XCTAssertFalse(section.subtitle.isEmpty, "\(section)")
            XCTAssertFalse(section.icon.isEmpty, "\(section)")
        }
        XCTAssertEqual(Section.overview.title, "Visão geral")
    }
}
