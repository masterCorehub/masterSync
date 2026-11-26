package com.nexus.mastersync.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import android.app.Activity
import android.net.Uri
import androidx.core.view.WindowCompat
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nexus.mastersync.BuildConfig
import com.nexus.mastersync.NexusController
import com.nexus.mastersync.R
import com.nexus.mastersync.protocol.LocalClient
import com.nexus.mastersync.protocol.MacPeer
import com.nexus.mastersync.services.ScanLibrary
import java.io.File
import java.text.DateFormat
import java.util.Date

enum class Tab(val label: String) {
    Home("Início"), Scan("Digitalizar"), Share("Conversa"), Devices("Dispositivos"), Settings("Configurações")
}

private val light = lightColorScheme(
    primary = Color(0xFF454EC4), onPrimary = Color.White,
    primaryContainer = Color(0xFFE4E6FF), onPrimaryContainer = Color(0xFF252960),
    secondaryContainer = Color(0xFFEAECF8), onSecondaryContainer = Color(0xFF262B43),
    background = Color(0xFFF4F6FA), surface = Color.White, onSurface = Color(0xFF151821),
    surfaceVariant = Color(0xFFEAEDF5), onSurfaceVariant = Color(0xFF51576A), outline = Color(0xFF747B8F)
)
private val dark = darkColorScheme(
    primary = Color(0xFFAAB0FF), onPrimary = Color(0xFF252960),
    primaryContainer = Color(0xFF323976), onPrimaryContainer = Color(0xFFF1F1FF),
    secondaryContainer = Color(0xFF292E46), onSecondaryContainer = Color(0xFFDFE3F9),
    background = Color(0xFF10131B), surface = Color(0xFF191E2A), onSurface = Color(0xFFEDF0F9),
    surfaceVariant = Color(0xFF272D3B), onSurfaceVariant = Color(0xFFBBC3D8), outline = Color(0xFF949CB6)
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NexusScreen(
    nexus: NexusController,
    tab: Tab,
    navigate: (Tab) -> Unit,
    shared: Uri?,
    clearShared: () -> Unit,
    onQr: () -> Unit,
    onChoose: () -> Unit,
    onConnection: () -> Unit,
    onNotificationSettings: () -> Unit,
    onGalleryAccess: () -> Unit,
    onApprovePhoto: () -> Unit = {},
    onApproveScreen: () -> Unit,
    onKeyboardSettings: () -> Unit,
    onChooseKeyboard: () -> Unit,
    onScan: () -> Unit,
    onAdvancedScan: () -> Unit,
    onAcceptScan: (Boolean) -> Unit,
    documents: List<ScanLibrary.Document>,
    scannerBusy: Boolean,
    recognized: String?,
    onOCR: (ScanLibrary.Document) -> Unit,
    onDismissOCR: () -> Unit,
    onSendDocument: (ScanLibrary.Document) -> Unit,
    onExport: (File, String, String, Boolean) -> Unit
) {
    val options by nexus.options.collectAsStateWithLifecycle()
    val connection by nexus.client.status.collectAsStateWithLifecycle()
    val permission by nexus.permissions.collectAsStateWithLifecycle()
    val message by nexus.feedback.collectAsStateWithLifecycle()
    val background by nexus.background.collectAsStateWithLifecycle()
    val scanRequest by nexus.pendingScan.collectAsStateWithLifecycle()
    val photoRequest by nexus.pendingPhoto.collectAsStateWithLifecycle()
    val screenRequest by nexus.pendingMirror.collectAsStateWithLifecycle()
    val mirroring by nexus.mirroring.collectAsStateWithLifecycle()
    val useDark = options.theme == "dark" || options.theme == "system" && isSystemInDarkTheme()

    val view = LocalView.current
    SideEffect {
        (view.context as? Activity)?.window?.let { window ->
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !useDark
                isAppearanceLightNavigationBars = !useDark
            }
        }
    }
    var showAccess by rememberSaveable { mutableStateOf(false) }
    val accessOpen = tab == Tab.Settings && showAccess
    BackHandler(tab == Tab.Settings) {
        if (accessOpen) showAccess = false else navigate(Tab.Home)
    }
    MaterialTheme(colorScheme = if (useDark) dark else light) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            topBar = {
                TopAppBar(colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background), title = {
                    if (tab == Tab.Settings) {
                        Text(if (accessOpen) "Permissões e acessos" else "Configurações")
                    } else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                            Icon(painterResource(R.drawable.ic_nexus), null, Modifier.padding(7.dp).size(20.dp),
                                tint = MaterialTheme.colorScheme.onPrimaryContainer)
                        }
                        Text("MasterSync", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    }
                }, navigationIcon = {
                    if (tab == Tab.Settings) IconButton(onClick = {
                        if (accessOpen) showAccess = false else navigate(Tab.Home)
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Voltar")
                    }
                }, actions = {
                    if (tab != Tab.Settings) IconButton(onClick = { navigate(Tab.Settings) }) {
                        Icon(Icons.Default.Settings, contentDescription = "Configurações")
                    }
                })
            },
            bottomBar = {
                if (tab != Tab.Settings) NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                    Tab.entries.filter { it != Tab.Settings }.forEach { item ->
                        NavigationBarItem(selected = tab == item, onClick = { navigate(item) }, icon = {
                            Icon(when (item) {
                                Tab.Home -> Icons.Default.Home
                                Tab.Scan -> Icons.Default.Search
                                Tab.Share -> Icons.Default.Share
                                Tab.Devices -> Icons.AutoMirrored.Filled.List
                                Tab.Settings -> Icons.Default.Settings
                            }, contentDescription = item.label)
                        }, label = { Text(item.label, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) })
                    }
                }
            }
        ) { insets ->
            LazyColumn(Modifier.padding(insets), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(13.dp)) {
                if (tab != Tab.Home && tab != Tab.Settings) item { PageTitle(tab.label) }
                if (mirroring) item { Feedback("Sua tela está sendo compartilhada com o Mac.", onClose = nexus::stopMirror, action = "Parar") }
                if (message.isNotBlank()) item { Feedback(message, onClose = { nexus.note("") }) }
                item {
                    when (tab) {
                        Tab.Home -> Home(connection, options, permission, navigate) { nexus.update(options.copy(clipboard = it)) }
                        Tab.Scan -> ScanPage(nexus, documents, scannerBusy, onScan, onAdvancedScan, onOCR, onSendDocument, onExport)
                        Tab.Share -> SharePage(nexus, connection, options, permission, shared, clearShared, onChoose, onExport,
                            background, onConnection, onKeyboardSettings, onChooseKeyboard)
                        Tab.Devices -> Devices(nexus, connection, background, onQr, onConnection)
                        Tab.Settings -> SettingsPage(nexus, options, onNotificationSettings, onGalleryAccess, background, onConnection, onKeyboardSettings, onChooseKeyboard, accessOpen, { showAccess = true }, connection.connected != null)
                    }
                }
            }
        }

        if (screenRequest != null) {
            AlertDialog(onDismissRequest = { nexus.decideMirror(false) },
                title = { Text("Compartilhar sua tela?") },
                text = { Text("O Mac pareado poderá ver o conteúdo que você selecionar no próximo diálogo do Android. Você pode parar a qualquer momento pela notificação.") },
                confirmButton = { TextButton(onClick = onApproveScreen) { Text("Continuar") } },
                dismissButton = { TextButton(onClick = { nexus.decideMirror(false) }) { Text("Recusar") } })
        }
        if (photoRequest != null && screenRequest == null && scanRequest == null) {
            AlertDialog(onDismissRequest = { nexus.decidePhoto(false) },
                title = { Text("Tirar foto para o Mac?") },
                text = { Text("Confirme a foto na câmera do Android para enviar a imagem ao Mac pareado.") },
                confirmButton = { TextButton(enabled = !scannerBusy, onClick = onApprovePhoto) { Text("Abrir câmera") } },
                dismissButton = { TextButton(onClick = { nexus.decidePhoto(false) }) { Text("Recusar") } })
        }
        if (scanRequest != null) {
            AlertDialog(onDismissRequest = { nexus.decideScan(false) },
                title = { Text("Fotografar para o Mac?") },
                text = {
                    Column {
                        Text("O Mac solicitou uma digitalização. Confirme a foto na câmera para enviar a imagem e o PDF.")
                        TextButton(enabled = !scannerBusy, onClick = { onAcceptScan(true) }) {
                            Text("Recortar ou digitalizar várias páginas")
                        }
                    }
                },
                confirmButton = { TextButton(enabled = !scannerBusy, onClick = { onAcceptScan(false) }) { Text("Abrir câmera") } },
                dismissButton = { TextButton(onClick = { nexus.decideScan(false) }) { Text("Recusar") } })
        }
        if (recognized != null) {
            AlertDialog(onDismissRequest = onDismissOCR, title = { Text("Texto reconhecido") },
                text = {
                    LazyColumn(Modifier.height(240.dp)) {
                        item { SelectionContainer { Text(recognized) } }
                    }
                }, confirmButton = { TextButton(onClick = onDismissOCR) { Text("Fechar") } })
        }
    }
}

