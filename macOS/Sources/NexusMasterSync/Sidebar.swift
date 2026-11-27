import NexusCore
import SwiftUI

/// The left column of the window: the phone, the sections, pinned apps and what was copied last.
struct Sidebar: View {
    @ObservedObject var model: NexusModel
    var pinnedApps: [AndroidApp]
    var openApp: (AndroidApp) -> Void
    var manageApps: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var palette: NexusPalette { NexusPalette(scheme: scheme) }

    private var badges: [Section: Int] { [.notifications: model.notifications.notices.count] }

    var body: some View {
        // The column fits when the window is tall enough; otherwise it scrolls.
        ViewThatFits(in: .vertical) {
            column.frame(maxHeight: .infinity, alignment: .top)
            ScrollView { column }.scrollIndicators(.hidden)
        }
        .frame(width: 244)
        .background(palette.side)
        .overlay(alignment: .trailing) { Rectangle().fill(palette.line).frame(width: 1) }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 12) {
            phoneCard
            VStack(spacing: 2) {
                ForEach(sidebarItems(group: .main, badges: badges)) { row($0) }
            }
            VStack(alignment: .leading, spacing: 0) {
                caption("Em breve").padding(.horizontal, 10).padding(.bottom, 2)
                ForEach(sidebarItems(group: .soon, badges: badges)) { row($0, compact: true) }
            }
            Spacer(minLength: 8)
            pinned
            clipboardCard
            HStack(spacing: 4) {
                ForEach(sidebarItems(group: .footer, badges: badges)) { row($0, compact: true) }
            }
        }
        .padding(.horizontal, 12)
        // Room for the window's own close/minimize buttons.
        .padding(.top, 34).padding(.bottom, 12)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold)).tracking(0.7)
            .foregroundStyle(palette.muted)
    }

    private var phoneCard: some View {
        let status = model.selectedStatus
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(palette.faint, lineWidth: 1.5)
                    .frame(width: 34, height: 56)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(palette.faint).frame(width: 12, height: 2).padding(.bottom, 4)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selected?.name ?? "Nenhum celular")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusDot(color: model.active ? palette.fill : palette.faint, pulsing: model.active)
                        Text(model.active ? "Conectado · Wi‑Fi" : "Desconectado")
                            .font(.system(size: 11.5))
                            .foregroundStyle(model.active ? palette.accent : palette.muted)
                    }
                }
            }
            if let battery = status?.battery {
                VStack(spacing: 6) {
                    HStack {
                        Text("Bateria")
                        Spacer()
                        Text("\(battery)%" + (status?.charging == true ? " · carregando" : ""))
                    }
                    .font(.system(size: 11.5)).foregroundStyle(palette.muted)
                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.track)
                            Capsule().fill(palette.fill).frame(width: bar.size.width * CGFloat(min(max(battery, 0), 100)) / 100)
                        }
                    }.frame(height: 5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bateria \(battery) por cento\(status?.charging == true ? ", carregando" : "")")
            }
        }
        .padding(14)
        .glassPanel(radius: 16)
        .accessibilityElement(children: .contain)
    }

    private func row(_ item: SidebarItem, compact: Bool = false) -> some View {
        let selected = model.section == item.section
        let soon = item.section.isComingSoon
        return Button { model.section = item.section } label: {
            HStack(spacing: compact ? 6 : 10) {
                Image(systemName: item.section.icon)
                    .font(.system(size: compact ? 13 : 15))
                    .frame(width: compact ? 18 : 22)
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                Text(item.section.title)
                    .font(.system(size: compact ? 12.5 : 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if let badge = item.badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(palette.fill, in: Capsule())
                }
            }
            .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 5 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? palette.active : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(soon ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(item.badge.map { "\(item.section.title), \($0) pendentes" } ?? item.section.title)
    }

    @ViewBuilder private var pinned: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label { caption("Apps fixados") } icon: {
                    Image(systemName: "pin").font(.system(size: 10)).foregroundStyle(palette.muted)
                }
                Spacer()
                Button("Gerenciar", action: manageApps)
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.accent)
            }
            if pinnedApps.isEmpty {
                Text("Nenhum app fixado.").font(.system(size: 11.5)).foregroundStyle(palette.muted)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(pinnedApps.prefix(5)) { app in
                        let label = Wire.visible(app.label, limit: 70)
                        Button { openApp(app) } label: {
                            Group {
                                if let icon = model.launcherIcons[app.id] {
                                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().padding(4)
                                } else {
                                    Text(String(label.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .background(model.launcherIcons[app.id] == nil ? NexusPalette.hueColor(Double(abs(app.id.hashValue % 360))) : palette.panel2,
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(label).accessibilityLabel("Abrir \(label)")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var clipboardCard: some View {
        let latest = model.clipboard.items.first
        return Button { model.section = .clipboard } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label { caption("Área de transferência") } icon: {
                    Image(systemName: "document.on.clipboard").font(.system(size: 10)).foregroundStyle(palette.muted)
                }
                Text(latest?.text ?? "Nada copiado ainda.")
                    .font(.system(size: 12.5)).lineLimit(3).multilineTextAlignment(.leading)
                    .foregroundStyle(latest == nil ? palette.muted : palette.ink)
                if let latest {
                    Text(latest.date, style: .relative).font(.system(size: 11)).foregroundStyle(palette.faint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Área de transferência")
    }
}
