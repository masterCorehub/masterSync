import Foundation

/// Messages for the control socket of a scrcpy 5.0.1 server. Every integer is big-endian.
enum ScrcpyControl {
    nonisolated static let mousePointer: UInt64 = .max
    nonisolated static let collapsePanels = Data([7])
    nonisolated static let expandNotifications = Data([5])

    /// Touch and key actions share these Android values.
    enum Action {
        nonisolated static let down: UInt8 = 0
        nonisolated static let up: UInt8 = 1
        nonisolated static let move: UInt8 = 2
    }

    enum Key {
        nonisolated static let home: Int32 = 3
        nonisolated static let back: Int32 = 4
        nonisolated static let power: Int32 = 26
        nonisolated static let enter: Int32 = 66
        nonisolated static let delete: Int32 = 67
        nonisolated static let appSwitch: Int32 = 187
        nonisolated static let tab: Int32 = 61
        nonisolated static let forwardDelete: Int32 = 112
        nonisolated static let moveHome: Int32 = 122
        nonisolated static let moveEnd: Int32 = 123
        nonisolated static let pageUp: Int32 = 92
        nonisolated static let pageDown: Int32 = 93
        nonisolated static let dpadUp: Int32 = 19
        nonisolated static let dpadDown: Int32 = 20
        nonisolated static let dpadLeft: Int32 = 21
        nonisolated static let dpadRight: Int32 = 22
    }

    private nonisolated static func be<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    nonisolated static func keycode(action: UInt8, keycode: Int32, metaState: Int32 = 0) -> Data {
        Data([0, action] + be(keycode) + be(Int32(0)) + be(metaState))
    }

    nonisolated static func touch(action: UInt8, x: Int32, y: Int32, width: UInt16, height: UInt16, pressed: Bool) -> Data {
        let pressure: UInt16 = pressed ? 0xFFFF : 0
        let actionButton: Int32 = action == Action.move ? 0 : 1
        let buttons: Int32 = pressed ? 1 : 0
        return Data([2, action] + be(mousePointer) + be(x) + be(y) + be(width) + be(height) + be(pressure)
                    + be(actionButton) + be(buttons))
    }

    /// Scroll amounts are in wheel steps; the protocol carries them as a fixed-point fraction of 16 steps.
    nonisolated static func scroll(x: Int32, y: Int32, width: UInt16, height: UInt16, horizontal: Float, vertical: Float) -> Data {
        func fixed(_ steps: Float) -> Int16 { Int16(max(-1, min(1, steps / 16)) * 32767) }
        return Data([3] + be(x) + be(y) + be(width) + be(height) + be(fixed(horizontal)) + be(fixed(vertical)) + be(Int32(0)))
    }

    nonisolated static func backOrScreenOn(action: UInt8) -> Data { Data([4, action]) }

    nonisolated static func text(_ string: String) -> Data? {
        let bytes = Array(string.utf8)
        guard !bytes.isEmpty, bytes.count <= 300 else { return nil }
        return Data([1] + be(UInt32(bytes.count)) + bytes)
    }
}
