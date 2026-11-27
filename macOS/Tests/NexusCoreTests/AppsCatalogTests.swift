import NexusCore
@testable import NexusMasterSync
import XCTest

final class AppsCatalogTests: XCTestCase {
    private let apps = [
        AndroidApp(component: "com.google.camera/.Main", label: "Câmera"),
        AndroidApp(component: "com.whatsapp/.Home", label: "WhatsApp"),
        AndroidApp(component: "com.spotify.music/.Main", label: "Spotify"),
        AndroidApp(component: "com.nu.app/.Main", label: "Nubank"),
        AndroidApp(component: "com.google.maps/.Main", label: "Maps"),
        AndroidApp(component: "com.ifood/.Main", label: "iFood"),
    ]

    func testFilterIgnoresAccentsAndCase() {
        XCTAssertEqual(AppsCatalog.filter(apps, query: "camera").map(\.label), ["Câmera"])
        XCTAssertEqual(AppsCatalog.filter(apps, query: "SPOT").map(\.label), ["Spotify"])
        XCTAssertEqual(AppsCatalog.filter(apps, query: "  maps ").map(\.label), ["Maps"])
    }

    func testFilterEmptyQueryReturnsAll() {
        XCTAssertEqual(AppsCatalog.filter(apps, query: "").count, apps.count)
        XCTAssertEqual(AppsCatalog.filter(apps, query: "   ").count, apps.count)
    }

    func testFilterWithNoMatchReturnsNothing() {
        XCTAssertTrue(AppsCatalog.filter(apps, query: "zzz").isEmpty)
    }

    func testPinnedKeepsIdOrderAndDropsMissing() {
        let ids = ["com.spotify.music/.Main", "gone/.Old", "com.whatsapp/.Home"]
        XCTAssertEqual(AppsCatalog.pinned(apps, ids: ids).map(\.label), ["Spotify", "WhatsApp"])
    }

    func testToggledAddsAtEndAndRemoves() {
        XCTAssertEqual(AppsCatalog.toggled(["a", "b"], id: "c"), ["a", "b", "c"])
        XCTAssertEqual(AppsCatalog.toggled(["a", "b", "c"], id: "b"), ["a", "c"])
    }

    func testSidebarPinsAreFirstFive() {
        XCTAssertEqual(AppsCatalog.sidebarPins(apps).map(\.label), ["Câmera", "WhatsApp", "Spotify", "Nubank", "Maps"])
        XCTAssertEqual(AppsCatalog.sidebarPins(Array(apps.prefix(2))).count, 2)
    }
}
