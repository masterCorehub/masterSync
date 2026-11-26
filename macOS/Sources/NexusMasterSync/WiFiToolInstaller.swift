import Foundation
import NexusCore

enum WiFiToolInstaller {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let assets: [Asset]
    }

    static var homebrewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

    static func install(adb: Bool, scrcpy: Bool) async throws {
        if homebrewPath == nil { try await installHomebrew() }
        guard let brew = homebrewPath else {
            throw NexusError.transfer("O Homebrew não apareceu após a instalação. Tente novamente.")
        }
        let commands = (adb ? [["install", "--cask", "android-platform-tools"]] : [])
            + (scrcpy ? [["install", "scrcpy"]] : [])
        for arguments in commands {
            try run(brew, arguments, noninteractive: true)
        }
    }

    private static func installHomebrew() async throws {
        #if arch(arm64)
        let releaseURL = URL(string: "https://api.github.com/repos/Homebrew/brew/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: releaseURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NexusError.transfer("Não foi possível buscar o instalador oficial do Homebrew.")
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let asset = release.assets.first(where: { asset in
            let url = asset.browserDownloadURL
            return asset.name.hasPrefix("Homebrew") && asset.name.hasSuffix(".pkg")
                && url.scheme == "https" && url.host == "github.com"
                && url.path.hasPrefix("/Homebrew/brew/releases/download/")
        }) else {
            throw NexusError.transfer("A versão atual do Homebrew não disponibiliza um pacote oficial.")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = directory.appendingPathComponent("Homebrew.pkg")
        let (download, downloadResponse) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw NexusError.transfer("Não foi possível baixar o pacote do Homebrew.")
        }
        try FileManager.default.moveItem(at: download, to: package)

        // Let Gatekeeper validate the package before asking for administrator authorization.
        try run("/usr/sbin/spctl", ["--assess", "--type", "install", package.path])
        let script = """
        on run argv
            set packagePath to quoted form of item 1 of argv
            do shell script "/usr/sbin/installer -pkg " & packagePath & " -target /" with administrator privileges
        end run
        """
        try run("/usr/bin/osascript", ["-e", script, package.path])
        #else
        throw NexusError.transfer("O pacote oficial do Homebrew para instalação no guia requer Apple Silicon.")
        #endif
    }

    private static func run(_ executable: String, _ arguments: [String], noninteractive: Bool = false) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        if noninteractive {
            var environment = ProcessInfo.processInfo.environment
            environment["NONINTERACTIVE"] = "1"
            environment["PATH"] = "\(URL(fileURLWithPath: executable).deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
        }
        try process.run()
        let log = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: log, as: UTF8.self).split(separator: "\n").suffix(4).joined(separator: "\n")
            throw NexusError.transfer(detail.isEmpty ? "Não foi possível concluir a instalação." : detail)
        }
    }
}
