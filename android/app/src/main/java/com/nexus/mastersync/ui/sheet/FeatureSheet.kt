package com.nexus.mastersync.ui.sheet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nexus.mastersync.NexusController
import com.nexus.mastersync.services.ScanLibrary
import com.nexus.mastersync.ui.NexusActions
import com.nexus.mastersync.ui.components.Muted
import com.nexus.mastersync.ui.components.NexusPanel
import com.nexus.mastersync.ui.components.Pill
import com.nexus.mastersync.ui.components.SectionLabel
import com.nexus.mastersync.ui.components.StepRow
import com.nexus.mastersync.ui.components.ToggleRow
import com.nexus.mastersync.ui.features.Feature
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.features.StepAction
import com.nexus.mastersync.ui.theme.LocalNexusColors
import android.text.format.Formatter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import com.nexus.mastersync.ui.conversation.allReceived
import java.text.DateFormat
import java.util.Date

private enum class Subpage { Apps, Documents, Received }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeatureSheet(feature: Feature, nexus: NexusController, actions: NexusActions,
                 documents: List<ScanLibrary.Document>, scannerBusy: Boolean, onDismiss: () -> Unit) {
    val c = LocalNexusColors.current
    val options by nexus.options.collectAsStateWithLifecycle()
    var subpage by rememberSaveable(feature.id) { mutableStateOf<Subpage?>(null) }
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    fun run(action: StepAction) = when (action) {
        StepAction.OpenAppSettings -> actions.openAppSettings()
        StepAction.OpenNotificationAccess -> actions.openNotificationAccess()
        StepAction.RequestGallery -> actions.requestGallery()
        StepAction.RequestSms -> actions.requestSms()
        StepAction.ToggleBackground -> actions.toggleBackground()
        StepAction.EnableFiles -> nexus.update(options.copy(files = true))
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = c.canvas, contentColor = c.ink) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
            .padding(bottom = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when (subpage) {
                Subpage.Apps -> {
                    SubpageHeader("Apps que aparecem no Mac") { subpage = null }
                    AppsList(nexus, options)
                }
                Subpage.Received -> {
                    SubpageHeader("Arquivos recebidos") { subpage = null }
                    ReceivedList(nexus, actions)
                }
                Subpage.Documents -> {
                    SubpageHeader("Digitalizações") { subpage = null }
                    DocumentsList(nexus, options, documents, scannerBusy, actions)
                }
                null -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Column(Modifier.weight(1f)) {
                            Text(feature.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                            Muted(feature.summary)
                        }
                        Switch(feature.enabled, { setFeatureEnabled(feature.id, it, nexus, options, actions) },
                            colors = SwitchDefaults.colors(checkedTrackColor = c.accent, checkedThumbColor = c.accentInk,
                                uncheckedTrackColor = c.control, uncheckedThumbColor = c.muted, uncheckedBorderColor = c.border),
                            modifier = Modifier.semantics { contentDescription = "Ligar ${feature.title}" })
                    }
                    SectionLabel("Para funcionar")
                    NexusPanel {
                        feature.requirements.forEachIndexed { i, requirement ->
                            if (i > 0) HorizontalDivider(color = c.control)
                            StepRow(i + 1, requirement, ::run)
                        }
                    }
                    FeatureOptions(feature, nexus, options, actions, scannerBusy, documents.size) { subpage = it }
                }
            }
        }
    }
}

fun setFeatureEnabled(id: FeatureId, on: Boolean, nexus: NexusController, o: NexusController.Options,
                       actions: NexusActions) = when (id) {
    FeatureId.Clipboard -> nexus.update(o.copy(clipboard = on))
    FeatureId.Files -> nexus.update(o.copy(files = on))
    FeatureId.Gallery -> if (on) actions.requestGallery() else nexus.update(o.copy(gallery = false, syncNewMedia = false))
    FeatureId.Notifications -> nexus.update(o.copy(notificationMirror = on))
    FeatureId.Mirror -> nexus.update(o.copy(mirror = on))
    FeatureId.Scan -> nexus.update(o.copy(remoteScan = on))
    FeatureId.FindPhone -> nexus.update(o.copy(findPhone = on))
    FeatureId.Sms -> if (on) actions.requestSms() else nexus.update(o.copy(sms = false))
}

