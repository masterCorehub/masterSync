import Foundation
import NexusCore

/// Messages the Mac sends to the phone's media session, and the rules for the cover that comes back.
enum MediaCommands {
    nonisolated static func command(_ name: String, positionMs: Int64? = nil, queueId: Int64? = nil) -> Message {
        var message = Message("mediaCommand")
        message.message = name
        message.positionMs = positionMs
        message.queueId = queueId
        return message
    }

    /// Ask for a cover once per track: not when there is no key, and not when it is cached or already asked for.
    nonisolated static let maxArtAttempts = 4

    /// A few attempts, because the phone may not have the picture yet when the track starts.
    nonisolated static func shouldRequestArt(key: String?, cached: Set<String>, pending: Set<String>, attempts: Int = 0) -> Bool {
        guard let key, !key.isEmpty, attempts < maxArtAttempts else { return false }
        return !cached.contains(key) && !pending.contains(key)
    }

    /// A queue item id is only meaningful on the phone that listed it.
    nonisolated static func queueBelongs(queuePeer: String?, selected: String?) -> Bool {
        guard let queuePeer, let selected else { return false }
        return queuePeer == selected
    }

    /// The cover bytes, only if they belong to the track playing now and are a small, decodable image.
    nonisolated static func acceptsArt(key: String?, currentKey: String?, data: String) -> Data? {
        guard let key, !key.isEmpty, key == currentKey else { return nil }
        return NexusModel.acceptedIcon(data)
    }
}
