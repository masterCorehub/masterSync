import Foundation
import NexusCore

/// What the Android media session last reported, ready to draw: text lines, progress and what the player supports.
struct MediaPlayerState: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let year: Int?
    let trackLine: String?
    let durationMs: Int64?
    let positionMs: Int64
    let speed: Double
    let playing: Bool?
    let receivedAt: Date
    let artKey: String?
    let canSeek: Bool
    let canLike: Bool
    let liked: Bool
    let hasQueue: Bool

    var isEmpty: Bool { title == nil && artist == nil }

    init(message: Message, receivedAt: Date) {
        func text(_ value: String?) -> String? {
            let trimmed = value.map { Wire.visible($0, limit: 150).trimmingCharacters(in: .whitespacesAndNewlines) }
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        title = text(message.name)
        artist = text(message.artist ?? message.text)
        album = text(message.albumName)
        year = message.year.flatMap { $0 > 0 ? $0 : nil }
        switch (message.trackNumber ?? 0, message.trackCount ?? 0) {
        case (let number, let count) where number > 0 && count > 0: trackLine = "\(number) de \(count)"
        case (let number, _) where number > 0: trackLine = "Faixa \(number)"
        default: trackLine = nil
        }
        durationMs = message.durationMs.flatMap { $0 > 0 ? $0 : nil }
        positionMs = message.positionMs ?? 0
        speed = message.speed ?? 1
        playing = message.playing
        self.receivedAt = receivedAt
        artKey = text(message.artKey)
        canSeek = message.canSeek == true
        canLike = message.canLike == true
        liked = message.liked == true
        hasQueue = message.hasQueue == true
    }

    /// Where the track is at [date]: it moves on by itself while playing, and never leaves 0...duration.
    func position(at date: Date) -> Int64 {
        let elapsed = playing == true ? Int64(date.timeIntervalSince(receivedAt) * 1000 * speed) : 0
        let moved = max(0, positionMs + elapsed)
        return durationMs.map { min(moved, $0) } ?? moved
    }

    func fraction(at date: Date) -> Double {
        guard let durationMs else { return 0 }
        return min(1, max(0, Double(position(at: date)) / Double(durationMs)))
    }

    nonisolated static func clock(_ ms: Int64) -> String {
        let total = max(0, ms) / 1000
        let seconds = total % 60, minutes = (total / 60) % 60, hours = total / 3600
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes + hours * 60, seconds)
    }

    nonisolated static func seekTarget(fraction: Double, durationMs: Int64) -> Int64 {
        Int64(min(1, max(0, fraction)) * Double(durationMs))
    }
}

/// Where the phone's sound comes out.
enum MediaOutput: Equatable {
    case phone, mac

    nonisolated static func current(audioOnlyActive: Bool) -> MediaOutput { audioOnlyActive ? .mac : .phone }
}
