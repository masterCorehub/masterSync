import NexusCore
@testable import NexusMasterSync
import XCTest

final class PixelFilesTests: XCTestCase {
    // MARK: Paths

    func testOnlyPathsInsideTheInternalStorageAreSafe() {
        XCTAssertTrue(PixelPath.isSafe("/sdcard"))
        XCTAssertTrue(PixelPath.isSafe("/sdcard/Download"))
        XCTAssertTrue(PixelPath.isSafe("/sdcard/Download/Meu arquivo (1).pdf"))
        XCTAssertTrue(PixelPath.isSafe("/sdcard/Música/Faixa é ã.mp3"))
        XCTAssertFalse(PixelPath.isSafe("/data/data"))
        XCTAssertFalse(PixelPath.isSafe("/sdcard/../data"))
        XCTAssertFalse(PixelPath.isSafe("/sdcard/Download/../../etc"))
        XCTAssertFalse(PixelPath.isSafe("/sdcardx"))
        XCTAssertFalse(PixelPath.isSafe(""))
    }

    func testShellMetacharactersAreNeverSafe() {
        for bad in ["a'b", "a\"b", "a$b", "a`b", "a;b", "a&b", "a|b", "a<b", "a>b", "a\nb", "a\\b"] {
            XCTAssertFalse(PixelPath.isSafe("/sdcard/\(bad)"), bad)
            XCTAssertFalse(PixelPath.isSafeName(bad), bad)
        }
        XCTAssertFalse(PixelPath.isSafeName(""))
        XCTAssertFalse(PixelPath.isSafeName(".."))
        XCTAssertFalse(PixelPath.isSafeName("a/b"))
    }

    func testQuotingWrapsInSingleQuotes() {
        XCTAssertEqual(PixelPath.quoted("/sdcard/Meu arquivo.pdf"), "'/sdcard/Meu arquivo.pdf'")
    }

    func testChildAndParent() {
        XCTAssertEqual(PixelPath.child("/sdcard", "Download"), "/sdcard/Download")
        XCTAssertEqual(PixelPath.child("/sdcard/Download", "a.pdf"), "/sdcard/Download/a.pdf")
        XCTAssertNil(PixelPath.child("/sdcard", "a'b"))
        XCTAssertEqual(PixelPath.parent("/sdcard/Download/MasterSync"), "/sdcard/Download")
        XCTAssertEqual(PixelPath.parent("/sdcard/Download"), "/sdcard")
        XCTAssertEqual(PixelPath.parent("/sdcard"), "/sdcard")
    }

    func testBreadcrumbsStartAtTheInternalStorage() {
        let crumbs = PixelPath.breadcrumbs("/sdcard/Download/MasterSync")
        XCTAssertEqual(crumbs.map(\.title), ["Armazenamento interno", "Download", "MasterSync"])
        XCTAssertEqual(crumbs.map(\.path), ["/sdcard", "/sdcard/Download", "/sdcard/Download/MasterSync"])
        XCTAssertEqual(PixelPath.breadcrumbs("/sdcard").count, 1)
    }

    // MARK: Listing

    private let listing = """
    total 120
    drwxrws--- 2 u0_a216 media_rw     3452 2025-11-26 10:15 Download
    drwxrws--- 3 u0_a216 media_rw     3452 2025-11-25 09:00 DCIM
    -rw-rw---- 1 u0_a216 media_rw   312345 2025-11-26 11:05 Roteiro viagem.docx
    lrwxrwxrwx 1 root    root           21 2025-11-01 08:00 link -> /storage/emulated/0
    -rw-rw---- 1 u0_a216 media_rw        0 2025-11-26 11:06 vazio.txt
    drwxrws--- 2 u0_a216 media_rw     3452 2025-11-26 10:15 .thumbnails
    -rw-rw---- 1 u0_a216 media_rw      900 2025-11-26 11:06 it's.txt
    """

