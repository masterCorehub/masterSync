import Foundation
import NexusCore

/// The phone's internal storage as seen from the Mac: folders, files, free space, and downloads. It talks to the phone
/// through two closures (ADB over Wi-Fi in the app, fakes in tests) and only ever hands them validated paths.
@MainActor
final class PixelFilesModel: ObservableObject {
    @Published private(set) var path = PixelPath.root
    @Published private(set) var entries: [PixelListing.Entry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var storage: PixelStorage?
    @Published private(set) var segments: [PixelStorage.Segment] = []
    @Published private(set) var folderCounts: [String: Int] = [:]
    @Published private(set) var selection = Set<String>()
    @Published private(set) var downloading = false
    @Published private(set) var downloadMessage: String?
    @Published private(set) var lastDownloaded: [URL] = []

    /// Runs one command in the phone's shell and returns what it printed.
    var shell: (@Sendable (String) async throws -> String)?
    /// Copies a path from the phone to the Mac.
    var pull: (@Sendable (String, URL) async throws -> Void)?
    let downloads: URL
    private var generation = 0

    init(downloads: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
        .appendingPathComponent("MasterSync", isDirectory: true) ?? FileManager.default.temporaryDirectory) {
        self.downloads = downloads
    }

    var isAvailable: Bool { shell != nil }

    // MARK: Folders

    func open(_ target: String) async {
        guard PixelPath.isSafe(target) else {
            error = "Essa pasta não pode ser aberta."
            return
        }
        generation += 1
        let mine = generation
        path = target
        selection = []
        error = nil
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let output = try await run("ls -la \(PixelPath.quoted(target))")
            guard mine == generation else { return }
            entries = PixelListing.parse(output)
        } catch {
            guard mine == generation else { return }
            entries = []
            self.error = error.localizedDescription
        }
    }

    func reload() async { await open(path) }

    func enter(_ entry: PixelListing.Entry) async {
        guard entry.isDirectory, entry.isSafe, let next = PixelPath.child(path, entry.name) else { return }
        await open(next)
    }

    func goUp() async {
        guard path != PixelPath.root else { return }
        await open(PixelPath.parent(path))
    }

    private func run(_ command: String) async throws -> String {
        guard let shell else { throw NexusError.transfer("Configure o controle por Wi‑Fi (tela Dispositivos) para ver os arquivos do celular.") }
        return try await shell(command)
    }

    // MARK: Storage

    /// Free space, what the main folders take, and how many items each top folder has. Any part may fail on its own.
    func loadOverview() async {
        if let output = try? await run("df -k /sdcard") { storage = PixelStorage.parse(df: output) }
        if let storage {
            let measured = (try? await run("du -sk /sdcard/DCIM /sdcard/Pictures /sdcard/Movies /sdcard/Music /sdcard/Download /sdcard/Documents /sdcard/Android/media/com.whatsapp 2>/dev/null"))
                .map(PixelStorage.parts(fromDu:)) ?? []
            segments = PixelStorage.breakdown(storage, parts: measured)
        }
        if let output = try? await run(#"cd /sdcard && for d in */; do n=$(ls -A "$d" 2>/dev/null | wc -l); echo "${d%/} $n"; done"#) {
            folderCounts = PixelListing.parseCounts(output)
        }
    }

    // MARK: Selection and download

    func toggle(_ entry: PixelListing.Entry) {
        guard entry.isSafe else { return }
        if !selection.insert(entry.name).inserted { selection.remove(entry.name) }
    }

    func clearSelection() { selection = [] }

    func downloadSelection() async {
        guard let pull, !selection.isEmpty, !downloading else { return }
        let chosen = entries.filter { selection.contains($0.name) && $0.isSafe }
        downloading = true
        downloadMessage = "Baixando…"
        lastDownloaded = []
        defer { downloading = false }
        do { try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true) } catch {
            downloadMessage = "Não foi possível criar a pasta de downloads."
            return
        }
        var done: [URL] = []
        for entry in chosen {
            guard let remote = PixelPath.child(path, entry.name) else { continue }
            let local = ScanActions.uniqueDestination(name: entry.name, in: downloads)
            do {
                try await pull(remote, local)
                done.append(local)
            } catch {
                downloadMessage = "Não foi possível baixar \(entry.name): \(error.localizedDescription)"
                lastDownloaded = done
                return
            }
        }
        lastDownloaded = done
        selection = []
        downloadMessage = "\(GalleryFormat.items(done.count)) \(done.count == 1 ? "baixado" : "baixados") para Downloads/MasterSync."
    }
}