@Composable
private fun SubpageHeader(title: String, onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Voltar") }
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun LinkRow(title: String, detail: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Muted(detail)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = LocalNexusColors.current.muted)
    }
}

@Composable
private fun OptionsPanel(content: @Composable ColumnScope.() -> Unit) {
    SectionLabel("Opções")
    NexusPanel(content = content)
}

@Composable
private fun FeatureOptions(feature: Feature, nexus: NexusController, options: NexusController.Options,
                           actions: NexusActions, busy: Boolean, documentCount: Int, open: (Subpage) -> Unit) {
    when (feature.id) {
        FeatureId.Clipboard -> {
            val latest by nexus.lastClip.collectAsStateWithLifecycle()
            val keyboard by nexus.keyboardSelected.collectAsStateWithLifecycle()
            val permission by nexus.permissions.collectAsStateWithLifecycle()
            val connected = nexus.client.status.collectAsStateWithLifecycle().value.connected != null
            OptionsPanel {
                Muted(when {
                    latest?.image == true -> "Imagem do Mac pronta para colar."
                    latest?.text != null -> "Texto do Mac pronto para colar."
                    else -> "Copie no celular e abra o MasterSync, ou copie no Mac e cole aqui normalmente."
                })
                if (connected && permission.clipboard && !permission.clipboardImages) {
                    Muted("Atualize o app do Mac para sincronizar imagens.")
                }
                HorizontalDivider(color = LocalNexusColors.current.control)
                Text("Teclado Nexus (opcional)", style = MaterialTheme.typography.bodyLarge)
                Muted(if (keyboard) "Selecionado: cópias seguem para o Mac com outro app em foco."
                    else "Envia cópias ao Mac sem abrir o MasterSync.")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (!keyboard) Pill("Ativar", actions.keyboardSettings)
                    Pill("Escolher teclado", actions.chooseKeyboard)
                }
            }
        }
        FeatureId.Files -> {
            val received by nexus.transfers.received.collectAsStateWithLifecycle()
            OptionsPanel {
                Muted("Envie pela Conversa ou pelo menu Compartilhar de qualquer app.")
                HorizontalDivider(color = LocalNexusColors.current.control)
                LinkRow("Arquivos recebidos", "${received.size}") { open(Subpage.Received) }
            }
        }
        FeatureId.Gallery -> if (options.gallery) OptionsPanel {
            ToggleRow("Enviar novas fotos e vídeos ao Mac", options.syncNewMedia,
                { nexus.update(options.copy(syncNewMedia = it)) })
            Pill("Revisar fotos e vídeos", actions.requestGallery)
        }
        FeatureId.Notifications -> {
            val apps by nexus.apps.collectAsStateWithLifecycle()
            OptionsPanel {
                ToggleRow("Ocultar conteúdo", options.hideNotifications, { nexus.update(options.copy(hideNotifications = it)) })
                ToggleRow("Controle de mídia", options.mediaControl, { nexus.update(options.copy(mediaControl = it)) },
                    subtitle = "Pausar e trocar faixa pelo Mac")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Acesso às notificações", style = MaterialTheme.typography.bodyLarge)
                        Muted("Revise ou remova o acesso no Android")
                    }
                    Pill("Abrir", actions.openNotificationAccess)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Controle do Não Perturbe", style = MaterialTheme.typography.bodyLarge)
                        Muted("O Mac liga e desliga o Não Perturbe")
                    }
                    Pill("Abrir", actions.openDndAccess)
                }
                HorizontalDivider(color = LocalNexusColors.current.control)
                LinkRow("Escolher apps", "${apps.keys.count { it !in options.blockedApps }} de ${apps.size}") {
                    open(Subpage.Apps)
                }
            }
        }
        FeatureId.Mirror -> OptionsPanel {
            Muted("O Android pede autorização a cada sessão e mostra um indicador enquanto a tela é compartilhada.")
        }
        FeatureId.Scan -> OptionsPanel {
            ToggleRow("Enviar páginas e PDF ao Mac automaticamente", options.autoScan,
                { nexus.update(options.copy(autoScan = it)) })
            HorizontalDivider(color = LocalNexusColors.current.control)
            Text("Digitalizar no celular", style = MaterialTheme.typography.bodyLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Pill("Fotografar", actions.scan, prominent = true, enabled = !busy)
                Pill("Várias páginas", actions.advancedScan, enabled = !busy)
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            }
            Muted("Várias páginas usa o Google Play Services para recorte e filtros e pode enviar métricas técnicas ao Google.")
            HorizontalDivider(color = LocalNexusColors.current.control)
            LinkRow("Digitalizações", "$documentCount") { open(Subpage.Documents) }
        }
        FeatureId.FindPhone -> OptionsPanel { Muted("O celular toca alto mesmo no silencioso quando o Mac pedir.") }
        FeatureId.Sms -> OptionsPanel { Muted("O Mac lê e responde seus SMS. Só texto: o RCS do Google Mensagens não aparece. Nada é guardado no Mac.") }
    }
}

