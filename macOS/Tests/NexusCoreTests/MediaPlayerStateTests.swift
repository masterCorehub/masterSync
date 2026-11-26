import NexusCore
@testable import NexusMasterSync
import XCTest

final class MediaPlayerStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func full(playing: Bool = true, position: Int64 = 56_000, duration: Int64 = 223_000) -> Message {
        var message = Message("mediaStatus")
        message.name = "Abracadabra"
        message.text = "Lady Gaga"
        message.artist = "Lady Gaga"
        message.albumName = "Mayhem"
        message.year = 2025
        message.trackNumber = 2
        message.trackCount = 14
        message.durationMs = duration
        message.positionMs = position
        message.speed = 1
        message.playing = playing
        message.artKey = "abc123"
        message.canSeek = true
        message.canLike = true
        message.liked = true
        message.hasQueue = true
        return message
    }

    func testLegacyMessageStillParses() {
        var message = Message("mediaStatus")
        message.name = "Faixa"
        message.text = "Artista"
        message.playing = false
        let state = MediaPlayerState(message: message, receivedAt: start)
        XCTAssertEqual(state.title, "Faixa")
        XCTAssertEqual(state.artist, "Artista")
        XCTAssertNil(state.album)
        XCTAssertNil(state.year)
        XCTAssertNil(state.trackLine)
        XCTAssertNil(state.durationMs)
        XCTAssertFalse(state.canSeek)
        XCTAssertFalse(state.isEmpty)
    }

    func testEmptyMessageIsEmpty() {
        XCTAssertTrue(MediaPlayerState(message: Message("mediaStatus"), receivedAt: start).isEmpty)
    }

    func testFullMessageParses() {
        let state = MediaPlayerState(message: full(), receivedAt: start)
        XCTAssertEqual(state.title, "Abracadabra")
        XCTAssertEqual(state.artist, "Lady Gaga")
        XCTAssertEqual(state.album, "Mayhem")
        XCTAssertEqual(state.year, 2025)
        XCTAssertEqual(state.trackLine, "2 de 14")
        XCTAssertEqual(state.durationMs, 223_000)
        XCTAssertEqual(state.artKey, "abc123")
        XCTAssertTrue(state.canSeek && state.canLike && state.liked && state.hasQueue)
    }

    func testTrackLineVariants() {
        func line(_ number: Int?, _ count: Int?) -> String? {
            var message = full()
            message.trackNumber = number
            message.trackCount = count
            return MediaPlayerState(message: message, receivedAt: start).trackLine
        }
        XCTAssertEqual(line(2, 14), "2 de 14")
        XCTAssertEqual(line(2, 0), "Faixa 2")
        XCTAssertEqual(line(2, nil), "Faixa 2")
        XCTAssertNil(line(0, 14))
        XCTAssertNil(line(nil, nil))
    }

    func testPositionAdvancesWhilePlayingAndClamps() {
        let playing = MediaPlayerState(message: full(), receivedAt: start)
        XCTAssertEqual(playing.position(at: start.addingTimeInterval(2)), 58_000)
        XCTAssertEqual(playing.position(at: start.addingTimeInterval(10_000)), 223_000)
        let paused = MediaPlayerState(message: full(playing: false), receivedAt: start)
        XCTAssertEqual(paused.position(at: start.addingTimeInterval(30)), 56_000)
    }

    func testPositionClampsToDuration() {
        let state = MediaPlayerState(message: full(position: 999_999, duration: 223_000), receivedAt: start)
        XCTAssertEqual(state.position(at: start), 223_000)
        let negative = MediaPlayerState(message: full(position: -10), receivedAt: start)
        XCTAssertEqual(negative.position(at: start), 0)
    }

    func testFractionWithoutDurationIsZero() {
        var message = full()
        message.durationMs = nil
        let state = MediaPlayerState(message: message, receivedAt: start)
        XCTAssertEqual(state.fraction(at: start), 0)
        XCTAssertEqual(MediaPlayerState(message: full(), receivedAt: start).fraction(at: start), 56_000.0 / 223_000.0, accuracy: 0.0001)
    }

    func testClockFormats() {
        XCTAssertEqual(MediaPlayerState.clock(56_000), "0:56")
        XCTAssertEqual(MediaPlayerState.clock(223_000), "3:43")
        XCTAssertEqual(MediaPlayerState.clock(3_723_000), "1:02:03")
        XCTAssertEqual(MediaPlayerState.clock(-5), "0:00")
    }

    func testSeekTargetClamps() {
        XCTAssertEqual(MediaPlayerState.seekTarget(fraction: 0.5, durationMs: 200_000), 100_000)
        XCTAssertEqual(MediaPlayerState.seekTarget(fraction: 1.7, durationMs: 200_000), 200_000)
        XCTAssertEqual(MediaPlayerState.seekTarget(fraction: -1, durationMs: 200_000), 0)
    }

    func testOutputFollowsAudioOnly() {
        XCTAssertEqual(MediaOutput.current(audioOnlyActive: true), .mac)
        XCTAssertEqual(MediaOutput.current(audioOnlyActive: false), .phone)
    }
}