    func testListingReadsNamesSizesAndKinds() {
        let entries = PixelListing.parse(listing)
        XCTAssertEqual(entries.first { $0.name == "Download" }?.isDirectory, true)
        let file = entries.first { $0.name == "Roteiro viagem.docx" }
        XCTAssertEqual(file?.isDirectory, false)
        XCTAssertEqual(file?.size, 312345)
        XCTAssertNotNil(file?.modified)
        XCTAssertEqual(entries.first { $0.name == "vazio.txt" }?.size, 0)
    }

    func testListingSkipsTotalsAndHiddenAndKeepsSymlinkNameOnly() {
        let names = PixelListing.parse(listing).map(\.name)
        XCTAssertFalse(names.contains { $0.hasPrefix("total") })
        XCTAssertFalse(names.contains(".thumbnails"))
        XCTAssertTrue(names.contains("link"))
    }

    func testListingMarksUnsafeNames() {
        let entries = PixelListing.parse(listing)
        XCTAssertEqual(entries.first { $0.name == "it's.txt" }?.isSafe, false)
        XCTAssertEqual(entries.first { $0.name == "Download" }?.isSafe, true)
    }

    func testListingSortsFoldersFirstThenByName() {
        let names = PixelListing.parse(listing).map(\.name)
        XCTAssertEqual(Array(names.prefix(2)), ["DCIM", "Download"])
    }

    func testListingToleratesGarbageAndEmpty() {
        XCTAssertTrue(PixelListing.parse("").isEmpty)
        XCTAssertTrue(PixelListing.parse("ls: /sdcard/x: No such file or directory").isEmpty)
        XCTAssertTrue(PixelListing.parse("drwx").isEmpty)
    }

    func testCountsLineFormat() {
        let counts = PixelListing.parseCounts("Download 38\nDCIM 1204\nlixo\nMusic x\nRecordings 9")
        XCTAssertEqual(counts, ["Download": 38, "DCIM": 1204, "Recordings": 9])
    }

    // MARK: Storage

    func testDfOutputGivesTotalUsedFree() throws {
        let output = "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/fuse 230000000 190000000 40000000 83% /storage/emulated\n"
        let storage = try XCTUnwrap(PixelStorage.parse(df: output))
        XCTAssertEqual(storage.total, 230_000_000 * 1024)
        XCTAssertEqual(storage.used, 190_000_000 * 1024)
        XCTAssertEqual(storage.free, 40_000_000 * 1024)
    }

    func testDfGarbageIsRejected() {
        XCTAssertNil(PixelStorage.parse(df: ""))
        XCTAssertNil(PixelStorage.parse(df: "df: /sdcard: No such file"))
        XCTAssertNil(PixelStorage.parse(df: "Filesystem 1K-blocks Used Available Use% Mounted on\nx a b c d e"))
    }

    func testBreakdownAddsOthersAndNeverGoesNegative() {
        let storage = PixelStorage(total: 1000, used: 700, free: 300)
        let parts = [("Fotos e vídeos", Int64(300)), ("WhatsApp", 100)]
        let breakdown = PixelStorage.breakdown(storage, parts: parts)
        XCTAssertEqual(breakdown.map(\.title), ["Fotos e vídeos", "WhatsApp", "Outros e sistema"])
        XCTAssertEqual(breakdown.last?.bytes, 300)
        let over = PixelStorage.breakdown(storage, parts: [("Tudo", 900)])
        XCTAssertEqual(over.map(\.bytes).reduce(0, +), 700)
    }

    func testBreakdownFractionsFillTheBar() {
        let storage = PixelStorage(total: 1000, used: 500, free: 500)
        let segments = PixelStorage.breakdown(storage, parts: [("A", 250)])
        XCTAssertEqual(segments.map(\.fraction).reduce(0, +), 0.5, accuracy: 0.0001)
    }