@Composable
private fun AppsList(nexus: NexusController, options: NexusController.Options) {
    val apps by nexus.apps.collectAsStateWithLifecycle()
    NexusPanel {
        if (apps.isEmpty()) Muted("Os apps aparecem aqui depois da primeira notificação.")
        apps.entries.sortedBy { it.value }.forEach { (id, label) ->
            ToggleRow(label, id !in options.blockedApps, {
                nexus.update(options.copy(blockedApps = if (it) options.blockedApps - id else options.blockedApps + id))
            })
        }
    }
}

@Composable
private fun ReceivedList(nexus: NexusController, actions: NexusActions) {
    val received by nexus.transfers.received.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val items = remember(received) { allReceived(received) }
    NexusPanel {
        if (items.isEmpty()) Muted("Nenhum arquivo recebido.")
        items.forEach { entry ->
            val item = entry.received.item
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(item.name, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
                    Muted(Formatter.formatShortFileSize(context, item.size))
                }
                TextButton(onClick = { actions.export(entry.received.file, item.mime, item.name, false) }) { Text("Salvar") }
            }
        }
    }
}

@Composable
private fun DocumentsList(nexus: NexusController, options: NexusController.Options, documents: List<ScanLibrary.Document>,
                          busy: Boolean, actions: NexusActions) {
    val permission by nexus.permissions.collectAsStateWithLifecycle()
    val connected = nexus.client.status.collectAsStateWithLifecycle().value.connected != null
    val format = remember { DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT) }
    if (documents.isEmpty()) NexusPanel { Muted("Nenhum documento digitalizado.") }
    documents.forEach { doc ->
        var pages by remember(doc.id) { mutableStateOf(false) }
        NexusPanel {
            Text(format.format(Date(doc.date)), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Muted("${doc.pages.size} página(s) • PDF")
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = { actions.export(doc.pdf, "application/pdf", "Digitalização.pdf", false) }) { Text("Salvar PDF") }
                TextButton(enabled = !busy && doc.pages.isNotEmpty(), onClick = { actions.ocr(doc) }) { Text("Ler texto") }
                TextButton(enabled = connected && options.files && permission.files,
                    onClick = { actions.sendDocument(doc) }) { Text("Enviar") }
            }
            if (doc.pages.isNotEmpty()) TextButton(onClick = { pages = !pages }) {
                Text(if (pages) "Ocultar páginas" else "Exportar páginas como imagem")
            }
            if (pages) doc.pages.forEachIndexed { index, file ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Página ${index + 1}", Modifier.weight(1f))
                    TextButton(onClick = { actions.export(file, "image/jpeg", file.name, false) }) { Text("JPG") }
                    TextButton(onClick = { actions.export(file, "image/png", file.nameWithoutExtension + ".png", true) }) { Text("PNG") }
                }
            }
        }
    }
}
