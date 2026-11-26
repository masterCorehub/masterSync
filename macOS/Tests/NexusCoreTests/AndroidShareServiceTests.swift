import AppKit
import XCTest
@testable import NexusMasterSync

final class AndroidShareServiceTests: XCTestCase {
    @MainActor
    func testServiceRoutesFilesAndWebLinksByType() {
        let service = AndroidShareService()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let file = URL(fileURLWithPath: "/tmp/MasterSync-Service-Test.pdf")
        let link = URL(string: "https://example.com/manual")!
        var receivedFiles: [URL] = []
        var receivedText: String?
        service.send = {
            receivedFiles = $0
            receivedText = $1
            return nil
        }

        pasteboard.writeObjects([file as NSURL])
        var error: NSString?
        service.sendToAndroid(pasteboard, userData: nil, error: &error)
        XCTAssertEqual(receivedFiles, [file])
        XCTAssertNil(receivedText)
        XCTAssertNil(error)

        pasteboard.clearContents()
        pasteboard.writeObjects([link as NSURL])
        service.sendToAndroid(pasteboard, userData: nil, error: &error)
        XCTAssertTrue(receivedFiles.isEmpty)
        XCTAssertEqual(receivedText, link.absoluteString)
        XCTAssertNil(error)
    }
    @MainActor
    func testServiceReportsRejectionToFinderAndMasterSync() {
        let service = AndroidShareService()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Um link", forType: .string)
        let disconnected = "O Galaxy está desconectado."
        service.send = { _, _ in disconnected }
        var displayed: String?
        service.reportFailure = { displayed = $0 }
        var error: NSString?
        service.sendToAndroid(pasteboard, userData: nil, error: &error)
        XCTAssertEqual(error as String?, disconnected)
        XCTAssertEqual(displayed, disconnected)
    }

}
