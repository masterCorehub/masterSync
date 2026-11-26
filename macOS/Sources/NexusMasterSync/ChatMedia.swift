import AppKit
import ImageIO

/// What the conversation shows for a file or message: image previews and who sent it.
enum ChatMedia {
    nonisolated static let previewMimes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif"
    ]

    nonisolated static func isImage(mime: String) -> Bool { previewMimes.contains(mime.lowercased()) }

    nonisolated static func senderName(outgoing: Bool, local: String, peer: String) -> String {
        let name = (outgoing ? local : peer).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (outgoing ? "Este Mac" : "Celular") : name
    }

    /// A reduced copy that keeps the aspect ratio; nil when the file is not a decodable image.
    nonisolated static func thumbnail(url: URL, maxPixel: Int) -> NSImage? {
        thumbnailPixels(url: url, maxPixel: maxPixel).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    /// The thumbnail pixels themselves, whose size is exact whatever the screen scale.
    nonisolated static func thumbnailPixels(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
