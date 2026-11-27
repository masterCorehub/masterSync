@testable import NexusMasterSync
import XCTest

@MainActor
final class ToastTests: XCTestCase {
    func testActionFeedbackClearsItselfAfterTheToastTime() async throws {
        let model = NexusModel()
        model.toastSeconds = 0.05
        model.actionFeedback = "Pedido de foto recusado"
        XCTAssertEqual(model.toast, "Pedido de foto recusado")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(model.actionFeedback)
        XCTAssertNil(model.toast)
    }

    func testANewMessageRestartsTheTimerInsteadOfBeingClearedEarly() async throws {
        let model = NexusModel()
        model.toastSeconds = 0.25
        model.actionFeedback = "primeira"
        try await Task.sleep(for: .milliseconds(150))
        model.actionFeedback = "segunda"
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.actionFeedback, "segunda")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(model.actionFeedback)
    }

    func testCameraFeedbackAlsoExpiresAndShowsAsToast() async throws {
        let model = NexusModel()
        model.toastSeconds = 0.05
        model.cameraFeedback = "Foto salva no Mac."
        XCTAssertEqual(model.toast, "Foto salva no Mac.")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(model.cameraFeedback)
    }

    func testEmptyMessagesAreNotToasts() {
        let model = NexusModel()
        model.cameraFeedback = ""
        XCTAssertNil(model.toast)
    }
}