@Composable
private fun Home(status: LocalClient.Status, options: NexusController.Options, permission: NexusController.Permissions,
                 navigate: (Tab) -> Unit, onClipboard: (Boolean) -> Unit) {
    Stack {
        PageTitle("Início")
        Card(onClick = { navigate(Tab.Devices) }, modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
            shape = RoundedCornerShape(24.dp)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                MacIllustration()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(status.connected?.name ?: "Conectar Mac", style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold)
                        Muted(if (status.connected != null) "Conectado pela rede local" else status.title)
                    }
                    Icon(Icons.Default.KeyboardArrowRight, contentDescription = null)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            QuickAction("Conversa", Icons.Default.Share, Modifier.weight(1f)) { navigate(Tab.Share) }
            QuickAction("Digitalizar", Icons.Default.Search, Modifier.weight(1f)) { navigate(Tab.Scan) }
        }
        Panel("Integrações") {
            ToggleRow("Área de transferência", options.clipboard, onClipboard)
            Muted(if (options.clipboard && !permission.clipboard) "Aguardando ativação no Mac" else "Texto e imagens")
            HorizontalDivider()
            AccessRow("Galeria", "Fotos e vídeos no Mac", "Abrir") { navigate(Tab.Settings) }
        }
    }
}

@Composable
private fun QuickAction(title: String, icon: ImageVector, modifier: Modifier, action: () -> Unit) {
    Card(onClick = action, modifier = modifier, shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun MacIllustration() {
    Box(Modifier.fillMaxWidth().height(148.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(196.dp, 136.dp)) {
            val w = size.width
            val h = size.height
            val frame = Color(0xFF29264A)
            drawRoundRect(frame, Offset(0f, h * .04f), Size(w, h * .76f), CornerRadius(9.dp.toPx()))
            drawRoundRect(Brush.linearGradient(listOf(Color(0xFF819FFF), Color(0xFF493DC0))),
                Offset(w * .035f, h * .085f), Size(w * .93f, h * .64f), CornerRadius(4.dp.toPx()))
            drawRect(frame, Offset(w * .44f, h * .79f), Size(w * .12f, h * .15f))
            drawRoundRect(frame, Offset(w * .31f, h * .92f), Size(w * .38f, h * .06f), CornerRadius(4.dp.toPx()))
        }
        Icon(painterResource(R.drawable.ic_nexus), null, Modifier.padding(bottom = 22.dp).size(44.dp), tint = Color.White)
    }
}

@Composable
private fun Devices(nexus: NexusController, status: LocalClient.Status, background: Boolean, onQr: () -> Unit,
                    onConnection: () -> Unit) {
    var forget by remember { mutableStateOf<MacPeer?>(null) }
    Stack {
        StatusCard(status.title, status.info)
        Panel("Parear Mac") {
            Muted("A câmera lê o QR gerado no Mac. Depois, confirme o nome deste celular no Mac.")
            Button(onClick = onQr) { Text("Ler QR") }
        }
        Panel("Conexão") {
            Muted("Em segundo plano, o Android exibe uma notificação enquanto o Nexus permanece conectado.")
            OutlinedButton(onClick = onConnection) { Text(if (background) "Parar conexão em segundo plano" else "Manter conexão em segundo plano") }
        }
        Panel("Macs autorizados") {
            if (status.peers.isEmpty()) Muted("Nenhum Mac autorizado.")
            status.peers.forEach { peer ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(peer.name, fontWeight = FontWeight.Medium)
                        Muted(if (status.connected?.id == peer.id) "Conectado" else "Desconectado")
                    }
                    if (status.connected?.id != peer.id) TextButton(onClick = { nexus.client.select(peer.id) }) { Text("Conectar") }
                    TextButton(onClick = { forget = peer }) { Text("Esquecer") }
                }
            }
        }
    }
    forget?.let { peer ->
        AlertDialog(onDismissRequest = { forget = null }, title = { Text("Esquecer ${peer.name}?") },
            text = { Text("Para conectar novamente, você precisará ler outro QR. Você pode revogar este celular na lista de dispositivos do Mac.") },
            confirmButton = { TextButton(onClick = { nexus.forget(peer.id); forget = null }) { Text("Esquecer") } },
            dismissButton = { TextButton(onClick = { forget = null }) { Text("Cancelar") } })
    }
}

