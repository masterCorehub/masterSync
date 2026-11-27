import AppKit
@testable import NexusMasterSync
import XCTest

final class ScanActionsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func jpeg(in directory: URL, name: String = "Digitalização 1.jpg") throws -> URL {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 40, height: 40).fill(); image.unlockFocus()
        let data = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .jpeg, properties: [:]))
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testUniqueDestinationKeepsTheNameWhenFree() throws {
        let folder = try directory()
        XCTAssertEqual(ScanActions.uniqueDestination(name: "a.jpg", in: folder).lastPathComponent, "a.jpg")
    }

    func testUniqueDestinationNumbersTakenNames() throws {
        let folder = try directory()
        try Data("x".utf8).write(to: folder.appendingPathComponent("a.jpg"))
        XCTAssertEqual(ScanActions.uniqueDestination(name: "a.jpg", in: folder).lastPathComponent, "a 2.jpg")
        try Data("x".utf8).write(to: folder.appendingPathComponent("a 2.jpg"))
        XCTAssertEqual(ScanActions.uniqueDestination(name: "a.jpg", in: folder).lastPathComponent, "a 3.jpg")
    }

    func testUniqueDestinationHandlesNamesWithoutExtensionAndPaths() throws {
        let folder = try directory()
        try Data("x".utf8).write(to: folder.appendingPathComponent("nota"))
        XCTAssertEqual(ScanActions.uniqueDestination(name: "nota", in: folder).lastPathComponent, "nota 2")
        // A name can never walk out of the folder.
        XCTAssertEqual(ScanActions.uniqueDestination(name: "../x.jpg", in: folder).deletingLastPathComponent().standardizedFileURL,
                       folder.standardizedFileURL)
    }

    func testSaveCopiesAndNeverOverwrites() throws {
        let source = try directory(), target = try directory()
        let file = try jpeg(in: source)
        let first = try ScanActions.save(file, to: target)
        let second = try ScanActions.save(file, to: target)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "o original continua no lugar")
    }

    func testSaveFailsForAMissingFile() throws {
        XCTAssertThrowsError(try ScanActions.save(URL(fileURLWithPath: "/tmp/nao-existe-\(UUID().uuidString).jpg"), to: try directory()))
    }

    func testCopyPutsTheImageAndTheFileOnThePasteboard() throws {
        let file = try jpeg(in: try directory())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("scan-test-\(UUID().uuidString)"))
        XCTAssertTrue(ScanActions.copy(file, to: pasteboard))
        XCTAssertNotNil(NSImage(pasteboard: pasteboard))
        XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.lastPathComponent, file.lastPathComponent)
    }

    func testCopyFailsForAMissingFile() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("scan-test-\(UUID().uuidString)"))
        XCTAssertFalse(ScanActions.copy(URL(fileURLWithPath: "/tmp/nao-existe.jpg"), to: pasteboard))
    }

    func testOnlyAPageThatWasNotKnownOpensTheModal() {
        XCTAssertEqual(ScanActions.newPage(known: ["a"], current: ["c", "b", "a"]), "c")
        XCTAssertNil(ScanActions.newPage(known: ["a", "b"], current: ["b", "a"]))
        XCTAssertNil(ScanActions.newPage(known: [], current: []))
    }

    func testDeletingAPageDoesNotOpenTheModalForAnOlderOne() {
        // After "c" is deleted the list is ["b", "a"]; both were seen, so nothing opens.
        XCTAssertNil(ScanActions.newPage(known: ["a", "b", "c"], current: ["b", "a"]))
    }
}
