@testable import NexusMasterSync
import XCTest

final class SingleRetryTests: XCTestCase {
    @MainActor func testSchedulingAgainReplacesThePendingRetry() async throws {
        let retry = SingleRetry()
        var runs = 0
        retry.schedule(after: .milliseconds(50)) { runs += 1 }
        retry.schedule(after: .milliseconds(50)) { runs += 1 }
        retry.schedule(after: .milliseconds(50)) { runs += 1 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(runs, 1)
    }

    @MainActor func testCancelDropsThePendingRetry() async throws {
        let retry = SingleRetry()
        var runs = 0
        retry.schedule(after: .milliseconds(50)) { runs += 1 }
        retry.cancel()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(runs, 0)
    }
}