@Composable
private fun SharePage(nexus: NexusController, status: LocalClient.Status, options: NexusController.Options,
                      permission: NexusController.Permissions, shared: Uri?, clear: () -> Unit,
                      choose: () -> Unit, export: (File, String, String, Boolean) -> Unit,
                      background: Boolean, onConnection: () -> Unit,
                      keyboardSettings: () -> Unit, chooseKeyboard: () -> Unit) {
    val latest by nexus.lastClip.collectAsStateWithLifecycle()
    val keyboard by nexus.keyboardSelected.collectAsStateWithLifecycle()
    val progress by nexus.transfers.progress.collectAsStateWithLifecycle()
    val received by nexus.transfers.received.collectAsStateWithLifecycle()
    val sent by nexus.transfers.sent.collectAsStateWithLifecycle()
    val transferPeer = status.connected?.id
    val transferFeedback by nexus.transfers.feedback.collectAsStateWithLifecycle()
    val connected = status.connected != null
    val messages by nexus.messages.collectAsStateWithLifecycle()
    val conversation = messages.filter { it.peer == status.connected?.id }
    var draft by rememberSaveable(status.connected?.id) { mutableStateOf("") }
    var keyboardOptions by rememberSaveable { mutableStateOf(false) }
    Stack {
        StatusCard(status.connected?.name ?: "Mac desconectado", status.title)
        Panel("Conversa com o Mac") {
            if (conversation.isEmpty()) Muted("As mensagens aparecem aqui.")
            conversation.takeLast(30).forEach { entry ->
                Column(modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = if (entry.outgoing) Alignment.End else Alignment.Start) {
                    val colors = MaterialTheme.colorScheme
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = if (entry.outgoing) colors.primaryContainer else colors.surfaceVariant,
                        contentColor = if (entry.outgoing) colors.onPrimaryContainer else colors.onSurfaceVariant
                    ) {
                        Text(entry.text, Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
                    }
                    if (entry.outgoing && !entry.confirmed) Muted("Sem confirmação")
                }
            }
            received.filter { it.peer == transferPeer }.take(8).forEach { item ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(item.item.name, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    TextButton(onClick = { export(item.file, item.item.mime, item.item.name, false) }) { Text("Salvar") }
                }
            }
            sent.filter { it.peer == transferPeer }.takeLast(8).forEach { item ->
                Text(item.name, Modifier.align(Alignment.End), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            OutlinedTextField(value = draft, onValueChange = { draft = it.take(2048) },
                label = { Text("Mensagem") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(enabled = connected && permission.chat && draft.isNotBlank() && draft.toByteArray().size <= 2048,
                    onClick = { if (nexus.sendChat(draft)) draft = "" }) { Text("Enviar mensagem") }
                OutlinedButton(enabled = connected && options.files && permission.files,
                    onClick = choose) { Text("Anexar arquivo") }
            }
        }
        if (shared != null) Panel("Compartilhado de outro aplicativo") {
            Muted("Arquivo pronto para enviar.")
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Button(enabled = connected && options.files && permission.files,
                    onClick = { nexus.offerFile(shared); clear() }) { Text("Enviar ao Mac") }
                TextButton(onClick = clear) { Text("Cancelar") }
            }
        }
        Panel("Área de transferência automática") {
            ToggleRow("Sincronizar texto e imagens", options.clipboard) { nexus.update(options.copy(clipboard = it)) }
            if (options.clipboard) {
                val description = when {
                    !connected || !permission.clipboard -> "Ative a área de transferência também no Mac pareado."
                    latest?.image == true -> "Imagem do Mac pronta para colar."
                    latest?.text != null -> "Texto do Mac pronto para colar."
                    else -> "Copie no Mac e cole normalmente no Android."
                }
                Muted(description)
                if (keyboard) {
                    Muted("Teclado Nexus selecionado para copiar de outros aplicativos.")
                } else {
                    Muted("No Android, copie com seu teclado de sempre e abra o Nexus. O texto ou a imagem segue automaticamente para o Mac.")
                    TextButton(onClick = { keyboardOptions = !keyboardOptions }) {
                        Text(if (keyboardOptions) "Ocultar opções do teclado" else "Opções do Teclado Nexus")
                    }
                    if (keyboardOptions) {
                        Muted("O Teclado Nexus é opcional e permite enviar cópias com outro app em foco.")
                        OutlinedButton(onClick = keyboardSettings) { Text("Ativar Teclado Nexus") }
                        OutlinedButton(onClick = chooseKeyboard) { Text("Escolher teclado") }
                    }
                }
                if (!background) OutlinedButton(onClick = onConnection) { Text("Manter conexão em segundo plano") }
                if (connected && permission.clipboard && !permission.clipboardImages) {
                    Muted("Atualize o app do Mac para sincronizar imagens.")
                }
            }
        }
        Panel("Arquivos") {
            ToggleRow("Permitir arquivos", options.files) { nexus.update(options.copy(files = it)) }
            Muted("Escolha um arquivo do Android ou use Compartilhar em outro aplicativo.")
            Button(enabled = connected && options.files && permission.files, onClick = choose) { Text("Escolher arquivo") }
            if (transferFeedback.isNotBlank()) Muted(transferFeedback)
            progress.forEach { transfer ->
                Text(transfer.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                LinearProgressIndicator(progress = { if (transfer.size <= 0) 0f else transfer.offset.toFloat() / transfer.size },
                    modifier = Modifier.fillMaxWidth())
                Muted("${if (transfer.sending) "Enviando" else "Recebendo"} • ${transfer.offset} de ${transfer.size} bytes")
            }
        }
        Panel("Arquivos recebidos") {
            if (received.isEmpty()) Muted("Nenhum arquivo recebido.")
            received.forEach { item ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(item.item.name, Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    TextButton(onClick = { export(item.file, item.item.mime, item.item.name, false) }) { Text("Salvar") }
                }
            }
        }
    }
}

@Composable
private fun ScanPage(nexus: NexusController, documents: List<ScanLibrary.Document>, busy: Boolean, scan: () -> Unit,
                     advanced: () -> Unit,
                     ocr: (ScanLibrary.Document) -> Unit, send: (ScanLibrary.Document) -> Unit,
                     export: (File, String, String, Boolean) -> Unit) {
    val options by nexus.options.collectAsStateWithLifecycle()
    val permission by nexus.permissions.collectAsStateWithLifecycle()
    val status by nexus.client.status.collectAsStateWithLifecycle()
    Stack {
        StatusCard("Scanner de documentos", "Capture uma página ou monte um PDF")
        Panel("Nova digitalização") {
            Button(enabled = !busy, onClick = scan) { Text("Fotografar documento") }
            TextButton(enabled = !busy, onClick = advanced) { Text("Recortar e digitalizar várias páginas") }
            Muted("O scanner avançado usa o Google Play Services para recorte e filtros e pode enviar métricas técnicas ao Google.")
            if (busy) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            ToggleRow("Aceitar solicitações do Mac", options.remoteScan) { nexus.update(options.copy(remoteScan = it)) }
            ToggleRow("Enviar páginas e PDF ao Mac automaticamente", options.autoScan) { nexus.update(options.copy(autoScan = it)) }
            if (options.autoScan && (!options.files || !permission.files)) Muted("Ative Arquivos no Android e no Mac para enviar as páginas.")
        }
        Panel("Digitalizações") {
            if (documents.isEmpty()) Muted("Nenhum documento digitalizado.")
            documents.forEach { doc ->
                var pages by remember(doc.id) { mutableStateOf(false) }
                val label = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(doc.date))
                Text(label, fontWeight = FontWeight.Medium)
                Muted("${doc.pages.size} página(s) • PDF")
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { export(doc.pdf, "application/pdf", "Digitalização.pdf", false) }) { Text("Salvar PDF") }
                    TextButton(enabled = !busy && doc.pages.isNotEmpty(), onClick = { ocr(doc) }) { Text("Ler texto") }
                    TextButton(enabled = status.connected != null && options.files && permission.files, onClick = { send(doc) }) { Text("Enviar PDF") }
                }
                if (doc.pages.isNotEmpty()) TextButton(onClick = { pages = !pages }) {
                    Text(if (pages) "Ocultar páginas" else "Exportar páginas como imagem")
                }
                if (pages) doc.pages.forEachIndexed { index, file ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Página ${index + 1}", Modifier.weight(1f))
                        TextButton(onClick = { export(file, "image/jpeg", file.name, false) }) { Text("JPG") }
                        TextButton(onClick = { export(file, "image/png", file.nameWithoutExtension + ".png", true) }) { Text("PNG") }
                    }
                }
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun SettingsPage(nexus: NexusController, options: NexusController.Options, openNotifications: () -> Unit,
                         allowGallery: () -> Unit, background: Boolean, onConnection: () -> Unit,
                         keyboardSettings: () -> Unit, chooseKeyboard: () -> Unit,
                         showAccess: Boolean, openAccess: () -> Unit, connected: Boolean) {
    val apps by nexus.apps.collectAsStateWithLifecycle()
    val context = LocalView.current.context
    var permissionRevision by remember { mutableStateOf(0) }
    LifecycleResumeEffect(context) {
        permissionRevision++
        onPauseOrDispose {}
    }
    val camera = remember(context, permissionRevision) {
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }
    val notifications = remember(context, permissionRevision) {
        NotificationManagerCompat.from(context).areNotificationsEnabled()
    }
    val notificationAccess = remember(context, permissionRevision) {
        context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)
    }
    fun openAppSettings() {
        context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null)))
    }
    Stack {
        if (showAccess) {
            StatusCard(if (connected) "Mac conectado" else "Mac desconectado", "Veja o que cada recurso precisa")
            Panel("Permissões do Android") {
                AccessRow("Câmera", "Ler o QR de pareamento", if (camera) "Permitida" else "Permitir", ::openAppSettings)
                HorizontalDivider()
                val fullMedia = if (Build.VERSION.SDK_INT >= 33) {
                    listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO).all {
                        context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
                    }
                } else context.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                val partialMedia = Build.VERSION.SDK_INT >= 34 &&
                    context.checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED
                AccessRow("Fotos e vídeos", "Abrir a galeria no Mac",
                    when { fullMedia -> "Permitidos"; partialMedia -> "Acesso parcial"; else -> "Permitir" }, allowGallery)
                HorizontalDivider()
                AccessRow("Notificações do app", "Avisos de conexão e captura",
                    if (notifications) "Permitidas" else "Permitir", ::openAppSettings)
            }
            Panel("Acessos especiais") {
                if (BuildConfig.NOTIFICATION_RELAY) {
                    AccessRow("Notificações de outros apps", "Espelhar avisos e controlar mídia",
                        if (notificationAccess) "Permitidas" else "Configurar", openNotifications)
                    OutlinedButton(onClick = {
                        context.startActivity(android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    }) { Text("Autorizar Não Perturbe") }
                }
                Muted("Autorize a captura de tela a cada sessão no Android.")
                ToggleRow("Receber solicitações de espelhamento", options.mirror) { nexus.update(options.copy(mirror = it)) }
            }
            Panel("Configuração dos recursos") {
                OutlinedButton(onClick = onConnection) {
                    Text(if (background) "Parar conexão em segundo plano" else "Manter conexão em segundo plano")
                }
                OutlinedButton(onClick = keyboardSettings) { Text("Ativar Teclado Nexus") }
                OutlinedButton(onClick = chooseKeyboard) { Text("Escolher teclado") }
                Muted("Para arquivos, galeria e área de transferência, ative a integração também no Mac. Para controle por Wi-Fi ou USB, configure a depuração no Android e no Mac.")
            }
        } else {
            Panel("Permissões e acessos") {
                Muted("Configure os acessos necessários para usar os recursos com o Mac.")
                OutlinedButton(onClick = openAccess) { Text("Gerenciar permissões e acessos") }
            }
            Panel("Aparência") {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    listOf("system" to "Automático", "light" to "Claro", "dark" to "Escuro").forEach { (key, label) ->
                        FilterChip(selected = options.theme == key, onClick = { nexus.update(options.copy(theme = key)) },
                            label = { Text(label) })
                    }
                }
            }
            if (BuildConfig.NOTIFICATION_RELAY) Panel("Notificações") {
                val context = LocalView.current.context
                Muted("O acesso permite ler notificações de outros aplicativos e responder quando houver uma ação de resposta. As notificações seguem para o Mac pareado.")
                OutlinedButton(onClick = openNotifications) { Text("Revisar acesso às notificações") }
                OutlinedButton(onClick = {
                    context.startActivity(android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                }) { Text("Autorizar controle do Não Perturbe") }
                ToggleRow("Espelhar no Mac", options.notificationMirror) { nexus.update(options.copy(notificationMirror = it)) }
                ToggleRow("Ocultar conteúdo", options.hideNotifications) { nexus.update(options.copy(hideNotifications = it)) }
                apps.entries.sortedBy { it.value }.forEach { (id, label) ->
                    ToggleRow(label, id !in options.blockedApps) {
                        val blocked = if (it) options.blockedApps - id else options.blockedApps + id
                        nexus.update(options.copy(blockedApps = blocked))
                    }
                }
            }
            Panel("Galeria") {
                Muted("O Mac pareado poderá buscar e abrir a mídia que você autorizar. O Android 14 ou mais recente permite escolher itens específicos.")
                ToggleRow("Disponibilizar galeria ao Mac", options.gallery) { enabled ->
                    if (enabled) allowGallery() else nexus.update(options.copy(gallery = false, syncNewMedia = false))
                }
                if (options.gallery) {
                    OutlinedButton(onClick = allowGallery) { Text("Revisar fotos e vídeos") }
                    Muted("Para ver a galeria com a tela bloqueada, mantenha a conexão em segundo plano. O Android mostra uma notificação durante a conexão.")
                    OutlinedButton(onClick = onConnection) {
                        Text(if (background) "Parar conexão em segundo plano" else "Manter conexão em segundo plano")
                    }
                    ToggleRow("Enviar novas fotos e vídeos ao Mac", options.syncNewMedia) {
                        nexus.update(options.copy(syncNewMedia = it))
                    }
                }
            }
            Panel("Espelhamento") {
                Muted("O Android mostra um pedido do sistema a cada sessão e mantém um indicador durante a captura.")
                ToggleRow("Receber solicitações de espelhamento", options.mirror) { nexus.update(options.copy(mirror = it)) }
            }
            Panel("Ações remotas") {
                Muted("O Mac pareado pode tocar o telefone.")
                ToggleRow("Permitir localizar por toque", options.findPhone) { nexus.update(options.copy(findPhone = it)) }
                if (BuildConfig.NOTIFICATION_RELAY) {
                    ToggleRow("Permitir controle de mídia", options.mediaControl) { nexus.update(options.copy(mediaControl = it)) }
                }
            }
        }
    }
}

