import Foundation
import NexusCore

/// Paths on the phone's internal storage. Everything that reaches the ADB shell goes through here first.
enum PixelPath {
    static let root = "/sdcard"
    private static let forbidden = CharacterSet(charactersIn: "'\"$`;&|<>\\*?\n\r\t").union(.controlCharacters)

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && name.rangeOfCharacter(from: forbidden) == nil
    }

    /// Inside the internal storage, with no way out and nothing the shell could read as a command.
    static func isSafe(_ path: String) -> Bool {
        guard path == root || path.hasPrefix(root + "/") else { return false }
        guard path.rangeOfCharacter(from: forbidden) == nil else { return false }
        return !path.split(separator: "/").contains("..")
    }

    static func quoted(_ path: String) -> String { "'" + path + "'" }

    static func child(_ parent: String, _ name: String) -> String? {
        guard isSafe(parent), isSafeName(name) else { return nil }
        return parent + "/" + name
    }

    static func parent(_ path: String) -> String {
        guard path != root, let slash = path.lastIndex(of: "/") else { return root }
        let up = String(path[..<slash])
        return up.count < root.count ? root : up
    }

    static func breadcrumbs(_ path: String) -> [(title: String, path: String)] {
        var crumbs: [(title: String, path: String)] = [("Armazenamento interno", root)]
        guard isSafe(path), path != root else { return crumbs }
        var current = root
        for part in path.dropFirst(root.count + 1).split(separator: "/") {
            current += "/" + part
            crumbs.append((String(part), current))
        }
        return crumbs
    }
}

/// What `ls -la` printed for one folder.
enum PixelListing {
    struct Entry: Identifiable, Equatable {
        let name: String
        let isDirectory: Bool
        let size: Int64
        let modified: Date?
        let isSafe: Bool
        var id: String { name }
    }

    private static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format
    }()

    static func parse(_ output: String) -> [Entry] {
        var entries: [Entry] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard fields.count == 8, let kind = fields[0].first, "d-lcbsp".contains(kind), let size = Int64(fields[4]),
                  fields[5].count == 10, fields[5].contains("-") else { continue }
            var name = String(fields[7])
            if kind == "l", let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
            guard !name.hasPrefix("."), name != "" else { continue }
            let modified = dateFormat.date(from: "\(fields[5]) \(fields[6].prefix(5))")
            entries.append(Entry(name: name, isDirectory: kind == "d", size: max(size, 0), modified: modified, isSafe: PixelPath.isSafeName(name)))
        }
        return entries.sorted {
            $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Lines of "name count" from the item-count loop.
    static func parseCounts(_ output: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let space = line.lastIndex(of: " "), let count = Int(line[line.index(after: space)...]) else { continue }
            let name = line[..<space].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { counts[name] = count }
        }
        return counts
    }
}

struct PixelStorage: Equatable {
    struct Segment: Identifiable, Equatable {
        let title: String
        let bytes: Int64
        let fraction: Double
        var id: String { title }
    }

    let total: Int64
    let used: Int64
    let free: Int64

    /// Reads `df -k /sdcard`.
    static func parse(df output: String) -> PixelStorage? {
        guard let line = output.split(whereSeparator: \.isNewline).last else { return nil }
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 6, fields[4].hasSuffix("%"), let total = Int64(fields[1]), let used = Int64(fields[2]),
              let free = Int64(fields[3]), total > 0 else { return nil }
        return PixelStorage(total: total * 1024, used: used * 1024, free: free * 1024)
    }

    /// The bar: the folders that could be measured, then what is left as "Outros e sistema". Never more than what is used.
    static func breakdown(_ storage: PixelStorage, parts: [(String, Int64)]) -> [Segment] {
        var remaining = max(storage.used, 0)
        var segments: [Segment] = []
        for (title, bytes) in parts {
            let counted = min(max(bytes, 0), remaining)
            guard counted > 0 else { continue }
            remaining -= counted
            segments.append(Segment(title: title, bytes: counted, fraction: Double(counted) / Double(max(storage.total, 1))))
        }
        if remaining > 0 {
            segments.append(Segment(title: "Outros e sistema", bytes: remaining, fraction: Double(remaining) / Double(max(storage.total, 1))))
        }
        return segments
    }

