import AppKit
@testable import NexusMasterSync
import XCTest

@MainActor
final class CodeClipboardTests: XCTestCase {
    private func board() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("code-test-\(UUID().uuidString)")) }

    func testCopyPutsTheCodeAsTextAndMarksItConcealed() {
        let pasteboard = board()
        CodeClipboard.copy("482913", to: pasteboard, clearAfter: 60)
        XCTAssertEqual(pasteboard.string(forType: .string), "482913")
        XCTAssertNotNil(pasteboard.data(forType: CodeClipboard.concealedType), "gerenciadores de área de transferência devem ignorar")
    }

    func testTheCodeIsRemovedAfterTheDelayWhenNothingElseWasCopied() async throws {
        let pasteboard = board()
        CodeClipboard.copy("482913", to: pasteboard, clearAfter: 0.05)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testSomethingCopiedLaterIsNeverErased() async throws {
        let pasteboard = board()
        CodeClipboard.copy("482913", to: pasteboard, clearAfter: 0.1)
        pasteboard.clearContents()
        pasteboard.setString("outra coisa", forType: .string)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(pasteboard.string(forType: .string), "outra coisa")
    }
}
