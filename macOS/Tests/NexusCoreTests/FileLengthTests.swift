@testable import NexusMasterSync
import XCTest

final class FileLengthTests: XCTestCase {
    func testLengthFollowsAppendsOnTheSameURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 1, count: 10).write(to: url)
        XCTAssertEqual(try FileTransfers.currentLength(url), 10)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 2, count: 5))
        try handle.close()
        XCTAssertEqual(try FileTransfers.currentLength(url), 15)
    }
}