@Composable
private fun AccessRow(title: String, subtitle: String, actionLabel: String, action: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Muted(subtitle)
        }
        TextButton(onClick = action) { Text(actionLabel) }
    }
}

@Composable
private fun StatusCard(title: String, subtitle: String) {
    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(22.dp)) {
        Row(Modifier.fillMaxWidth().padding(18.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(R.drawable.ic_nexus), null, Modifier.size(28.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Muted(subtitle)
            }
        }
    }
}

@Composable
private fun PageTitle(title: String) {
    Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.semantics { heading() })
}

@Composable
private fun Stack(content: @Composable ColumnScope.() -> Unit) =
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(13.dp), content = content)

@Composable
private fun Panel(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(shape = RoundedCornerShape(22.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() })
            content()
        }
    }
}

@Composable
private fun Muted(text: String) {
    Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
}

@Composable
private fun ToggleRow(title: String, enabled: Boolean, update: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f))
        Switch(enabled, update)
    }
}

@Composable
private fun StackedActions(actions: List<Pair<String, () -> Unit>>) {
    actions.forEachIndexed { index, (title, action) ->
        TextButton(onClick = action, modifier = Modifier.fillMaxWidth()) {
            Text(title, Modifier.weight(1f))
        }
        if (index < actions.lastIndex) HorizontalDivider()
    }
}

@Composable
private fun Feedback(text: String, onClose: () -> Unit, action: String = "Fechar") {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 13.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            TextButton(onClick = onClose) { Text(action) }
        }
    }
}
