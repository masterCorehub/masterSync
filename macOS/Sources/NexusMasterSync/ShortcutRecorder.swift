import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the new combination; Esc cancels. Combinations without ⌘, ⌃ or ⌥ are ignored.
struct ShortcutRecorder: View {
    let combo: KeyCombo
    let onRecord: (KeyCombo) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Pressione as teclas…" : combo.label)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 120)
        }
        .buttonStyle(NexusPillStyle(selected: recording, compact: true))
        .help(recording ? "Pressione a nova combinação ou Esc para cancelar" : "Clique para gravar outro atalho")
        .accessibilityLabel(recording ? "Gravando atalho" : "Atalho \(combo.label). Clique para mudar")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            if let combo = KeyCombo(keyCode: event.keyCode, flags: event.modifierFlags,
                                    key: event.charactersIgnoringModifiers ?? "") {
                stop()
                onRecord(combo)
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
