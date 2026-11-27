import NexusCore
@testable import NexusMasterSync
import XCTest

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var shell: [String] = []
    private var pulls: [(String, URL)] = []
    func addShell(_ c: String) { lock.lock(); shell.append(c); lock.unlock() }
    func addPull(_ r: String, _ l: URL) { lock.lock(); pulls.append((r, l)); lock.unlock() }
    var shellCommands: [String] { lock.lock(); defer { lock.unlock() }; return shell }
    var pullCalls: [(String, URL)] { lock.lock(); defer { lock.unlock() }; return pulls }
}

@MainActor
final class PixelFilesModelTests: XCTestCase {
    private let rootListing = """
    total 8
    drwxrws--- 2 u0 media_rw 4096 2025-11-26 10:15 Download
    drwxrws--- 3 u0 media_rw 4096 2025-11-25 09:00 DCIM
    -rw-rw---- 1 u0 media_rw 312345 2025-11-26 11:05 nota.txt
    """

    private func makeModel(calls: Calls, fail: Bool = false, destination: URL? = nil) -> PixelFilesModel {
        let model = PixelFilesModel(downloads: destination ?? FileManager.default.temporaryDirectory.appendingPathComponent("px-\(UUID().uuidString)"))
        let listing = rootListing
        model.shell = { command in
            calls.addShell(command)
            if fail { throw NexusError.transfer("Sem ADB") }
            if command.hasPrefix("ls -la") { return listing }
            if command.hasPrefix("df") { return "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/fuse 1000000 600000 400000 60% /storage" }
            if command.hasPrefix("du") { return "300000\t/sdcard/DCIM\n100000\t/sdcard/Music" }
            return "Download 38\nDCIM 1204\n"
        }
        model.pull = { remote, local in calls.addPull(remote, local) }
        return model
    }

    func testOpeningTheRootListsItsEntries() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        await model.open(PixelPath.root)
        XCTAssertEqual(model.entries.map(\.name), ["DCIM", "Download", "nota.txt"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)
        XCTAssertTrue(calls.shellCommands.contains("ls -la '/sdcard'"))
    }

    func testOverviewLoadsStorageCountsAndTheBar() async {
        let model = makeModel(calls: Calls())
        await model.loadOverview()
        XCTAssertEqual(model.storage?.free, 400_000 * 1024)
        XCTAssertEqual(model.folderCounts["Download"], 38)
        XCTAssertEqual(model.segments.map(\.title), ["Fotos e vídeos", "Música", "Outros e sistema"])
    }

    func testNavigatingIntoAFolderAndBack() async {
        let model = makeModel(calls: Calls())
        await model.open(PixelPath.root)
        let folder = model.entries.first { $0.name == "Download" }!
        await model.enter(folder)
        XCTAssertEqual(model.path, "/sdcard/Download")
        await model.goUp()
        XCTAssertEqual(model.path, "/sdcard")
        await model.goUp()
        XCTAssertEqual(model.path, "/sdcard", "não sobe além do armazenamento interno")
    }

    func testUnsafePathsNeverReachTheShell() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        await model.open("/data/data")
        await model.open("/sdcard/../etc")
        await model.open("/sdcard/a'b")
        XCTAssertTrue(calls.shellCommands.isEmpty)
        XCTAssertNotNil(model.error)
    }

    func testAnADBFailureShowsAMessageAndKeepsTheModelUsable() async {
        let model = makeModel(calls: Calls(), fail: true)
        await model.open(PixelPath.root)
        XCTAssertEqual(model.error, "Sem ADB")
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertFalse(model.loading)
    }

    func testDownloadPullsEachSelectedItemIntoTheFolder() async throws {
        let calls = Calls()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let model = makeModel(calls: calls, destination: folder)
        await model.open(PixelPath.root)
        model.toggle(model.entries.first { $0.name == "nota.txt" }!)
        model.toggle(model.entries.first { $0.name == "DCIM" }!)
        await model.downloadSelection()
        XCTAssertEqual(Set(calls.pullCalls.map(\.0)), ["/sdcard/nota.txt", "/sdcard/DCIM"])
        XCTAssertTrue(calls.pullCalls.allSatisfy { $0.1.deletingLastPathComponent().path == folder.path })
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.downloadMessage, "2 itens baixados para Downloads/MasterSync.")
    }

    func testDownloadSkipsUnsafeNamesAndReportsFailures() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        model.pull = { _, _ in throw NexusError.transfer("sem espaço") }
        await model.open(PixelPath.root)
        model.toggle(model.entries.first { $0.name == "nota.txt" }!)
        await model.downloadSelection()
        XCTAssertEqual(model.downloadMessage, "Não foi possível baixar nota.txt: sem espaço")
    }

    func testSelectionClearsWhenTheFolderChanges() async {
        let model = makeModel(calls: Calls())
        await model.open(PixelPath.root)
        model.toggle(model.entries.first { $0.name == "nota.txt" }!)
        XCTAssertEqual(model.selection.count, 1)
        await model.enter(model.entries.first { $0.name == "Download" }!)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testFoldersCannotBeOpenedWhenTheirNameIsUnsafe() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        let json = #"{"name":"x"}"#
        _ = json
        let unsafe = PixelListing.Entry(name: "a'b", isDirectory: true, size: 0, modified: nil, isSafe: false)
        await model.enter(unsafe)
        XCTAssertEqual(model.path, "/sdcard")
        XCTAssertTrue(calls.shellCommands.isEmpty)
    }

    func testDuParsingGroupsFolders() {
        let parts = PixelStorage.parts(fromDu: "300000\t/sdcard/DCIM\n50000\t/sdcard/Pictures\n100000\t/sdcard/Music\n7\t/sdcard/Android/media/com.whatsapp\nlixo")
        XCTAssertEqual(parts.map(\.0), ["Fotos e vídeos", "Música", "WhatsApp"])
        XCTAssertEqual(parts.first?.1, 350_000 * 1024)
    }
}
