package com.nexus.mastersync.ui

import com.nexus.mastersync.NexusController.ChatEntry
import com.nexus.mastersync.NexusController.Options
import com.nexus.mastersync.NexusController.Permissions
import com.nexus.mastersync.services.TransferQueue
import com.nexus.mastersync.ui.conversation.ChatBlocker
import com.nexus.mastersync.ui.conversation.TimelineItem
import com.nexus.mastersync.ui.conversation.allReceived
import com.nexus.mastersync.ui.conversation.chatBlocker
import com.nexus.mastersync.ui.conversation.conversationBanner
import com.nexus.mastersync.ui.conversation.timeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TimelineTest {
    private fun msg(peer: String, text: String, time: Long) = ChatEntry(peer, text, text, false, true, time)
    private fun received(peer: String, name: String) =
        TransferQueue.Received(TransferQueue.Item(name, name, "image/png", 10, "h"), File(name), peer)

    private fun label(item: TimelineItem) = when (item) {
        is TimelineItem.Message -> item.entry.text
        is TimelineItem.SentFile -> item.sent.name
        is TimelineItem.ReceivedFile -> item.received.item.name
    }

    @Test fun interleavesByTime() {
        val items = timeline("p", listOf(msg("p", "oi", 10)), listOf(TransferQueue.Sent("p", "a.pdf", 20, 1)),
            listOf(received("p", "x.png")), modified = { 15 })
        assertEquals(listOf("oi", "x.png", "a.pdf"), items.map(::label))
    }

    @Test fun legacyZeroTimeItemsComeFirstInOriginalOrder() {
        val items = timeline("p", listOf(msg("p", "a", 0), msg("p", "b", 0)),
            listOf(TransferQueue.Sent("p", "s.pdf", 5, 1)), emptyList(), modified = { 0 })
        assertEquals(listOf("a", "b", "s.pdf"), items.map(::label))
    }

    @Test fun filtersByPeerAndNullPeerIsEmpty() {
        val messages = listOf(msg("x", "for x", 1), msg("y", "for y", 2))
        val sent = listOf(TransferQueue.Sent("y", "y.pdf", 3, 1))
        val got = listOf(received("y", "y.png"))
        assertEquals(listOf("for x"), timeline("x", messages, sent, got, modified = { 4 }).map(::label))
        assertTrue(timeline(null, messages, sent, got, modified = { 4 }).isEmpty())
    }

    @Test fun sharedFileWithFilesOffIsBlocked() =
        assertEquals(ChatBlocker.FilesOff,
            chatBlocker(true, Options(files = false), Permissions(chat = true, files = true), wantsFiles = true))

    @Test fun filesOffOnMacIsBlocked() =
        assertEquals(ChatBlocker.FilesOff,
            chatBlocker(true, Options(files = true), Permissions(chat = true, files = false), wantsFiles = true))

    @Test fun disconnectedWinsOverEverything() =
        assertEquals(ChatBlocker.Disconnected, chatBlocker(false, Options(), Permissions(), wantsFiles = true))

    @Test fun chatOffOnMac() =
        assertEquals(ChatBlocker.ChatOffOnMac, chatBlocker(true, Options(), Permissions(chat = false), wantsFiles = false))

    @Test fun textOnlyIgnoresFiles() =
        assertNull(chatBlocker(true, Options(files = false), Permissions(chat = true), wantsFiles = false))

    @Test fun sharedFileBannerPrefersFileProblemOverChatOff() =
        assertEquals(ChatBlocker.FilesOff,
            conversationBanner(chat = ChatBlocker.ChatOffOnMac, files = ChatBlocker.FilesOff, hasSharedFile = true))

    @Test fun withoutSharedFileBannerShowsChatProblem() =
        assertEquals(ChatBlocker.ChatOffOnMac,
            conversationBanner(chat = ChatBlocker.ChatOffOnMac, files = ChatBlocker.FilesOff, hasSharedFile = false))

    @Test fun sharedFileWithOnlyChatOffShowsChatBanner() =
        assertEquals(ChatBlocker.ChatOffOnMac,
            conversationBanner(chat = ChatBlocker.ChatOffOnMac, files = null, hasSharedFile = true))

    @Test fun receivedFilesListsEveryPeerNewestFirst() {
        val files = allReceived(listOf(received("a", "old.png"), received("b", "new.png")),
            modified = { if (it.name == "new.png") 20 else 10 })
        assertEquals(listOf("new.png", "old.png"), files.map { it.received.item.name })
    }
}
