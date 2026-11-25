import SwiftUI

struct NexusPalette {
    let scheme: ColorScheme

    var canvas: Color { tone(0x191412, 0xF5EEE6) }
    var surface: Color { tone(0x2F2521, 0xFFF9F2) }
    var control: Color { tone(0x392E28, 0xECE0D3) }
    var border: Color { tone(0x59453B, 0xDED0C2) }
    var ink: Color { tone(0xF5ECE3, 0x281C16) }
    var muted: Color { tone(0xC4B1A3, 0x635046) }
    var accent: Color { tone(0xF3BB7D, 0x8A4925) }
    var accentInk: Color { tone(0x27180F, 0xFFF8F0) }
    var accentSurface: Color { tone(0x473225, 0xF2E0CB) }
    var connected: Color { tone(0xA6CD9E, 0x386342) }

    private func tone(_ dark: UInt32, _ light: UInt32) -> Color {
        let rgb = scheme == .dark ? dark : light
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }
}

struct NexusBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        ZStack {
            palette.canvas
            if !reduceTransparency {
                // Warm light stays at the window edges so the text has a steady backdrop.
                RadialGradient(colors: [palette.accent.opacity(scheme == .dark ? 0.145 : 0.09), .clear],
                               center: .init(x: 0.82, y: 0.11), startRadius: 0, endRadius: 540)
                RadialGradient(colors: [palette.accent.opacity(0.055), .clear],
                               center: .bottomLeading, startRadius: 12, endRadius: 470)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct NexusPillStyle: ButtonStyle {
    var selected = false
    var prominent = false
    var compact = false
    var segmented = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, selected: selected, prominent: prominent, compact: compact, segmented: segmented)
    }

    private struct Pill: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        let prominent: Bool
        let compact: Bool
        let segmented: Bool
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        private var filled: Bool { prominent || selected }

        private func background(in palette: NexusPalette) -> Color {
            if filled { return palette.accent }
            if hovered { return palette.control }
            return segmented ? .clear : palette.control.opacity(0.72)
        }

        var body: some View {
            let palette = NexusPalette(scheme: scheme)
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .padding(.horizontal, compact ? 11 : 14)
                .frame(minHeight: compact ? 31 : 37)
                .foregroundStyle(filled ? palette.accentInk : palette.ink)
                .background {
                    Capsule().fill(background(in: palette))
                }
                .opacity(enabled ? (configuration.isPressed ? 0.83 : 1) : 0.45)
                .contentShape(.capsule)
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: hovered)
        }
    }
}

extension View {
    func nexusPanel(_ palette: NexusPalette, radius: CGFloat = 19, highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(highlighted ? palette.accentSurface : palette.surface, in: shape)
            .overlay { shape.strokeBorder(highlighted ? palette.accent.opacity(0.52) : palette.border.opacity(0.65)) }
    }
}
