import Foundation

struct QuickControl: Identifiable, Equatable {
    enum Kind: String { case dnd, ringer, find, hotspot, torch, lock }

    let kind: Kind
    let title: String
    let subtitle: String
    let icon: String
    let isOn: Bool
    let isEnabled: Bool
    /// What to tell the person when the button is off and they press it anyway.
    var disabledReason: String? = nil

    var id: String { kind.rawValue }
    var accessibilityLabel: String { "\(title), \(subtitle)" }
}

/// The six buttons on the phone card of the overview: what each shows and when it can be pressed.
enum QuickControls {
    struct Inputs {
        var phoneName: String
        /// The MasterSync connection to the phone is up.
        var online: Bool
        var dndAllowed: Bool?
        var dndEnabled: Bool
        var canFind: Bool
        /// The phone's app understands the torch and ringer commands.
        var controlsAvailable: Bool
        var torch: Bool?
        var torchAvailable: Bool?
        /// "normal", "vibrate" or "silent"; nil before the phone has answered.
        var ringer: String?
        /// ADB over Wi-Fi is set up for this phone (needed to lock the screen and open its hotspot settings).
        var hasADB: Bool
    }

    static func items(_ input: Inputs) -> [QuickControl] {
        [dnd(input), ringer(input), find(input), hotspot(input), torch(input), lock(input)]
    }

    private static let offline = "Conecte o celular para usar este botão."
    private static let needsWifiControl = "Configure o controle por Wi‑Fi (tela Dispositivos) para usar este botão."

    private static func dnd(_ i: Inputs) -> QuickControl {
        let allowed = i.dndAllowed == true
        let enabled = i.online && allowed
        return QuickControl(kind: .dnd, title: "Não perturbe",
                            subtitle: allowed || !i.online ? (i.dndEnabled ? "Ativado" : "Desativado") : "Autorize no celular",
                            icon: "minus.circle", isOn: i.dndEnabled && allowed, isEnabled: enabled,
                            disabledReason: enabled ? nil : (!i.online ? offline : "Autorize o Não Perturbe no MasterSync do Android."))
    }

    private static func ringer(_ i: Inputs) -> QuickControl {
        let mode = i.ringer ?? "normal"
        let subtitle = !i.controlsAvailable && i.online ? "Atualize o app"
            : mode == "silent" ? "Silencioso" : mode == "vibrate" ? "Vibrar" : "Som normal"
        let enabled = i.online && i.controlsAvailable
        return QuickControl(kind: .ringer, title: "Silencioso", subtitle: subtitle,
                            icon: mode == "silent" ? "speaker.slash.fill" : "speaker.slash", isOn: mode == "silent", isEnabled: enabled,
                            disabledReason: enabled ? nil : (!i.online ? offline : appUpdate))
    }

    private static let appUpdate = "Atualize o MasterSync no Android para usar a lanterna e o modo silencioso."

    private static func find(_ i: Inputs) -> QuickControl {
        let enabled = i.online && i.canFind
        return QuickControl(kind: .find, title: "Tocar celular", subtitle: "Encontrar", icon: "phone.arrow.up.right", isOn: false,
                            isEnabled: enabled,
                            disabledReason: enabled ? nil : (!i.online ? offline : "Ative “Localizar celular” no MasterSync do Android para fazê-lo tocar."))
    }

    private static func hotspot(_ i: Inputs) -> QuickControl {
        // The phone offers no way to switch it on from outside, so the button opens its hotspot settings.
        QuickControl(kind: .hotspot, title: "Hotspot", subtitle: "Abrir ajustes", icon: "personalhotspot", isOn: false, isEnabled: i.hasADB,
                     disabledReason: i.hasADB ? nil : needsWifiControl)
    }

    private static func torch(_ i: Inputs) -> QuickControl {
        let noFlash = i.torchAvailable == false
        let subtitle = !i.controlsAvailable && i.online ? "Atualize o app" : noFlash ? "Sem lanterna" : (i.torch == true ? "Acesa" : "Apagada")
        let enabled = i.online && i.controlsAvailable && !noFlash
        let reason: String? = enabled ? nil : (!i.online ? offline : !i.controlsAvailable ? appUpdate : "Este celular não tem lanterna.")
        return QuickControl(kind: .torch, title: "Lanterna", subtitle: subtitle,
                            icon: i.torch == true ? "flashlight.on.fill" : "flashlight.off.fill", isOn: i.torch == true && !noFlash,
                            isEnabled: enabled, disabledReason: reason)
    }

    private static func lock(_ i: Inputs) -> QuickControl {
        let name = String(i.phoneName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        return QuickControl(kind: .lock, title: "Bloquear", subtitle: name.isEmpty ? "Tela do celular" : "Tela do \(name)",
                            icon: "lock", isOn: false, isEnabled: i.hasADB, disabledReason: i.hasADB ? nil : needsWifiControl)
    }
}
