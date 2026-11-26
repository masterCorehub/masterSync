import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class ScanPasteShortcut {
    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<ScanPasteShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.action?() }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x4D535350, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                         id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { unregister() }
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    struct Target {
        private let pid: pid_t
        private let element: AXUIElement
        private let selection: CFTypeRef

        init?() {
            guard AXIsProcessTrusted(),
                  let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let focused = Self.focusedElement(pid),
                  Self.attribute(focused, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
                  let selection = Self.attribute(focused, kAXSelectedTextRangeAttribute) else { return nil }
            self.pid = pid
            element = focused
            self.selection = selection
        }

        func pasteIfStillFocused() -> Bool {
            // Never redirect an image into a different app, field, or selection.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let focused = Self.focusedElement(pid), CFEqual(element, focused),
                  let current = Self.attribute(focused, kAXSelectedTextRangeAttribute), CFEqual(selection, current),
                  let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
            return true
        }

        private static func focusedElement(_ pid: pid_t) -> AXUIElement? {
            guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }

        private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
            return value
        }
    }
}
