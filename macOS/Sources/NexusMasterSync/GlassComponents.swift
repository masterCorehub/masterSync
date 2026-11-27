import AppKit
import SwiftUI

/// The window's glass: blurs what is behind the window, like the design's frosted panel.
struct GlassBackground: NSViewRepresentable {
    /// Lets the window itself be see-through, so the blur has something behind it.
    private final class GlassView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
        }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension NexusPalette {
    /// oklch(l c h) as an sRGB color, to share hues (avatars, app badges) with the design.
    static func oklch(_ l: Double, _ c: Double, _ hue: Double) -> Color {
        let a = c * cos(hue * .pi / 180), b = c * sin(hue * .pi / 180)
        let l1 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m1 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s1 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        let r = 4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1
        let g = -1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1
        let bl = -0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1
        func encode(_ v: Double) -> Double {
            let x = max(0, min(1, v))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        return Color(red: encode(r), green: encode(g), blue: encode(bl))
    }

    /// A hue (0..<360) that stays the same between launches, so an app or person keeps its color.
    static func stableHue(_ text: String) -> Double {
        // FNV-1a, so package names that differ in one character still land far apart on the color wheel.
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        hash ^= hash >> 15
        hash = hash &* 2_246_822_519
        hash ^= hash >> 13
        return Double(hash % 360)
    }

    /// The design's avatar/app color for a hue.
    static func hueColor(_ hue: Double) -> Color { oklch(0.6, 0.15, hue) }
}

extension View {
    /// A glass card: translucent fill, hairline border, rounded corners.
    func glassPanel(radius: CGFloat = 20, padding: CGFloat? = nil) -> some View {
        modifier(GlassPanelModifier(radius: radius, padding: padding))
    }
}

private struct GlassPanelModifier: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = NexusPalette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? 0)
            .background(palette.panel, in: shape)
            .overlay { shape.strokeBorder(palette.line) }
    }
}

/// A rounded badge with an icon, tinted with the accent.
struct IconBadge: View {
    let systemName: String
    var size: CGFloat = 38
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(palette.accent)
            .frame(width: size, height: size)
            .background(palette.accentSurface, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A round avatar with initials, colored by hue.
struct Avatar: View {
    let initials: String
    var hue: Double = 165
    var size: CGFloat = 36

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(NexusPalette.hueColor(hue), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The design's 36×22 switch.
struct GlassToggle: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? palette.fill : palette.track)
                Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            }
            .frame(width: 36, height: 22)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "Ligado" : "Desligado")
    }
}

/// A small status dot, pulsing when live.
struct StatusDot: View {
    var color: Color
    var pulsing = false
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .opacity(pulsing && dim ? 0.3 : 1)
            .onAppear {
                guard pulsing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// A settings row: title and optional subtitle at the left, a switch at the right, hairline below.
struct SwitchRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var showsDivider = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = NexusPalette(scheme: scheme)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(palette.muted) }
                }
                Spacer(minLength: 8)
                GlassToggle(isOn: $isOn)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "Ligado" : "Desligado")
            .accessibilityAction { isOn.toggle() }
            if showsDivider { Rectangle().fill(palette.line).frame(height: 1) }
        }
    }
}

/// A scroll view that, in snapshot tests, lays its content out directly (ImageRenderer cannot draw scrolling content).
struct SnapshotAwareScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.nexusFlatBackdrop) private var snapshot

    var body: some View {
        if snapshot {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content }
        }
    }
}

/// Every `Toggle` in the window: label at the left, the design's switch at the right.
struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            GlassToggle(isOn: configuration.$isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}
