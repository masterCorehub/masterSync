package com.nexus.mastersync.ui

import android.app.Activity
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nexus.mastersync.BuildConfig
import com.nexus.mastersync.NexusController
import com.nexus.mastersync.R
import com.nexus.mastersync.services.ScanLibrary
import com.nexus.mastersync.ui.components.Banner
import com.nexus.mastersync.ui.connection.ConnectionScreen
import com.nexus.mastersync.ui.conversation.ConversationScreen
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.features.buildFeatures
import com.nexus.mastersync.ui.features.rememberSystemAccess
import com.nexus.mastersync.ui.home.HomeScreen
import com.nexus.mastersync.ui.sheet.FeatureSheet
import com.nexus.mastersync.ui.onboarding.Onboarding
import com.nexus.mastersync.ui.onboarding.OnboardingPage
import com.nexus.mastersync.ui.onboarding.OnboardingScreen
import com.nexus.mastersync.ui.components.Pill
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.nexus.mastersync.ui.theme.LocalNexusColors
import com.nexus.mastersync.ui.theme.NexusBackdrop
import com.nexus.mastersync.ui.theme.NexusTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NexusScreen(
    nexus: NexusController,
    actions: NexusActions,
    tab: Tab,
    navigate: (Tab) -> Unit,
    openFeature: FeatureId?,
    setOpenFeature: (FeatureId?) -> Unit,
    shared: Uri?,
    clearShared: () -> Unit,
    documents: List<ScanLibrary.Document>,
    scannerBusy: Boolean,
    recognized: String?
) {
    val options by nexus.options.collectAsStateWithLifecycle()
    val status by nexus.client.status.collectAsStateWithLifecycle()
    val permission by nexus.permissions.collectAsStateWithLifecycle()
    val message by nexus.feedback.collectAsStateWithLifecycle()
    val background by nexus.background.collectAsStateWithLifecycle()
    val scanRequest by nexus.pendingScan.collectAsStateWithLifecycle()
    val photoRequest by nexus.pendingPhoto.collectAsStateWithLifecycle()
    val screenRequest by nexus.pendingMirror.collectAsStateWithLifecycle()
    val mirroring by nexus.mirroring.collectAsStateWithLifecycle()
    val access = rememberSystemAccess()
    val features = buildFeatures(options, permission, status.connected != null, background, access,
        BuildConfig.NOTIFICATION_RELAY)
    val context = LocalContext.current
    val onboardingPrefs = remember { context.getSharedPreferences("onboarding", android.content.Context.MODE_PRIVATE) }
    var onboarding by rememberSaveable {
        mutableStateOf<OnboardingPage?>(
            if (Onboarding.shouldShow(onboardingPrefs.getBoolean("done", false), status.peers.isNotEmpty())) OnboardingPage.Welcome else null)
    }
    val dark = options.theme == "dark" || options.theme == "system" && isSystemInDarkTheme()

    val view = LocalView.current
    SideEffect {
        (view.context as? Activity)?.window?.let { window ->
            if (android.os.Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    BackHandler(tab != Tab.Home) { navigate(Tab.Home) }

    NexusTheme(dark) {
        val c = LocalNexusColors.current
        Box(Modifier.fillMaxSize()) {
            NexusBackdrop()
            Scaffold(
                containerColor = Color.Transparent,
                contentColor = c.ink,
                topBar = {
                    TopAppBar(colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent,
                        titleContentColor = c.ink), title = {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Surface(shape = RoundedCornerShape(10.dp), color = c.accentSurface) {
                                Icon(painterResource(R.drawable.ic_nexus), null, Modifier.padding(7.dp).size(20.dp), tint = c.accent)
                            }
                            Text(if (tab == Tab.Home) "MasterSync" else tab.label,
                                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        }
                    })
                },
                bottomBar = {
                    NavigationBar(containerColor = c.surface) {
                        Tab.entries.forEach { item ->
                            NavigationBarItem(selected = tab == item, onClick = { navigate(item) }, icon = {
                                Icon(when (item) {
                                    Tab.Home -> Icons.Default.Home
                                    Tab.Conversation -> Icons.Default.Email
                                    Tab.Connection -> Icons.Default.Settings
                                }, contentDescription = null)
                            }, label = { Text(item.label) }, colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = c.accent, selectedTextColor = c.accent, indicatorColor = c.accentSurface,
                                unselectedIconColor = c.muted, unselectedTextColor = c.muted))
                        }
                    }
                }
            ) { insets ->
                Column(Modifier.padding(insets).consumeWindowInsets(insets).padding(horizontal = 20.dp).fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (mirroring) Banner("Sua tela está sendo compartilhada com o Mac.", "Parar", nexus::stopMirror)
                    if (message.isNotBlank()) Banner(message, "Fechar") { nexus.note("") }
                    when (tab) {
                        Tab.Home -> Scrolling {
                            HomeScreen(status, background, features, setOpenFeature, { navigate(Tab.Connection) }, actions.readQr)
                        }
                        Tab.Conversation -> Box(Modifier.weight(1f).imePadding()) {
                            ConversationScreen(nexus, actions, shared, clearShared,
                                onOpenFeature = { navigate(Tab.Home); setOpenFeature(it) },
                                onOpenConnection = { navigate(Tab.Connection) })
                        }
                        Tab.Connection -> Scrolling {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                ConnectionScreen(nexus, background, actions)
                                Pill("Rever introdução", { onboarding = OnboardingPage.Welcome })
                            }
                        }
                    }
                }
            }
        }

        features.firstOrNull { it.id == openFeature }?.let { feature ->
            FeatureSheet(feature, nexus, actions, documents, scannerBusy) { setOpenFeature(null) }
        }

        onboarding?.let { page ->
            OnboardingScreen(page, { onboarding = it }, status, features, options, nexus, actions, setOpenFeature) {
                onboardingPrefs.edit().putBoolean("done", true).apply()
                onboarding = null
            }
        }

        if (screenRequest != null) {
            AlertDialog(onDismissRequest = { nexus.decideMirror(false) },
                title = { Text("Compartilhar sua tela?") },
                text = { Text("O Mac pareado poderá ver o conteúdo que você selecionar no próximo diálogo do Android. Você pode parar a qualquer momento pela notificação.") },
                confirmButton = { TextButton(onClick = actions.approveScreen) { Text("Continuar") } },
                dismissButton = { TextButton(onClick = { nexus.decideMirror(false) }) { Text("Recusar") } })
        }
        if (photoRequest != null && screenRequest == null && scanRequest == null) {
            AlertDialog(onDismissRequest = { nexus.decidePhoto(false) },
                title = { Text("Tirar foto para o Mac?") },
                text = { Text("Confirme a foto na câmera do Android para enviar a imagem ao Mac pareado.") },
                confirmButton = { TextButton(enabled = !scannerBusy, onClick = actions.approvePhoto) { Text("Abrir câmera") } },
                dismissButton = { TextButton(onClick = { nexus.decidePhoto(false) }) { Text("Recusar") } })
        }
        if (scanRequest != null) {
            AlertDialog(onDismissRequest = { nexus.decideScan(false) },
                title = { Text("Fotografar para o Mac?") },
                text = {
                    Column {
                        Text("O Mac solicitou uma digitalização. Confirme a foto na câmera para enviar a imagem e o PDF.")
                        TextButton(enabled = !scannerBusy, onClick = { actions.acceptScan(true) }) {
                            Text("Recortar ou digitalizar várias páginas")
                        }
                    }
                },
                confirmButton = { TextButton(enabled = !scannerBusy, onClick = { actions.acceptScan(false) }) { Text("Abrir câmera") } },
                dismissButton = { TextButton(onClick = { nexus.decideScan(false) }) { Text("Recusar") } })
        }
        if (recognized != null) {
            AlertDialog(onDismissRequest = actions.dismissOcr, title = { Text("Texto reconhecido") },
                text = {
                    LazyColumn(Modifier.height(240.dp)) {
                        item { SelectionContainer { Text(recognized) } }
                    }
                }, confirmButton = { TextButton(onClick = actions.dismissOcr) { Text("Fechar") } })
        }
    }
}

@Composable
private fun Scrolling(content: @Composable () -> Unit) {
    Box(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) { content() }
}
