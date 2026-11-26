import AppKit
import Social
import UniformTypeIdentifiers

@objc(MasterSyncShareController)
final class MasterSyncShareController: SLComposeServiceViewController {
    private let inbox = ShareInbox.directory
    private var selectedDestination: ShareInbox.Destination?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Enviar ao Android"
        selectedDestination = inbox.flatMap { ShareInbox.destination(in: $0) }
        placeholder = selectedDestination
            .map { "Mensagem opcional para \($0.name)" } ?? "Abra o MasterSync e selecione um Android."
    }

    override func isContentValid() -> Bool {
        guard let selectedDestination else { return false }
        return selectedDestination == inbox.flatMap { ShareInbox.destination(in: $0) }
    }

    override func didSelectPost() {
        guard let inbox, let destination = selectedDestination, destination == ShareInbox.destination(in: inbox) else {
            extensionContext?.cancelRequest(withError: CocoaError(.fileNoSuchFile))
            return
        }
        let manager = FileManager.default
        let id = UUID().uuidString
        let working = inbox.appendingPathComponent(".\(id)", isDirectory: true)
        let committed = inbox.appendingPathComponent(id, isDirectory: true)
        let providers = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        let comment = contentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task {
            do {
                guard providers.count <= 10 else { throw CocoaError(.fileWriteOutOfSpace) }
                try manager.createDirectory(at: working, withIntermediateDirectories: true)
                var texts = comment.isEmpty ? [] : [comment]
                for (index, provider) in providers.enumerated() {
                    let folder = working.appendingPathComponent("files/\(index)", isDirectory: true)
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                       let url = try await loadURL(provider, type: .fileURL), url.isFileURL {
                        try Self.copyFile(url, into: folder, name: url.lastPathComponent)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                              let url = try await loadURL(provider, type: .url), !url.isFileURL {
                        texts.append(url.absoluteString)
                    } else if let type = provider.registeredTypeIdentifiers.first(where: {
                        let type = UTType($0)
                        return type?.conforms(to: .image) == true || type?.conforms(to: .pdf) == true
                    }) {
                        try await stageRepresentation(provider, type: type, into: folder)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                              let text = try await loadText(provider), !text.isEmpty {
                        texts.append(text)
                    } else {
                        throw CocoaError(.fileReadUnsupportedScheme)
                    }
                }
                guard texts.joined(separator: "\n").utf8.count <= 2048 else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                guard !texts.isEmpty || !ShareInbox.items(in: working).isEmpty else {
                    throw CocoaError(.fileReadUnknown)
                }
                let request = ShareInbox.Request(peer: destination.peer, text: texts)
                try JSONEncoder().encode(request).write(to: working.appendingPathComponent("request.json"), options: .atomic)
                // Reveal the request only after every attachment has been copied.
                try manager.moveItem(at: working, to: committed)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                try? manager.removeItem(at: working)
                extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider, type: UTType) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item as? URL) }
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item as? String) }
            }
        }
    }

    private func stageRepresentation(_ provider: NSItemProvider, type: String, into folder: URL) async throws {
        let suggestedName = provider.suggestedName
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CocoaError(.fileReadUnknown) }
                    let name = suggestedName ?? url.lastPathComponent
                    let fileExtension = UTType(type)?.preferredFilenameExtension
                    let filename = (name as NSString).pathExtension.isEmpty
                        ? [name, fileExtension].compactMap { $0 }.joined(separator: ".") : name
                    try Self.copyFile(url, into: folder, name: filename)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func copyFile(_ url: URL, into folder: URL, name: String) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 4 * 1024 * 1024 * 1024 else { throw CocoaError(.fileReadUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = (name as NSString).lastPathComponent
        guard !filename.isEmpty, !filename.hasPrefix(".") else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(filename))
    }
}
