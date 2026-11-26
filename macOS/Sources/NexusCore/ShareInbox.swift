import Foundation

public enum ShareInbox {
    public struct Destination: Codable, Equatable {
        public let peer: String
        public let name: String
        public init(peer: String, name: String) {
            self.peer = peer
            self.name = name
        }
    }

    public struct Request: Codable {
        public let peer: String
        public let text: [String]
        public init(peer: String, text: [String]) {
            self.peer = peer
            self.text = text
        }
    }

    public static var directory: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MasterSyncShareGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container.appendingPathComponent("ShareInbox", isDirectory: true)
    }

    public static func destination(in directory: URL) -> Destination? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("destination.json")) else { return nil }
        return try? JSONDecoder().decode(Destination.self, from: data)
    }

    public static func items(in request: URL) -> [URL] {
        let payload = request.appendingPathComponent("files", isDirectory: true)
        return children(of: payload).sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { children(of: $0) }.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
                    .map { $0.isRegularFile == true && $0.isSymbolicLink != true } == true
            }
    }

    public static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])) ?? []
    }
}
