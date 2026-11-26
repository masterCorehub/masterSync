import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus Carbon modifiers, with the key's printed name for its label.
struct KeyCombo: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let scanDefault = KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey), key: "D")

    private init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// A global shortcut needs ⌃ or ⌥: plain ⌘ and ⇧⌘ belong to every app's menus (⌘C, ⌘V) and to MasterSync's own.
    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) {
        let modifiers = Self.carbonModifiers(flags)
        guard modifiers & UInt32(controlKey | optionKey) != 0,
              let printable = key.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers, key: String(printable).uppercased())
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value = 0
        if flags.contains(.command) { value |= cmdKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.shift) { value |= shiftKey }
        return UInt32(value)
    }

    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }
}
