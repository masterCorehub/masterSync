import AppKit
import SwiftUI

/// An image in the conversation: a reduced copy loaded off the main thread, or the file name while it is not available.
struct ChatImage: View {
    let item: ReceivedFile
    let open: () -> Void
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Button(action: open) {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(item.offer.name)
            } else {
                Label(item.offer.name, systemImage: failed ? "doc" : "photo").lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .disabled(!FileManager.default.fileExists(atPath: item.url.path))
        .help(item.offer.name)
        .task(id: item.url) {
            let url = item.url
            // A row can be handed another file; never show the previous one's picture while this one loads.
            image = ThumbnailCache.cached(url: url, maxPixel: 560)
            failed = false
            guard image == nil else { return }
            let loaded = await Task.detached(priority: .utility) { ThumbnailCache.image(url: url, maxPixel: 560) }.value
            image = loaded
            failed = loaded == nil
        }
    }
}
