package com.nexus.mastersync.ui.conversation

import android.net.Uri
import android.text.format.Formatter
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nexus.mastersync.NexusController
import com.nexus.mastersync.ui.NexusActions
import com.nexus.mastersync.ui.components.Banner
import com.nexus.mastersync.ui.components.Muted
import com.nexus.mastersync.ui.components.NexusPanel
import com.nexus.mastersync.ui.components.Pill
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.theme.LocalNexusColors

@Composable
fun ConversationScreen(nexus: NexusController, actions: NexusActions, shared: Uri?, clearShared: () -> Unit,
                       onOpenFeature: (FeatureId) -> Unit, onOpenConnection: () -> Unit) {
    val c = LocalNexusColors.current
    val context = LocalContext.current
    val status by nexus.client.status.collectAsStateWithLifecycle()
    val options by nexus.options.collectAsStateWithLifecycle()
    val permission by nexus.permissions.collectAsStateWithLifecycle()
    val messages by nexus.messages.collectAsStateWithLifecycle()
    val sent by nexus.transfers.sent.collectAsStateWithLifecycle()
    val received by nexus.transfers.received.collectAsStateWithLifecycle()
    val progress by nexus.transfers.progress.collectAsStateWithLifecycle()
    val transferFeedback by nexus.transfers.feedback.collectAsStateWithLifecycle()
    val peer = status.connected?.id
    val items = remember(peer, messages, sent, received) { timeline(peer, messages, sent, received) }
    var draft by rememberSaveable(peer) { mutableStateOf("") }
    val connected = peer != null
    val blocker = chatBlocker(connected, options, permission, wantsFiles = false)
    // Sending files does not depend on chat being enabled on the Mac.
    val fileBlocker = chatBlocker(connected, options, permission.copy(chat = true), wantsFiles = true)
    val list = rememberLazyListState()
    LaunchedEffect(items.size, progress.size) {
        val last = items.size + progress.size - 1
        if (last >= 0) list.animateScrollToItem(last)
    }
    fun size(bytes: Long) = Formatter.formatShortFileSize(context, bytes)

    Column(Modifier.fillMaxSize()) {
        when (conversationBanner(blocker, fileBlocker, shared != null)) {
            ChatBlocker.Disconnected -> Banner("Mac desconectado", "Conectar", onOpenConnection)
            ChatBlocker.ChatOffOnMac -> Banner("Ative a Conversa no app do Mac", null) {}
            ChatBlocker.FilesOff -> Banner("Arquivos desligado", "Abrir") { onOpenFeature(FeatureId.Files) }
            null -> {}
        }
        if (transferFeedback.isNotBlank()) Muted(transferFeedback, Modifier.padding(top = 8.dp))
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list,
            contentPadding = PaddingValues(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (items.isEmpty() && progress.isEmpty()) item {
                Muted(if (connected) "Mensagens e arquivos trocados com o Mac aparecem aqui."
                    else "Arquivos já recebidos ficam em Início → Arquivos → Arquivos recebidos.", Modifier.padding(top = 24.dp))
            }
            items(items) { item ->
                when (item) {
                    is TimelineItem.Message -> Bubble(item.entry)
                    is TimelineItem.SentFile -> FileCard(item.sent.name,
                        if (item.sent.size > 0) "Enviado • ${size(item.sent.size)}" else "Enviado", outgoing = true)
                    is TimelineItem.ReceivedFile -> FileCard(item.received.item.name,
                        "Recebido • ${size(item.received.item.size)}", outgoing = false, action = "Salvar") {
                        actions.export(item.received.file, item.received.item.mime, item.received.item.name, false)
                    }
                }
            }
            items(progress) { transfer ->
                NexusPanel(Modifier.widthIn(max = 320.dp)) {
                    Text(transfer.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    LinearProgressIndicator(progress = { if (transfer.size <= 0) 0f else transfer.offset.toFloat() / transfer.size },
                        modifier = Modifier.fillMaxWidth(), color = c.accent, trackColor = c.control)
                    Muted("${if (transfer.sending) "Enviando" else "Recebendo"} • ${size(transfer.offset)} de ${size(transfer.size)}")
                }
            }
        }
        if (shared != null) NexusPanel(Modifier.padding(bottom = 8.dp), highlighted = true) {
            Text("Arquivo pronto para enviar", fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill("Enviar ao Mac", { nexus.offerFile(shared); clearShared() }, prominent = true, enabled = fileBlocker == null)
                Pill("Cancelar", clearShared)
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilledIconButton(onClick = actions.chooseFile, enabled = fileBlocker == null,
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = c.control, contentColor = c.ink)) {
                Icon(Icons.Default.Add, contentDescription = "Anexar arquivo")
            }
            OutlinedTextField(value = draft, onValueChange = { draft = it.take(2048) }, modifier = Modifier.weight(1f),
                placeholder = { Text("Mensagem para o Mac") }, maxLines = 4, shape = RoundedCornerShape(24.dp),
                colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = c.surface, unfocusedContainerColor = c.surface,
                    focusedBorderColor = c.accent, unfocusedBorderColor = c.border))
            val canSend = blocker == null && draft.isNotBlank() && draft.toByteArray().size <= 2048
            FilledIconButton(onClick = { if (nexus.sendChat(draft)) draft = "" }, enabled = canSend,
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = c.accent, contentColor = c.accentInk)) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Enviar mensagem")
            }
        }
    }
}

@Composable
private fun Bubble(entry: NexusController.ChatEntry) {
    val c = LocalNexusColors.current
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (entry.outgoing) Alignment.End else Alignment.Start) {
        Surface(shape = RoundedCornerShape(18.dp), color = if (entry.outgoing) c.accentSurface else c.control,
            contentColor = c.ink, modifier = Modifier.widthIn(max = 300.dp)) {
            Text(entry.text, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
        }
        if (entry.outgoing && !entry.confirmed) Muted("Sem confirmação")
    }
}

@Composable
private fun FileCard(name: String, detail: String, outgoing: Boolean, action: String? = null, onAction: () -> Unit = {}) {
    val c = LocalNexusColors.current
    Box(Modifier.fillMaxWidth(), contentAlignment = if (outgoing) Alignment.CenterEnd else Alignment.CenterStart) {
        Surface(shape = RoundedCornerShape(16.dp), color = c.surface, contentColor = c.ink,
            border = BorderStroke(1.dp, c.border), modifier = Modifier.widthIn(max = 300.dp)) {
            Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(34.dp).background(c.accentSurface, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                    Icon(if (outgoing) Icons.AutoMirrored.Filled.Send else Icons.Default.Add, contentDescription = null,
                        tint = c.accent, modifier = Modifier.size(18.dp))
                }
                Column(Modifier.weight(1f, fill = false)) {
                    Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
                    Muted(detail)
                }
                if (action != null) TextButton(onClick = onAction) { Text(action, color = c.accent, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}
