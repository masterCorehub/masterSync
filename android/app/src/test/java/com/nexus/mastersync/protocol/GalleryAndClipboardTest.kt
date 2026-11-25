package com.nexus.mastersync.protocol

import com.nexus.mastersync.services.GalleryQuery
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

class GalleryAndClipboardTest {
    @Test fun filenameWildcardsAreLiteralAndDateRangeIsBound() {
        val name = "100%_capa"
        val query = GalleryQuery.from(Wire.message("galleryList")
            .put("query", name).put("album", "123").put("mime", "video")
            .put("addedFrom", 1_700_000_000L).put("addedBefore", 1_700_086_400L)
            .put("order", "name").put("offset", 24))
        assertFalse(query.selection.contains(name))
        assertTrue(query.selection.contains("media_type = 3"))
        assertTrue(query.selection.contains("date_added >= ? AND date_added < ?"))
        assertArrayEquals(arrayOf("123", "%100\\%\\_capa%", "1700000000", "1700086400"), query.values)
        assertArrayEquals(arrayOf("_display_name", "_id"), query.sortColumns)
        assertTrue(query.ascending)
        assertEquals(24, query.offset)
    }

    @Test fun unsupportedSortFallsBackToDate() {
        val query = GalleryQuery.from(Wire.message("galleryList").put("order", "random()").put("offset", -4))
        assertArrayEquals(arrayOf("date_added", "_id"), query.sortColumns)
        assertFalse(query.ascending)
        assertEquals(0, query.offset)
    }

    @Test fun clipboardReassemblesMultipleBlocksAndRejectsCorruption() {
        val source = ByteArray(ClipboardImages.CHUNK * 2 + 29) { index -> (index % 251).toByte() }
        var received: ByteArray? = null
        lateinit var sender: ClipboardImages
        lateinit var receiver: ClipboardImages
        var corrupt = false
        sender = ClipboardImages({ message ->
            if (corrupt && message.optString("type") == "clipboardImagePart" && message.optInt("offset") == 0) {
                val data = Wire.decode(message.getString("data"))
                data[0] = 42
                message.put("data", Wire.encode(data))
            }
            receiver.receive(message)
            true
        }, { _, _ -> error("Unexpected clipboard echo") })
        receiver = ClipboardImages({ message -> sender.receive(message); true }, { bytes, type ->
            assertEquals("image/png", type)
            received = bytes
        })
        sender.offer(source, "image/png")
        assertArrayEquals(source, received)
        received = null
        corrupt = true
        sender.offer(source, "image/png")
        assertNull(received)
    }
}
