import Foundation

enum SidebarGroup {
    case main, soon, footer
}

struct SidebarItem: Identifiable, Equatable {
    let section: Section
    let badge: Int?
    var id: String { section.id }
}

/// What the side bar lists in each group. `badges` carries pending counts; zero shows nothing.
func sidebarItems(group: SidebarGroup, badges: [Section: Int]) -> [SidebarItem] {
    let sections: [Section] = switch group {
    case .main: [.overview, .conversation, .notifications, .gallery, .documents, .files, .remote, .apps]
    case .soon: [.calls, .sms, .webcam]
    case .footer: [.devices, .settings]
    }
    return sections.map { SidebarItem(section: $0, badge: badges[$0].flatMap { $0 > 0 ? $0 : nil }) }
}
