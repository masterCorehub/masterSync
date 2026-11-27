import NexusCore
@testable import NexusMasterSync
import XCTest

final class GalleryLayoutTests: XCTestCase {
    private func entry(_ id: String, mime: String = "image/jpeg", album: String = "Câmera", at: Int64 = 1_700_000_000, size: Int64 = 1000) -> MediaEntry {
        // MediaEntry has no public initializer; the app builds it from the phone's JSON.
        let json = #"{"id":"\#(id)","name":"IMG_\#(id).jpg","mime":"\#(mime)","album":"\#(album)","at":\#(at),"size":\#(size)}"#
        return try! JSONDecoder().decode(MediaEntry.self, from: Data(json.utf8))
    }

    private func makeAlbums(_ pairs: [(String, String)]) -> [MediaAlbum] {
        pairs.map { try! JSONDecoder().decode(MediaAlbum.self, from: Data(#"{"id":"\#($0.0)","name":"\#($0.1)"}"#.utf8)) }
    }

    // MARK: Tabs

    func testTabFollowsTheFilters() {
        XCTAssertEqual(GalleryTab.current(mediaType: "", albumID: "", screenshotsAlbumID: "9", favoritesOnly: false), .all)
        XCTAssertEqual(GalleryTab.current(mediaType: "image", albumID: "", screenshotsAlbumID: "9", favoritesOnly: false), .photos)
        XCTAssertEqual(GalleryTab.current(mediaType: "video", albumID: "", screenshotsAlbumID: "9", favoritesOnly: false), .videos)
        XCTAssertEqual(GalleryTab.current(mediaType: "", albumID: "9", screenshotsAlbumID: "9", favoritesOnly: false), .screenshots)
        XCTAssertEqual(GalleryTab.current(mediaType: "image", albumID: "", screenshotsAlbumID: "9", favoritesOnly: true), .favorites)
    }

    func testAnotherAlbumIsNotTheScreenshotsTab() {
        XCTAssertEqual(GalleryTab.current(mediaType: "", albumID: "4", screenshotsAlbumID: "9", favoritesOnly: false), .all)
        XCTAssertEqual(GalleryTab.current(mediaType: "", albumID: "", screenshotsAlbumID: nil, favoritesOnly: false), .all)
    }

    func testScreenshotsAlbumIsFoundByName() {
        let albums = makeAlbums([("1", "Câmera"), ("2", "Screenshots"), ("3", "WhatsApp")])
        XCTAssertEqual(GalleryTab.screenshotsAlbumID(in: albums), "2")
        XCTAssertEqual(GalleryTab.screenshotsAlbumID(in: makeAlbums([("7", "Capturas de tela")])), "7")
        XCTAssertNil(GalleryTab.screenshotsAlbumID(in: makeAlbums([("1", "Câmera")])))
    }

    // MARK: Text

    func testItemCountText() {
        XCTAssertEqual(GalleryFormat.items(0), "nenhum item")
        XCTAssertEqual(GalleryFormat.items(1), "1 item")
        XCTAssertEqual(GalleryFormat.items(26), "26 itens")
    }

    func testSubtitleMarksPartialLists() {
        XCTAssertEqual(GalleryFormat.subtitle(count: 26, more: false), "26 itens")
        XCTAssertEqual(GalleryFormat.subtitle(count: 24, more: true), "24 itens carregados")
        XCTAssertEqual(GalleryFormat.subtitle(count: 0, more: false), "Fotos e vídeos do celular")
    }

    func testTabCountShowsPlusWhenMoreExist() {
        XCTAssertEqual(GalleryFormat.tabCount(26, more: false), "26")
        XCTAssertEqual(GalleryFormat.tabCount(24, more: true), "24+")
    }

    func testByteSizeText() {
        XCTAssertEqual(GalleryFormat.size(2_400_000), "2,4 MB")
        XCTAssertEqual(GalleryFormat.size(840_000), "840 KB")
        XCTAssertEqual(GalleryFormat.size(0), "—")
    }

    // MARK: Selection

    func testToggleAddsAndRemoves() {
        var selection = GallerySelection()
        selection.toggle("a")
        XCTAssertTrue(selection.contains("a"))
        selection.toggle("a")
        XCTAssertFalse(selection.contains("a"))
        XCTAssertTrue(selection.isEmpty)
    }

    func testSelectingAGroupSelectsAllAndSecondTapClearsIt() {
        var selection = GallerySelection()
        selection.toggle("x")
        selection.toggleGroup(["a", "b", "c"])
        XCTAssertEqual(selection.count, 4)
        XCTAssertTrue(selection.isGroupSelected(["a", "b", "c"]))
        selection.toggleGroup(["a", "b", "c"])
        XCTAssertEqual(selection.count, 1)
        XCTAssertFalse(selection.isGroupSelected(["a", "b", "c"]))
    }

    func testEmptyGroupIsNeverSelected() {
        XCTAssertFalse(GallerySelection().isGroupSelected([]))
    }

    func testPruneDropsItemsThatLeftTheList() {
        var selection = GallerySelection()
        selection.toggleGroup(["a", "b", "c"])
        selection.prune(keeping: ["b", "c", "d"])
        XCTAssertEqual(selection.count, 2)
        XCTAssertFalse(selection.contains("a"))
    }

    // MARK: Zoom

    func testZoomStepsStayInRange() {
        XCTAssertEqual(GalleryZoom.clamped(-3), 0)
        XCTAssertEqual(GalleryZoom.clamped(9), GalleryZoom.minimumTile.count - 1)
        XCTAssertLessThan(GalleryZoom.minimumTile[0], GalleryZoom.minimumTile[1])
        XCTAssertLessThan(GalleryZoom.minimumTile[1], GalleryZoom.minimumTile[2])
    }

    // MARK: Viewer

    func testNeighboursStopAtTheEnds() {
        let items = [entry("1"), entry("2"), entry("3")]
        XCTAssertNil(GalleryNavigation.neighbour(of: "1", in: items, step: -1))
        XCTAssertEqual(GalleryNavigation.neighbour(of: "1", in: items, step: 1)?.id, "2")
        XCTAssertEqual(GalleryNavigation.neighbour(of: "3", in: items, step: -1)?.id, "2")
        XCTAssertNil(GalleryNavigation.neighbour(of: "3", in: items, step: 1))
        XCTAssertNil(GalleryNavigation.neighbour(of: "missing", in: items, step: 1))
    }

    func testPositionText() {
        let items = [entry("1"), entry("2"), entry("3")]
        XCTAssertEqual(GalleryNavigation.position(of: "2", in: items), "2 de 3")
        XCTAssertNil(GalleryNavigation.position(of: "9", in: items))
    }

    // MARK: Day headings

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testTodayAndYesterdayKeepTheirNamesAndShowTheShortDate() {
        let now = date(2025, 11, 26)
        XCTAssertEqual(GalleryFormat.dayHeading(date(2025, 11, 26), now: now, calendar: calendar).title, "Hoje")
        XCTAssertEqual(GalleryFormat.dayHeading(date(2025, 11, 26), now: now, calendar: calendar).detail, "26 nov")
        XCTAssertEqual(GalleryFormat.dayHeading(date(2025, 11, 25), now: now, calendar: calendar).title, "Ontem")
    }

    func testThisWeekUsesTheWeekdayName() {
        let now = date(2025, 11, 26)
        let heading = GalleryFormat.dayHeading(date(2025, 11, 24), now: now, calendar: calendar)
        XCTAssertEqual(heading.title, "Segunda")
        XCTAssertEqual(heading.detail, "24 nov")
    }

    func testOlderDaysUseTheFullDateAndNoRepeatedDetail() {
        let now = date(2025, 11, 26)
        let older = GalleryFormat.dayHeading(date(2025, 11, 10), now: now, calendar: calendar)
        XCTAssertEqual(older.title, "10 de novembro")
        XCTAssertNil(older.detail)
        let lastYear = GalleryFormat.dayHeading(date(2024, 12, 31), now: now, calendar: calendar)
        XCTAssertEqual(lastYear.title, "31 de dezembro de 2024")
    }
}

