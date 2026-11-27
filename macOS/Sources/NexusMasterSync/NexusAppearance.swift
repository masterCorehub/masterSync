import SwiftUI

struct NexusPalette {
    let scheme: ColorScheme

    // Window and text. `canvas` is the opaque stand-in for the glass, used when transparency is reduced and for contrast checks.
    var canvas: Color { tone(0x161820, 0xF4F6F9) }
    var ink: Color { tone(0xF3F4F6, 0x14161B) }
    var muted: Color { tone(0xA3A5A9, 0x696B6F) }
    var faint: Color { tone(0x77797E, 0x8F9195) }

    // Glass surfaces, translucent so the window material shows through.
    var panel: Color { tone(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.06, lightAlpha: 0.50) }
    var panel2: Color { tone(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.11, lightAlpha: 0.80) }
    var line: Color { tone(0xFFFFFF, 0x141820, darkAlpha: 0.09, lightAlpha: 0.08) }
    var edge: Color { tone(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.16, lightAlpha: 0.75) }
    var active: Color { tone(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.12, lightAlpha: 0.75) }
    var track: Color { tone(0xFFFFFF, 0x141820, darkAlpha: 0.16, lightAlpha: 0.14) }
    var input: Color { tone(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.07, lightAlpha: 0.60) }
    var side: Color { tone(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.035, lightAlpha: 0.25) }
    var windowTint: Color { tone(0x161820, 0xFAFBFD, darkAlpha: 0.30, lightAlpha: 0.42) }

    // Teal accent. `accent` is for text and icons on the glass; `fill` is for buttons, with `accentInk` on top.
    var accent: Color { tone(0x5ED8A9, 0x007950) }
    var fill: Color { tone(0x0BC18D, 0x0BC18D) }
    var accentInk: Color { tone(0x06130D, 0x06130D) }
    var accentSurface: Color { tone(0x0BC18D, 0x0BC18D, darkAlpha: 0.18, lightAlpha: 0.18) }
    var secondary: Color { tone(0x6BA4FF, 0x3461AC) }
    var connected: Color { accent }

    // Names kept from the previous palette so existing screens move to the new look together.
    var surface: Color { panel }
    var control: Color { panel2 }
    var border: Color { edge }

    private func tone(_ dark: UInt32, _ light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) -> Color {
        let isDark = scheme == .dark
        let rgb = isDark ? dark : light
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255,
                     opacity: isDark ? darkAlpha : lightAlpha)
    }

    /// sRGB components, so tests and contrast checks can compare colors.
    static func rgba(_ color: Color) -> [Double] {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent].map { Double($0) }
    }

    /// WCAG contrast ratio between two colors (alpha is ignored; pass opaque colors).
    static func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let c = rgba(color).prefix(3).map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

private struct FlatBackdropKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Draws the plain window color instead of the native glass, which ImageRenderer cannot show (used by snapshot tests).
    var nexusFlatBackdrop: Bool {
        get { self[FlatBackdropKey.self] }
        set { self[FlatBackdropKey.self] = newValue }
    }
}

struct NexusBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nexusFlatBackdrop) private var flat

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        ZStack {
            if reduceTransparency || flat {
                palette.canvas
            } else {
                GlassBackground()
                // Two soft color blobs behind the glass, as in the design.
                Circle().fill(palette.fill.opacity(scheme == .dark ? 0.30 : 0.38)).frame(width: 420, height: 420)
                    .blur(radius: 70).offset(x: -360, y: 170)
                Circle().fill(palette.secondary.opacity(scheme == .dark ? 0.30 : 0.38)).frame(width: 360, height: 360)
                    .blur(radius: 80).offset(x: 360, y: -190)
                palette.windowTint
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
            if filled { return palette.fill }
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
        return background(highlighted ? palette.accentSurface : palette.panel, in: shape)
            .overlay { shape.strokeBorder(highlighted ? palette.accent.opacity(0.52) : palette.line) }
    }
}
