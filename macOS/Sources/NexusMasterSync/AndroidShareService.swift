import AppKit
import NexusCore

@MainActor
final class AndroidShareService: NSObject {
    var send: (([URL], String?) -> String?)?
    var reportFailure: ((String) -> Void)?

    @objc(sendToAndroid:userData:error:)
    func sendToAndroid(_ board: NSPasteboard, userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (board.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        let fileURLs = urls.filter(\.isFileURL)
        let legacyPaths = board.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]
        let files = fileURLs.isEmpty ? (legacyPaths ?? []).map { URL(fileURLWithPath: $0) } : fileURLs
        let links = urls.filter { !$0.isFileURL }.map(\.absoluteString)
        let text = links.isEmpty ? board.string(forType: .string) : links.joined(separator: "\n")
        let message: String?
        if let send { message = send(files, files.isEmpty ? text : nil) }
        else { message = "Abra o MasterSync e selecione um Android." }
        if let message {
            error.pointee = message as NSString
            reportFailure?(message)
        }
    }
}
