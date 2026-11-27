import AppKit
import Foundation

/// What can be done with a scanned page: save it, copy it. Kept apart from the window so it can be tested.
enum ScanActions {
    /// A path in [folder] for [name] that does not exist yet: "a.jpg", then "a 2.jpg", "a 3.jpg"…
    /// Only the last component of [name] is used, so a name can never point outside the folder.
    static func uniqueDestination(name: String, in folder: URL) -> URL {
        let clean = (name as NSString).lastPathComponent.isEmpty ? "Digitalização" : (name as NSString).lastPathComponent
        let base = (clean as NSString).deletingPathExtension, ext = (clean as NSString).pathExtension
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(clean)
        var number = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    /// The newest page that has not been seen yet (pages are listed newest first), or nil when nothing new arrived.
    static func newPage(known: Set<String>, current: [String]) -> String? { current.first { !known.contains($0) } }

    /// Copies the page into [folder] without overwriting anything, and returns where it went.
    @discardableResult
    static func save(_ file: URL, to folder: URL) throws -> URL {
        let destination = uniqueDestination(name: file.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    /// Puts the picture (to paste into documents and chats) and the file itself on the pasteboard.
    @discardableResult
    static func copy(_ file: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path), let image = NSImage(contentsOf: file) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([image, file as NSURL])
    }
}
