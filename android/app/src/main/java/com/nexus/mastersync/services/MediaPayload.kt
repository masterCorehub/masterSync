package com.nexus.mastersync.services

import org.json.JSONObject
import java.security.MessageDigest

/** What the active media session reports, in plain values so the message built from it can be tested. */
data class MediaSnapshot(
    val title: String?, val artist: String?, val album: String?,
    val year: Int, val track: Int, val tracks: Int,
    val durationMs: Long, val positionMs: Long, val updatedAt: Long, val speed: Float, val playing: Boolean?,
    val canSeek: Boolean, val canLike: Boolean, val liked: Boolean, val hasQueue: Boolean
)

object MediaPayload {
    const val MAX_QUEUE = 30
    private const val MAX_TEXT = 150

    /** Identifies the track's cover, so the Mac asks for the image once and never shows another track's. */
    fun artKey(title: String?, artist: String?, album: String?): String {
        if (title.isNullOrBlank() && artist.isNullOrBlank() && album.isNullOrBlank()) return ""
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("${title.orEmpty()}\u0000${artist.orEmpty()}\u0000${album.orEmpty()}".toByteArray())
        return digest.take(8).joinToString("") { "%02x".format(it) }
    }

    /** The playback position at [now]: it keeps moving while playing, and never leaves 0..duration. */
    fun positionNow(positionMs: Long, updatedAt: Long, now: Long, speed: Float, playing: Boolean, durationMs: Long): Long {
        val advanced = if (playing) positionMs + ((now - updatedAt) * speed).toLong() else positionMs
        val floored = maxOf(0L, advanced)
        return if (durationMs > 0) minOf(floored, durationMs) else floored
    }

    fun status(snapshot: MediaSnapshot, now: Long): JSONObject = JSONObject().apply {
        put("type", "mediaStatus")
        fun text(key: String, value: String?) { value?.trim()?.takeIf { it.isNotEmpty() }?.let { put(key, it.take(MAX_TEXT)) } }
        text("name", snapshot.title)
        text("text", snapshot.artist)
        text("artist", snapshot.artist)
        text("albumName", snapshot.album)
        if (snapshot.year > 0) put("year", snapshot.year)
        if (snapshot.track > 0) put("trackNumber", snapshot.track)
        if (snapshot.tracks > 0) put("trackCount", snapshot.tracks)
        if (snapshot.durationMs > 0) put("durationMs", snapshot.durationMs)
        snapshot.playing?.let { put("playing", it) }
        put("positionMs", positionNow(snapshot.positionMs, snapshot.updatedAt, now, snapshot.speed,
            snapshot.playing == true, snapshot.durationMs))
        put("speed", snapshot.speed.toDouble())
        artKey(snapshot.title, snapshot.artist, snapshot.album).takeIf { it.isNotEmpty() }?.let { put("artKey", it) }
        put("canSeek", snapshot.canSeek)
        put("canLike", snapshot.canLike)
        if (snapshot.canLike) put("liked", snapshot.liked)
        put("hasQueue", snapshot.hasQueue)
    }
}