    /// Folders measured by `du -sk`, grouped the way the bar names them, in the order they first appear.
    static func parts(fromDu output: String) -> [(String, Int64)] {
        func group(_ path: String) -> String? {
            switch path {
            case "/sdcard/DCIM", "/sdcard/Pictures", "/sdcard/Movies": return "Fotos e vídeos"
            case "/sdcard/Music": return "Música"
            case "/sdcard/Download", "/sdcard/Documents": return "Documentos e downloads"
            case "/sdcard/Android/media/com.whatsapp": return "WhatsApp"
            default: return nil
            }
        }
        var order: [String] = []
        var totals: [String: Int64] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, let kilobytes = Int64(fields[0]), let title = group(String(fields[1])) else { continue }
            if totals[title] == nil { order.append(title) }
            totals[title, default: 0] += kilobytes * 1024
        }
        return order.map { ($0, totals[$0] ?? 0) }
    }

    static func gigabytes(_ bytes: Int64) -> String {
        let value = Double(max(bytes, 0)) / 1_000_000_000
        if value >= 10 || value == value.rounded() { return "\(Int(value.rounded())) GB" }
        return String(format: "%.1f GB", value).replacingOccurrences(of: ".", with: ",")
    }
}

enum TransferFilter: CaseIterable {
    case all, sent, received

    var title: String {
        switch self {
        case .all: "Todas"
        case .sent: "Enviadas"
        case .received: "Recebidas"
        }
    }
}

struct TransferRow: Identifiable, Equatable {
    enum Direction { case sent, received }

    let id: String
    /// The id the file has in the transfer lists, for removing it.
    let fileID: String
    let name: String
    let direction: Direction
    let size: Int64
    let date: Date?
    /// nil once the transfer is done.
    let fraction: Double?
    let verifying: Bool
    let deviceName: String
    let url: URL?
}

enum TransferRows {
    static func make(progress: [FileTransfers.Progress], sent: [ReceivedFile], received: [ReceivedFile],
                     peerNames: [String: String], filter: TransferFilter) -> [TransferRow] {
        func wanted(_ direction: TransferRow.Direction) -> Bool {
            filter == .all || (filter == .sent) == (direction == .sent)
        }
        let live = progress.compactMap { item -> TransferRow? in
            let direction: TransferRow.Direction = item.sending ? .sent : .received
            guard wanted(direction) else { return nil }
            return TransferRow(id: "live-" + item.id, fileID: item.id, name: item.name, direction: direction, size: item.size, date: nil,
                               fraction: min(1, max(0, item.fraction)), verifying: item.verifying,
                               deviceName: peerNames[item.peer] ?? "Celular", url: nil)
        }
        func finished(_ files: [ReceivedFile], _ direction: TransferRow.Direction) -> [TransferRow] {
            guard wanted(direction) else { return [] }
            return files.map {
                TransferRow(id: "\(direction == .sent ? "sent" : "received")-" + $0.id, fileID: $0.id, name: $0.offer.name, direction: direction,
                            size: $0.offer.size, date: $0.date == .distantPast ? nil : $0.date, fraction: nil, verifying: false,
                            deviceName: peerNames[$0.peerID] ?? "Celular", url: $0.url)
            }
        }
        let done = (finished(sent, .sent) + finished(received, .received))
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return live + done
    }

    static func sizeText(_ bytes: Int64) -> String { GalleryFormat.size(bytes) }
}

/// Folders cannot be sent as they are, so they travel as a .zip.
enum FolderZip {
    static func zip(_ folder: URL, into directory: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NexusError.transfer("Só pastas podem ser compactadas.")
        }
        let destination = ScanActions.uniqueDestination(name: folder.lastPathComponent + ".zip", in: directory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NexusError.transfer("Não foi possível compactar a pasta.") }
        return destination
    }
}
