package com.nexus.mastersync

import com.nexus.mastersync.services.TransferQueue
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class HistoryCodecTest {
    @Test fun chatEntryRoundTripKeepsTime() {
        val entry = NexusController.ChatEntry("p", "id1", "oi", true, false, time = 1_700_000_000_000)
        assertEquals(entry, NexusController.ChatEntry.fromJson(entry.toJson()))
    }

    @Test fun legacyChatEntryWithoutTimeReadsAsZero() {
        val json = JSONObject("""{"peer":"p","id":"i","text":"t","outgoing":false,"confirmed":true}""")
        val entry = NexusController.ChatEntry.fromJson(json)
        assertEquals(0L, entry.time)
        assertEquals("t", entry.text)
        assertEquals(true, entry.confirmed)
    }

    @Test fun sentRoundTripKeepsTimeAndSize() {
        val sent = TransferQueue.Sent("p", "a.pdf", time = 5, size = 2_100_000)
        assertEquals(sent, TransferQueue.Sent.fromJson(sent.toJson()))
    }

    @Test fun legacySentWithoutTimeAndSizeReadsAsZero() {
        val sent = TransferQueue.Sent.fromJson(JSONObject("""{"peer":"p","name":"a.pdf"}"""))
        assertEquals(0L, sent.time)
        assertEquals(0L, sent.size)
        assertEquals("a.pdf", sent.name)
    }
}
