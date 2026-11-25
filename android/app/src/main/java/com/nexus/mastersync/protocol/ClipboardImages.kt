package com.nexus.mastersync.protocol

import org.json.JSONObject
import java.security.MessageDigest

internal class ClipboardImages(
    private val send: (JSONObject) -> Boolean,
    private val received: (ByteArray, String) -> Unit
) {
    private data class Outgoing(val id: String, val bytes: ByteArray, var next: Int = 0, var deadline: Long = deadline())
    private data class Incoming(val id: String, val mime: String, val hash: ByteArray, val bytes: ByteArray,
                                var offset: Int = 0, var deadline: Long = deadline())

    private var outgoing: Outgoing? = null
    private var incoming: Incoming? = null

    fun offer(bytes: ByteArray, mime: String) {
        if (bytes.size !in 1..LIMIT || mime !in EXTENSIONS) return
        val id = Wire.id()
        outgoing = Outgoing(id, bytes)
        if (!send(frame("clipboardImageOffer", id).put("size", bytes.size).put("mime", mime).put("hash", Wire.encode(hash(bytes))))) {
            outgoing = null
        }
    }

    fun receive(message: JSONObject) {
        val now = System.nanoTime()
        if (outgoing?.let { it.deadline < now } == true) outgoing = null
        if (incoming?.let { it.deadline < now } == true) incoming = null
        val id = message.optString("id")
        if (!Wire.validID(id)) return

        when (message.optString("type")) {
            "clipboardImageOffer" -> {
                val size = message.optInt("size", -1)
                val mime = message.optString("mime")
                if (size !in 1..LIMIT || mime !in EXTENSIONS) return
                val hash = runCatching { Wire.secret(message.optString("hash")) }.getOrNull() ?: return
                incoming = Incoming(id, mime, hash, ByteArray(size))
                acknowledge(id, 0)
            }
            "clipboardImageAck" -> {
                val current = outgoing?.takeIf { it.id == id } ?: return
                val offset = message.optInt("offset", -1)
                if (offset != current.next) return
                if (offset == current.bytes.size) {
                    outgoing = null
                    send(frame("clipboardImageDone", id))
                    return
                }
                val end = (offset + CHUNK).coerceAtMost(current.bytes.size)
                current.next = end
                current.deadline = deadline()
                val part = Wire.encode(current.bytes.copyOfRange(offset, end))
                if (!send(frame("clipboardImagePart", id).put("offset", offset).put("data", part))) outgoing = null
            }
            "clipboardImagePart" -> {
                val current = incoming?.takeIf { it.id == id } ?: return
                val body = message.optString("data")
                if (message.optInt("offset", -1) != current.offset || body.length > (CHUNK + 2) / 3 * 4) return
                val bytes = runCatching { Wire.decode(body) }.getOrNull() ?: return
                if (bytes.size !in 1..CHUNK || current.offset + bytes.size > current.bytes.size) return
                // Each offset is checked before copying so a duplicate cannot corrupt the image.
                bytes.copyInto(current.bytes, current.offset)
                current.offset += bytes.size
                current.deadline = deadline()
                acknowledge(id, current.offset)
            }
            "clipboardImageDone" -> {
                val current = incoming?.takeIf { it.id == id } ?: return
                incoming = null
                if (current.offset == current.bytes.size && MessageDigest.isEqual(hash(current.bytes), current.hash)) {
                    received(current.bytes, current.mime)
                }
            }
        }
    }

    fun cancelOutgoing() { outgoing = null }
    fun cancelIncoming() { incoming = null }
    fun reset() {
        cancelOutgoing()
        cancelIncoming()
    }

    private fun acknowledge(id: String, offset: Int) { send(frame("clipboardImageAck", id).put("offset", offset)) }
    private fun frame(type: String, id: String) = Wire.message(type).put("id", id)

    companion object {
        const val LIMIT = 8 * 1024 * 1024
        const val CHUNK = 128 * 1024
        val EXTENSIONS = mapOf("image/png" to "png", "image/jpeg" to "jpg", "image/gif" to "gif",
            "image/webp" to "webp", "image/heic" to "heic", "image/heif" to "heif")

        private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        private fun deadline() = System.nanoTime() + 20_000_000_000L
    }
}
