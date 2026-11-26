package com.nexus.mastersync.ui

import com.nexus.mastersync.ui.conversation.ChatMedia
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatMediaTest {
    @Test fun previewableImageRules() {
        assertTrue(ChatMedia.isPreviewableImage("image/png", 1024))
        assertTrue(ChatMedia.isPreviewableImage("IMAGE/JPEG", 1024))
        assertFalse(ChatMedia.isPreviewableImage("application/pdf", 1024))
        assertFalse(ChatMedia.isPreviewableImage("image/png", 0))
        assertFalse(ChatMedia.isPreviewableImage("image/png", 51L * 1024 * 1024))
    }

    @Test fun hugeImageIsDownsampled() {
        assertEquals(8, ChatMedia.sampleSize(12000, 9000))
        assertEquals(1, ChatMedia.sampleSize(800, 600))
        assertEquals(2, ChatMedia.sampleSize(2200, 1000))
    }

    @Test fun linkSpansSplitText() {
        assertEquals(
            listOf(ChatMedia.Span("veja ", null), ChatMedia.Span("https://a.com/x", "https://a.com/x"), ChatMedia.Span(" ok", null)),
            ChatMedia.linkSpans("veja https://a.com/x ok"))
    }

    @Test fun linkKeepsTrailingPunctuationOutside() {
        val spans = ChatMedia.linkSpans("(https://a.com/x).")
        assertEquals("https://a.com/x", spans.single { it.url != null }.url)
        assertEquals("(", spans.first().text)
        assertEquals(").", spans.last().text)
    }

    @Test fun textWithoutLinkIsOneSpan() =
        assertEquals(listOf(ChatMedia.Span("oi, tudo bem?", null)), ChatMedia.linkSpans("oi, tudo bem?"))

    @Test fun blankNamesFallBack() {
        assertEquals("Este celular", ChatMedia.senderName(true, "  ", "Mac Air"))
        assertEquals("Mac", ChatMedia.senderName(false, "S23", ""))
        assertEquals("S23", ChatMedia.senderName(true, "S23", "x"))
    }

    @Test fun captionOmitsMissingTime() {
        assertEquals("S23", ChatMedia.caption("S23", 0) { "14:32" })
        assertEquals("S23 · 14:32", ChatMedia.caption("S23", 5) { "14:32" })
    }

    @Test fun displaySizeMatchesWhatTheImageWillOccupy() {
        // 600x300 stays at its own size: 600 px / density 3 = 200 dp wide.
        assertEquals(ChatMedia.Size(200f, 100f), ChatMedia.displaySize(600, 300, density = 3f))
        // 4000x3000 is decoded at half size (2000 px) and capped to 280 dp wide.
        assertEquals(ChatMedia.Size(280f, 210f), ChatMedia.displaySize(4000, 3000, density = 3f))
    }

    @Test fun displaySizeOfInvalidDimensionsIsNull() {
        assertNull(ChatMedia.displaySize(0, 100, density = 3f))
        assertNull(ChatMedia.displaySize(100, -1, density = 3f))
        assertNull(ChatMedia.displaySize(100, 100, density = 0f))
    }
}
