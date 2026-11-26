import AppKit

/// Thumbnails already decoded, so a row that scrolls back into view shows its image at once instead of decoding again.
enum ThumbnailCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    private nonisolated static func key(_ url: URL, _ maxPixel: Int) -> NSString { "\(url.path)#\(maxPixel)" as NSString }

    nonisolated static func cached(url: URL, maxPixel: Int) -> NSImage? { cache.object(forKey: key(url, maxPixel)) }

    /// The cached thumbnail, or a fresh one. A file that is not an image is not cached, so it is looked at again later.
    nonisolated static func image(url: URL, maxPixel: Int) -> NSImage? {
        if let hit = cached(url: url, maxPixel: maxPixel) { return hit }
        guard let image = ChatMedia.thumbnail(url: url, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key(url, maxPixel))
        return image
    }
}
