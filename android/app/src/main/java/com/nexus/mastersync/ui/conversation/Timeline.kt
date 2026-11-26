package com.nexus.mastersync.ui.conversation

import com.nexus.mastersync.NexusController
import com.nexus.mastersync.services.TransferQueue
import java.io.File

sealed interface TimelineItem {
    val time: Long

    data class Message(val entry: NexusController.ChatEntry) : TimelineItem {
        override val time get() = entry.time
    }

    data class SentFile(val sent: TransferQueue.Sent) : TimelineItem {
        override val time get() = sent.time
    }

    data class ReceivedFile(val received: TransferQueue.Received, override val time: Long) : TimelineItem
}

/**
 * Messages and files exchanged with [peer], oldest first. History saved before times were recorded has time 0,
 * so the stable sort keeps it at the top in its original order.
 */
fun timeline(peer: String?, messages: List<NexusController.ChatEntry>, sent: List<TransferQueue.Sent>,
             received: List<TransferQueue.Received>, modified: (File) -> Long = File::lastModified): List<TimelineItem> {
    if (peer == null) return emptyList()
    return (messages.filter { it.peer == peer }.map { TimelineItem.Message(it) } +
        sent.filter { it.peer == peer }.map { TimelineItem.SentFile(it) } +
        received.filter { it.peer == peer }.map { TimelineItem.ReceivedFile(it, modified(it.file)) })
        .sortedBy { it.time }
}

enum class ChatBlocker { Disconnected, ChatOffOnMac, FilesOff }

fun chatBlocker(connected: Boolean, options: NexusController.Options, permissions: NexusController.Permissions,
                wantsFiles: Boolean): ChatBlocker? = when {
    !connected -> ChatBlocker.Disconnected
    !permissions.chat -> ChatBlocker.ChatOffOnMac
    wantsFiles && !(options.files && permissions.files) -> ChatBlocker.FilesOff
    else -> null
}

/** With a shared file waiting, the file problem is the one that blocks the user's next step, so it wins. */
fun conversationBanner(chat: ChatBlocker?, files: ChatBlocker?, hasSharedFile: Boolean): ChatBlocker? =
    if (hasSharedFile) files ?: chat else chat

/** Every received file, from any Mac, newest first — reachable even when no Mac is connected. */
fun allReceived(received: List<TransferQueue.Received>,
                modified: (File) -> Long = File::lastModified): List<TimelineItem.ReceivedFile> =
    received.map { TimelineItem.ReceivedFile(it, modified(it.file)) }.sortedByDescending { it.time }
