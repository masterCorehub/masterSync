import NexusCore
@testable import NexusMasterSync
import XCTest

final class QuickControlsTests: XCTestCase {
    private func inputs(online: Bool = true) -> QuickControls.Inputs {
        QuickControls.Inputs(phoneName: "Pixel 9 Pro", online: online, dndAllowed: true, dndEnabled: false, canFind: true,
                             controlsAvailable: true, torch: false, torchAvailable: true, ringer: "normal", hasADB: true)
    }

    private func item(_ kind: QuickControl.Kind, _ inputs: QuickControls.Inputs) -> QuickControl {
        QuickControls.items(inputs).first { $0.kind == kind }!
    }

    func testTheSixButtonsComeInTheDesignOrder() {
        XCTAssertEqual(QuickControls.items(inputs()).map(\.kind), [.dnd, .ringer, .find, .hotspot, .torch, .lock])
        XCTAssertEqual(QuickControls.items(inputs()).map(\.title),
                       ["Não perturbe", "Silencioso", "Tocar celular", "Hotspot", "Lanterna", "Bloquear"])
    }

    func testDoNotDisturbFollowsThePhone() {
        var state = inputs()
        XCTAssertEqual(item(.dnd, state).subtitle, "Desativado")
        XCTAssertFalse(item(.dnd, state).isOn)
        state.dndEnabled = true
        XCTAssertEqual(item(.dnd, state).subtitle, "Ativado")
        XCTAssertTrue(item(.dnd, state).isOn)
    }

    func testDoNotDisturbNeedsThePhonePermission() {
        var state = inputs()
        state.dndAllowed = false
        XCTAssertFalse(item(.dnd, state).isEnabled)
        XCTAssertEqual(item(.dnd, state).subtitle, "Autorize no celular")
        state.dndAllowed = nil
        XCTAssertFalse(item(.dnd, state).isEnabled)
    }

    func testRingerShowsItsMode() {
        var state = inputs()
        XCTAssertEqual(item(.ringer, state).subtitle, "Som normal")
        XCTAssertFalse(item(.ringer, state).isOn)
        state.ringer = "silent"
        XCTAssertEqual(item(.ringer, state).subtitle, "Silencioso")
        XCTAssertTrue(item(.ringer, state).isOn)
        state.ringer = "vibrate"
        XCTAssertEqual(item(.ringer, state).subtitle, "Vibrar")
        XCTAssertFalse(item(.ringer, state).isOn)
    }

    func testRingerAndTorchNeedAnUpdatedPhoneApp() {
        var state = inputs()
        state.controlsAvailable = false
        XCTAssertFalse(item(.ringer, state).isEnabled)
        XCTAssertFalse(item(.torch, state).isEnabled)
        XCTAssertEqual(item(.torch, state).subtitle, "Atualize o app")
    }

    func testTorchShowsItsState() {
        var state = inputs()
        XCTAssertEqual(item(.torch, state).subtitle, "Apagada")
        state.torch = true
        XCTAssertEqual(item(.torch, state).subtitle, "Acesa")
        XCTAssertTrue(item(.torch, state).isOn)
    }

    func testPhoneWithoutAFlashDisablesTheTorch() {
        var state = inputs()
        state.torchAvailable = false
        XCTAssertFalse(item(.torch, state).isEnabled)
        XCTAssertEqual(item(.torch, state).subtitle, "Sem lanterna")
    }

    func testFindPhoneNeedsTheFeatureOn() {
        var state = inputs()
        XCTAssertTrue(item(.find, state).isEnabled)
        XCTAssertEqual(item(.find, state).subtitle, "Encontrar")
        state.canFind = false
        XCTAssertFalse(item(.find, state).isEnabled)
    }

    func testLockAndHotspotNeedAdbOverWifi() {
        var state = inputs()
        XCTAssertTrue(item(.lock, state).isEnabled)
        XCTAssertEqual(item(.lock, state).subtitle, "Tela do Pixel 9 Pro")
        XCTAssertEqual(item(.hotspot, state).subtitle, "Abrir ajustes")
        XCTAssertFalse(item(.hotspot, state).isOn)
        state.hasADB = false
        XCTAssertFalse(item(.lock, state).isEnabled)
        XCTAssertFalse(item(.hotspot, state).isEnabled)
    }

    func testEverythingThatTalksToTheAppNeedsAConnection() {
        let offline = inputs(online: false)
        for kind in [QuickControl.Kind.dnd, .ringer, .find, .torch] {
            XCTAssertFalse(item(kind, offline).isEnabled, "\(kind)")
        }
        // ADB reaches the phone on its own.
        XCTAssertTrue(item(.lock, offline).isEnabled)
    }

    func testEveryButtonHasAnIconAndALabelForVoiceOver() {
        for control in QuickControls.items(inputs()) {
            XCTAssertFalse(control.icon.isEmpty)
            XCTAssertFalse(control.accessibilityLabel.isEmpty)
        }
    }

    func testLongPhoneNamesAreShortenedInTheLockSubtitle() {
        var state = inputs()
        state.phoneName = String(repeating: "A", count: 80)
        XCTAssertLessThanOrEqual(item(.lock, state).subtitle.count, 40)
    }

    // MARK: Protocol

    func testControlMessagesCarryTheirFields() throws {
        var message = Message("deviceControl")
        message.control = "torch"
        message.enabled = true
        let decoded = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.control, "torch")
        XCTAssertEqual(decoded.enabled, true)
        let state = try JSONDecoder().decode(Message.self, from: Data(#"{"type":"deviceControlsState","torch":true,"torchAvailable":true,"ringer":"silent","ringerAllowed":false}"#.utf8))
        XCTAssertEqual(state.torch, true)
        XCTAssertEqual(state.ringer, "silent")
        XCTAssertEqual(state.ringerAllowed, false)
        XCTAssertEqual(state.torchAvailable, true)
    }
}
