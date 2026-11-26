import CoreGraphics
import Foundation

/// How a scrcpy 5.0.1 server is started, and how a click on the phone view maps to a pixel on the phone.
enum ScrcpyLaunch {
    nonisolated static func socketName(scid: UInt32) -> String { "scrcpy_" + String(format: "%08x", scid) }

    /// The `adb shell` arguments that start the server. nil when [version] could be used to inject something else.
    nonisolated static func serverArguments(version: String, scid: UInt32, maxSize: Int, maxFPS: Int, bitRate: Int) -> [String]? {
        guard version.range(of: #"\A[0-9]+(\.[0-9]+)*\z"#, options: .regularExpression) != nil else { return nil }
        return ["CLASSPATH=/data/local/tmp/scrcpy-server.jar", "app_process", "/", "com.genymobile.scrcpy.Server", version,
                "scid=" + String(format: "%08x", scid), "log_level=info", "tunnel_forward=true", "audio=false", "control=true",
                "video_codec=h264", "max_size=\(maxSize)", "max_fps=\(maxFPS)", "video_bit_rate=\(bitRate)",
                "clipboard_autosync=false", "cleanup=true"]
    }

    /// The server file that ships with the installed scrcpy: `<prefix>/share/scrcpy/scrcpy-server`.
    nonisolated static func serverURL(forScrcpy executable: String) -> URL? {
        let given = URL(fileURLWithPath: executable)
        for base in [given.resolvingSymlinksInPath(), given] {
            let candidate = base.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("share/scrcpy/scrcpy-server")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The pixel of the phone under [viewPoint], with the video fitted into the view keeping its proportions.
    /// nil in the bars around the video.
    nonisolated static func devicePoint(viewPoint: CGPoint, viewSize: CGSize, videoSize: CGSize) -> (x: Int32, y: Int32)? {
        guard viewSize.width > 0, viewSize.height > 0, videoSize.width > 0, videoSize.height > 0 else { return nil }
        let scale = min(viewSize.width / videoSize.width, viewSize.height / videoSize.height)
        let shown = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let origin = CGPoint(x: (viewSize.width - shown.width) / 2, y: (viewSize.height - shown.height) / 2)
        let local = CGPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)
        let slack: CGFloat = 0.5
        guard local.x >= -slack, local.y >= -slack, local.x <= shown.width + slack, local.y <= shown.height + slack else { return nil }
        let x = min(max(local.x / scale, 0), videoSize.width - 1)
        let y = min(max(local.y / scale, 0), videoSize.height - 1)
        return (Int32(x), Int32(y))
    }
}
