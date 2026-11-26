package com.nexus.mastersync.ui.conversation

/** Pure rules for what the conversation shows: image previews, links and who sent an item. */
object ChatMedia {
    const val MAX_PREVIEW_BYTES = 50L * 1024 * 1024
    const val TARGET_EDGE = 1080
    private val previewMimes = setOf("image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif")
    private val url = Regex("""https?://\S+""")

    fun isPreviewableImage(mime: String, size: Long): Boolean =
        mime.lowercase() in previewMimes && size in 1..MAX_PREVIEW_BYTES

    /** Largest power of two that still leaves the longest edge at or above [targetEdge]. */
    fun sampleSize(width: Int, height: Int, targetEdge: Int = TARGET_EDGE): Int {
        var sample = 1
        val longest = maxOf(width, height)
        while (longest / (sample * 2) >= targetEdge) sample *= 2
        return sample
    }

    const val MAX_DISPLAY_DP = 280f

    data class Size(val widthDp: Float, val heightDp: Float)

    /**
     * The room a preview will take, so the placeholder can reserve it before decoding: the image is decoded at
     * [sampleSize] and shown at its own size, at most [MAX_DISPLAY_DP] wide.
     */
    fun displaySize(width: Int, height: Int, density: Float): Size? {
        if (width <= 0 || height <= 0 || density <= 0f) return null
        val decodedWidth = width / sampleSize(width, height)
        val widthDp = minOf(MAX_DISPLAY_DP, decodedWidth / density)
        return Size(widthDp, widthDp * height / width)
    }

    data class Span(val text: String, val url: String?)

    fun linkSpans(text: String): List<Span> {
        val spans = mutableListOf<Span>()
        var cursor = 0
        for (match in url.findAll(text)) {
            var link = match.value
            var end = match.range.last + 1
            while (link.isNotEmpty() && trailing(link)) {
                link = link.dropLast(1)
                end--
            }
            if (link.length <= "https://".length) continue
            if (match.range.first > cursor) spans += Span(text.substring(cursor, match.range.first), null)
            spans += Span(link, link)
            cursor = end
        }
        if (cursor < text.length) spans += Span(text.substring(cursor), null)
        return spans.ifEmpty { listOf(Span(text, null)) }
    }

    /** Punctuation that ends a sentence rather than a link; a ")" only when the link has no "(" for it. */
    private fun trailing(link: String): Boolean = when (link.last()) {
        '.', ',', ';', ':', '!', '?' -> true
        ')' -> link.count { it == ')' } > link.count { it == '(' }
        else -> false
    }

    fun senderName(outgoing: Boolean, localName: String, peerName: String): String =
        if (outgoing) localName.trim().ifEmpty { "Este celular" } else peerName.trim().ifEmpty { "Mac" }

    fun caption(name: String, time: Long, format: (Long) -> String): String =
        if (time > 0) "$name · ${format(time)}" else name
}
