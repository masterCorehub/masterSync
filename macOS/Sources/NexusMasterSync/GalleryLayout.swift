import Foundation
import NexusCore

/// The tabs above the photo grid. They are views of the same filters the gallery already sends to the phone.
enum GalleryTab: CaseIterable {
    case all, photos, videos, screenshots, favorites

    var title: String {
        switch self {
        case .all: "Tudo"
        case .photos: "Fotos"
        case .videos: "Vídeos"
        case .screenshots: "Capturas"
        case .favorites: "Favoritas"
        }
    }

    var icon: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .photos: "photo"
        case .videos: "film"
        case .screenshots: "camera.viewfinder"
        case .favorites: "heart"
        }
    }

    /// Which tab the current filters amount to.
    static func current(mediaType: String, albumID: String, screenshotsAlbumID: String?, favoritesOnly: Bool) -> GalleryTab {
        if favoritesOnly { return .favorites }
        if let screenshotsAlbumID, !albumID.isEmpty, albumID == screenshotsAlbumID { return .screenshots }
        switch mediaType {
        case "image": return .photos
        case "video": return .videos
        default: return .all
        }
    }

    /// The phone's screenshots album, found by name since albums carry no kind.
    static func screenshotsAlbumID(in albums: [MediaAlbum]) -> String? {
        albums.first {
            let name = $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return name.contains("screenshot") || name.contains("captura")
        }?.id
    }
}

/// Text shown around the grid.
enum GalleryFormat {
    static func items(_ count: Int) -> String {
        switch count {
        case 0: "nenhum item"
        case 1: "1 item"
        default: "\(count) itens"
        }
    }

    /// The header subtitle: how many items are loaded, and that there may be more.
    static func subtitle(count: Int, more: Bool) -> String {
        guard count > 0 else { return "Fotos e vídeos do celular" }
        return more ? "\(count) itens carregados" : items(count)
    }

    /// The heading of a day: Hoje, Ontem, the weekday for the last week, then the full date. `detail` is the short date beside it.
    static func dayHeading(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> (title: String, detail: String?) {
        let format = Date.FormatStyle(locale: Locale(identifier: "pt_BR"), calendar: calendar, timeZone: calendar.timeZone)
        let short = date.formatted(format.day().month(.abbreviated)).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ")
        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 99
        switch days {
        case 0: return ("Hoje", short)
        case 1: return ("Ontem", short)
        case 2...6:
            let weekday = date.formatted(format.weekday(.wide))
            let name = String(weekday.split(separator: "-").first ?? Substring(weekday))
            return (name.prefix(1).uppercased(with: Locale(identifier: "pt_BR")) + name.dropFirst(), short)
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            let full = sameYear ? date.formatted(format.day().month(.wide)) : date.formatted(format.day().month(.wide).year())
            return (full, nil)
        }
    }

    static func tabCount(_ count: Int, more: Bool) -> String { more ? "\(count)+" : "\(count)" }

    /// A file size the way the design writes it: 2,4 MB, 840 KB.
    static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        return "\(max(1, Int((Double(bytes) / 1000).rounded()))) KB"
    }
}

/// The photos the person picked to save or favorite together.
struct GallerySelection: Equatable {
    private var ids: Set<String> = []

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }
    var all: Set<String> { ids }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: String) {
        if !ids.insert(id).inserted { ids.remove(id) }
    }

    func isGroupSelected(_ group: [String]) -> Bool { !group.isEmpty && group.allSatisfy(ids.contains) }

    /// Selects every item of a day; when the whole day is already selected, clears it.
    mutating func toggleGroup(_ group: [String]) {
        if isGroupSelected(group) { ids.subtract(group) } else { ids.formUnion(group) }
    }

    mutating func clear() { ids = [] }

    /// Forgets picks that are no longer in the list (a filter changed).
    mutating func prune(keeping available: Set<String>) { ids.formIntersection(available) }
}

/// The grid's tile sizes behind the zoom buttons.
enum GalleryZoom {
    static let minimumTile: [CGFloat] = [96, 140, 196]
    static let standard = 1

    static func clamped(_ step: Int) -> Int { min(max(step, 0), minimumTile.count - 1) }
}

/// Moving between photos in the viewer.
enum GalleryNavigation {
    static func neighbour(of id: String, in items: [MediaEntry], step: Int) -> MediaEntry? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let target = index + step
        return items.indices.contains(target) ? items[target] : nil
    }

    static func position(of id: String, in items: [MediaEntry]) -> String? {
        items.firstIndex(where: { $0.id == id }).map { "\($0 + 1) de \(items.count)" }
    }
}
