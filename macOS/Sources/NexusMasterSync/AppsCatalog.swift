import Foundation
import NexusCore

/// Pure helpers for the Apps screen: search, pins and what the side bar shows.
enum AppsCatalog {
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Apps whose name or package matches, ignoring accents and case. An empty query keeps everything.
    static func filter(_ apps: [AndroidApp], query: String) -> [AndroidApp] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return apps }
        return apps.filter { normalize($0.label).contains(needle) || normalize($0.component).contains(needle) }
    }

    /// The pinned apps in the order they were pinned; ids that are no longer installed are skipped.
    static func pinned(_ apps: [AndroidApp], ids: [String]) -> [AndroidApp] {
        ids.compactMap { id in apps.first { $0.id == id } }
    }

    /// Pins an app at the end, or unpins it when it is already pinned.
    static func toggled(_ ids: [String], id: String) -> [String] {
        ids.contains(id) ? ids.filter { $0 != id } : ids + [id]
    }

    /// The first five pinned apps appear in the side bar and in the menu bar.
    static func sidebarPins(_ pinned: [AndroidApp]) -> [AndroidApp] { Array(pinned.prefix(5)) }
}
