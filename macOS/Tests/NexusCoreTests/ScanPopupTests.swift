@testable import NexusMasterSync
import XCTest

final class ScanPopupTests: XCTestCase {
    private func progress(_ id: String, scan: Bool = true, sending: Bool = false, size: Int64 = 1000, offset: Int64 = 0,
                          verifying: Bool = false) -> FileTransfers.Progress {
        FileTransfers.Progress(id: id, name: "Digitalização \(id).jpg", peer: "p", sending: sending, size: size, offset: offset,
                               verifying: verifying, scan: scan)
    }

    func testNothingToShowWithoutAScanDownload() {
        XCTAssertNil(ScanPopup.content(for: []))
        XCTAssertNil(ScanPopup.content(for: [progress("1", scan: false)]))
        XCTAssertNil(ScanPopup.content(for: [progress("1", sending: true)]))
    }

    func testOneScanShowsItsProgress() throws {
        let content = try XCTUnwrap(ScanPopup.content(for: [progress("1", size: 2000, offset: 500)]))
        XCTAssertEqual(content.title, "Baixando a digitalização…")
        XCTAssertEqual(content.fraction, 0.25, accuracy: 0.0001)
        XCTAssertFalse(content.verifying)
    }

    func testSeveralPagesAreCombined() throws {
        let content = try XCTUnwrap(ScanPopup.content(for: [progress("1", size: 1000, offset: 1000), progress("2", size: 1000, offset: 0)]))
        XCTAssertEqual(content.title, "Baixando 2 digitalizações…")
        XCTAssertEqual(content.fraction, 0.5, accuracy: 0.0001)
    }

    func testOtherTransfersAreIgnoredWhenCombining() throws {
        let content = try XCTUnwrap(ScanPopup.content(for: [progress("1", size: 1000, offset: 100), progress("2", scan: false, size: 10, offset: 10)]))
        XCTAssertEqual(content.fraction, 0.1, accuracy: 0.0001)
        XCTAssertEqual(content.title, "Baixando a digitalização…")
    }

    func testVerifyingIsReportedWhenEveryPageIsBeingChecked() throws {
        let content = try XCTUnwrap(ScanPopup.content(for: [progress("1", size: 1000, offset: 1000, verifying: true)]))
        XCTAssertTrue(content.verifying)
        XCTAssertEqual(content.title, "Verificando a digitalização…")
    }

    func testFractionStaysInRangeAndHandlesEmptyFiles() throws {
        let empty = try XCTUnwrap(ScanPopup.content(for: [progress("1", size: 0, offset: 0)]))
        XCTAssertEqual(empty.fraction, 0)
        let over = try XCTUnwrap(ScanPopup.content(for: [progress("1", size: 100, offset: 500)]))
        XCTAssertEqual(over.fraction, 1)
    }

    func testFinishedMessage() {
        XCTAssertEqual(ScanPopup.finishedTitle(count: 1), "Digitalização recebida")
        XCTAssertEqual(ScanPopup.finishedTitle(count: 3), "3 digitalizações recebidas")
    }

    func testPopupPositionIsTheTopRightOfTheScreen() {
        let frame = ScanPopup.frame(size: CGSize(width: 340, height: 80), in: CGRect(x: 0, y: 0, width: 1440, height: 875))
        XCTAssertEqual(frame.maxX, 1440 - 16, accuracy: 0.1)
        XCTAssertEqual(frame.maxY, 875 - 12, accuracy: 0.1)
        XCTAssertEqual(frame.size, CGSize(width: 340, height: 80))
    }
}