    func testGigabyteText() {
        XCTAssertEqual(PixelStorage.gigabytes(74_000_000_000), "74 GB")
        XCTAssertEqual(PixelStorage.gigabytes(1_500_000_000), "1,5 GB")
        XCTAssertEqual(PixelStorage.gigabytes(0), "0 GB")
    }

    // MARK: Transfer rows

    private func offer(_ name: String, size: Int64 = 1000) throws -> FileOffer {
        let json = #"{"id":"\#(UUID().uuidString.lowercased())","name":"\#(name)","mime":"application/pdf","size":\#(size),"hash":"x"}"#
        return try JSONDecoder().decode(FileOffer.self, from: Data(json.utf8))
    }

    private func file(_ name: String, at seconds: TimeInterval) throws -> ReceivedFile {
        ReceivedFile(peerID: "p", offer: try offer(name), url: URL(fileURLWithPath: "/tmp/\(name)"), date: Date(timeIntervalSince1970: seconds))
    }

    func testRowsMergeSentAndReceivedNewestFirst() throws {
        let rows = TransferRows.make(progress: [], sent: [try file("a", at: 100)], received: [try file("b", at: 200)],
                                     peerNames: ["p": "Pixel"], filter: .all)
        XCTAssertEqual(rows.map(\.name), ["b", "a"])
        XCTAssertEqual(rows.map(\.direction), [.received, .sent])
        XCTAssertEqual(rows.first?.deviceName, "Pixel")
    }

    func testFilterKeepsOneDirection() throws {
        let sent = [try file("a", at: 1)], received = [try file("b", at: 2)]
        XCTAssertEqual(TransferRows.make(progress: [], sent: sent, received: received, peerNames: [:], filter: .sent).map(\.name), ["a"])
        XCTAssertEqual(TransferRows.make(progress: [], sent: sent, received: received, peerNames: [:], filter: .received).map(\.name), ["b"])
    }

    func testTransfersInFlightComeFirstWithTheirFraction() throws {
        let progress = FileTransfers.Progress(id: "1", name: "grande.zip", peer: "p", sending: true, size: 1000, offset: 250)
        let rows = TransferRows.make(progress: [progress], sent: [try file("a", at: 100)], received: [], peerNames: [:], filter: .all)
        XCTAssertEqual(rows.first?.name, "grande.zip")
        XCTAssertEqual(rows.first?.fraction ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertNil(rows.last?.fraction)
        XCTAssertEqual(rows.first?.direction, .sent)
    }

    func testFilterAppliesToTransfersInFlightToo() {
        let progress = FileTransfers.Progress(id: "1", name: "x", peer: "p", sending: false, size: 10, offset: 1)
        XCTAssertTrue(TransferRows.make(progress: [progress], sent: [], received: [], peerNames: [:], filter: .sent).isEmpty)
        XCTAssertEqual(TransferRows.make(progress: [progress], sent: [], received: [], peerNames: [:], filter: .received).count, 1)
    }

    func testSizeText() {
        XCTAssertEqual(TransferRows.sizeText(312_000), "312 KB")
        XCTAssertEqual(TransferRows.sizeText(2_400_000), "2,4 MB")
        XCTAssertEqual(TransferRows.sizeText(900), "1 KB")
    }

    // MARK: Folder zip

    func testFolderIsZippedWithItsName() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zip-\(UUID().uuidString)")
        let folder = base.appendingPathComponent("Viagem")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("olá".utf8).write(to: folder.appendingPathComponent("nota.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let archive = try FolderZip.zip(folder, into: base)
        XCTAssertEqual(archive.lastPathComponent, "Viagem.zip")
        XCTAssertGreaterThan(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
        let listing = Process()
        let pipe = Pipe()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listing.arguments = ["-l", archive.path]
        listing.standardOutput = pipe
        try listing.run(); listing.waitUntilExit()
        XCTAssertTrue(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("Viagem/nota.txt"))
    }

    func testZippingAFileFails() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("f-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try FolderZip.zip(file, into: FileManager.default.temporaryDirectory))
    }
}
