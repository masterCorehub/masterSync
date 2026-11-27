import NexusCore
@testable import NexusMasterSync
import XCTest

@MainActor
final class GalleryRefreshTests: XCTestCase {
    private func media(_ ids: [Int]) -> String {
        ids.map { #"{"id":"\#($0)","name":"IMG_\#($0).jpg","mime":"image/jpeg","album":"Câmera","at":\#(1_700_000_000 + $0),"size":1000}"# }
            .joined(separator: ",")
    }

    private func page(id: String, ids: [Int], more: Bool = false) throws -> Message {
        try JSONDecoder().decode(Message.self, from: Data(#"{"type":"galleryPage","id":"\#(id)","media":[\#(media(ids))],"more":\#(more)}"#.utf8))
    }

    private func makeGallery() -> (GalleryModel, () -> String) {
        let gallery = GalleryModel()
        var lastList = ""
        gallery.send = { _, message in if message.type == "galleryList" { lastList = message.id ?? "" } }
        gallery.select("phone", advanced: true, background: false)
        return (gallery, { lastList })
    }

    func testRefreshKeepsTheListVisibleUntilTheNewOneArrives() throws {
        let (gallery, lastList) = makeGallery()
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [3, 2, 1]), from: "phone")
        XCTAssertEqual(gallery.items.map(\.id), ["3", "2", "1"])
        gallery.refresh()
        XCTAssertEqual(gallery.items.map(\.id), ["3", "2", "1"], "a lista não pode sumir enquanto atualiza")
        XCTAssertTrue(gallery.loading)
    }

    func testRefreshReplacesTheListWithTheFreshOneWithoutDuplicates() throws {
        let (gallery, lastList) = makeGallery()
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [3, 2, 1]), from: "phone")
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [5, 4, 3, 2, 1]), from: "phone")
        XCTAssertEqual(gallery.items.map(\.id), ["5", "4", "3", "2", "1"])
    }

    func testRefreshDropsPhotosThatWereDeletedOnThePhone() throws {
        let (gallery, lastList) = makeGallery()
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [3, 2, 1]), from: "phone")
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [3, 1]), from: "phone")
        XCTAssertEqual(gallery.items.map(\.id), ["3", "1"])
    }

    func testLaterPagesStillAppend() throws {
        let (gallery, lastList) = makeGallery()
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [9, 8], more: true), from: "phone")
        gallery.page()
        gallery.receive(try page(id: lastList(), ids: [7, 6]), from: "phone")
        XCTAssertEqual(gallery.items.map(\.id), ["9", "8", "7", "6"])
    }

    func testAFailedRefreshKeepsWhatWasShown() throws {
        let (gallery, lastList) = makeGallery()
        gallery.refresh()
        gallery.receive(try page(id: lastList(), ids: [2, 1]), from: "phone")
        gallery.refresh()
        // The phone never answers the second request: the old list stays, nothing is emptied.
        XCTAssertEqual(gallery.items.map(\.id), ["2", "1"])
    }

    func testStalenessRule() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(GalleryModel.isStale(lastLoad: nil, now: now, maxAge: 20))
        XCTAssertFalse(GalleryModel.isStale(lastLoad: now.addingTimeInterval(-5), now: now, maxAge: 20))
        XCTAssertTrue(GalleryModel.isStale(lastLoad: now.addingTimeInterval(-21), now: now, maxAge: 20))
    }
}
