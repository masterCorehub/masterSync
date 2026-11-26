package com.nexus.mastersync.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaPayloadTest {
    private fun snapshot(
        title: String? = "Abracadabra", artist: String? = "Lady Gaga", album: String? = "Mayhem",
        year: Int = 2025, track: Int = 2, tracks: Int = 14, duration: Long = 223_000, position: Long = 56_000,
        updatedAt: Long = 0, speed: Float = 1f, playing: Boolean? = true,
        canSeek: Boolean = true, canLike: Boolean = true, liked: Boolean = false, hasQueue: Boolean = true
    ) = MediaSnapshot(title, artist, album, year, track, tracks, duration, position, updatedAt, speed, playing,
        canSeek, canLike, liked, hasQueue)

    @Test fun artKeyIsStableAndEmptyForNoData() {
        val key = MediaPayload.artKey("Abracadabra", "Lady Gaga", "Mayhem")
        assertEquals(key, MediaPayload.artKey("Abracadabra", "Lady Gaga", "Mayhem"))
        assertEquals(16, key.length)
        assertEquals("", MediaPayload.artKey("", null, ""))
    }

    @Test fun artKeyDiffersByAlbum() =
        assertNotEquals(MediaPayload.artKey("Intro", "A", "Primeiro"), MediaPayload.artKey("Intro", "A", "Segundo"))

    @Test fun positionAdvancesOnlyWhilePlaying() {
        assertEquals(3_000, MediaPayload.positionNow(1_000, 0, 2_000, 1f, playing = true, durationMs = 0))
        assertEquals(1_000, MediaPayload.positionNow(1_000, 0, 2_000, 1f, playing = false, durationMs = 0))
        assertEquals(5_000, MediaPayload.positionNow(1_000, 0, 2_000, 2f, playing = true, durationMs = 0))
    }

    @Test fun positionIsClamped() {
        assertEquals(10_000, MediaPayload.positionNow(9_000, 0, 5_000, 1f, playing = true, durationMs = 10_000))
        assertEquals(0, MediaPayload.positionNow(-5_000, 0, 0, 1f, playing = false, durationMs = 10_000))
        assertEquals(500_000, MediaPayload.positionNow(1_000, 0, 499_000, 1f, playing = true, durationMs = 0))
    }

    @Test fun statusKeepsLegacyFieldsAndAddsNewOnes() {
        val json = MediaPayload.status(snapshot(), now = 2_000)
        assertEquals("mediaStatus", json.getString("type"))
        assertEquals("Abracadabra", json.getString("name"))
        assertEquals("Lady Gaga", json.getString("text"))
        assertTrue(json.getBoolean("playing"))
        assertEquals("Lady Gaga", json.getString("artist"))
        assertEquals("Mayhem", json.getString("albumName"))
        assertEquals(2025, json.getInt("year"))
        assertEquals(2, json.getInt("trackNumber"))
        assertEquals(14, json.getInt("trackCount"))
        assertEquals(223_000, json.getLong("durationMs"))
        assertEquals(58_000, json.getLong("positionMs"))
        assertEquals(MediaPayload.artKey("Abracadabra", "Lady Gaga", "Mayhem"), json.getString("artKey"))
        assertTrue(json.getBoolean("canSeek"))
        assertTrue(json.getBoolean("canLike"))
        assertTrue(json.getBoolean("hasQueue"))
    }

    @Test fun statusOmitsUnknownValues() {
        val json = MediaPayload.status(
            snapshot(artist = null, album = null, year = 0, track = 0, tracks = 0, duration = 0, canLike = false,
                liked = true, playing = null), now = 0)
        for (key in listOf("artist", "text", "albumName", "year", "trackNumber", "trackCount", "durationMs", "liked", "playing")) {
            assertFalse(key, json.has(key))
        }
        assertEquals("Abracadabra", json.getString("name"))
    }

    @Test fun artReplyAlwaysCarriesTheKeyEvenWithoutAnImage() {
        val empty = MediaPayload.artReply("abc", null)
        assertEquals("mediaArt", empty.getString("type"))
        assertEquals("abc", empty.getString("artKey"))
        assertFalse(empty.has("data"))
        val full = MediaPayload.artReply("abc", "QUJD")
        assertEquals("image/jpeg", full.getString("mime"))
        assertEquals("QUJD", full.getString("data"))
    }

    @Test fun likedIsReportedOnlyWhenLikingIsPossible() {
        assertTrue(MediaPayload.status(snapshot(canLike = true, liked = true), 0).getBoolean("liked"))
        assertFalse(MediaPayload.status(snapshot(canLike = false, liked = true), 0).has("liked"))
    }
}
