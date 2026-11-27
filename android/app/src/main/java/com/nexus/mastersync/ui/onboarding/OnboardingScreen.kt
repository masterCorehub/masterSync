package com.nexus.mastersync.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nexus.mastersync.NexusController
import com.nexus.mastersync.protocol.LocalClient
import com.nexus.mastersync.ui.NexusActions
import com.nexus.mastersync.ui.components.ChipTone
import com.nexus.mastersync.ui.components.Muted
import com.nexus.mastersync.ui.components.NexusPanel
import com.nexus.mastersync.ui.components.Pill
import com.nexus.mastersync.ui.components.StatusChip
import com.nexus.mastersync.ui.components.ToggleRow
import com.nexus.mastersync.ui.features.Feature
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.features.FeatureStatus
import com.nexus.mastersync.ui.sheet.setFeatureEnabled
import com.nexus.mastersync.ui.theme.LocalNexusColors

@Composable
fun OnboardingScreen(
    page: OnboardingPage,
    setPage: (OnboardingPage) -> Unit,
    status: LocalClient.Status,
    features: List<Feature>,
    options: NexusController.Options,
    nexus: NexusController,
    actions: NexusActions,
    openFeature: (FeatureId) -> Unit,
    onFinish: () -> Unit
) {
    val c = LocalNexusColors.current
    val connected = status.connected != null
    // Once the Mac is really connected, the pairing page is done: move on by itself.
    LaunchedEffect(connected, page) {
        if (connected && page == OnboardingPage.Pair) setPage(OnboardingPage.Features)
    }
    Box(Modifier.fillMaxSize().background(c.canvas).safeDrawingPadding()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    OnboardingPage.entries.forEach {
                        Box(Modifier.height(6.dp).width(if (it == page) 22.dp else 8.dp)
                            .background(if (it.ordinal <= page.ordinal) c.accent else c.control, CircleShape))
                    }
                }
                Spacer(Modifier.weight(1f))
                Muted(page.position)
                if (!page.isLast) TextButton(onClick = onFinish) { Text("Pular", color = c.muted) }
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 18.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(page.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text(page.body, color = c.muted, style = MaterialTheme.typography.bodyLarge)
                when (page) {
                    OnboardingPage.Welcome -> NexusPanel {
                        listOf("Notificações e códigos de verificação", "SMS no Mac", "Fotos, vídeos e arquivos",
                            "Área de transferência compartilhada", "Controle do celular pelo Mac").forEach {
                            Text("•  $it", style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                    OnboardingPage.Mac -> Unit
                    OnboardingPage.Pair -> NexusPanel {
                        if (connected) Text("Conectado a ${status.connected?.name}", fontWeight = FontWeight.Bold)
                        else {
                            Pill("Ler QR", actions.readQr, prominent = true)
                            Muted(status.info)
                        }
                    }
                    OnboardingPage.Features -> NexusPanel {
                        features.forEachIndexed { index, feature ->
                            if (index > 0) HorizontalDivider(color = c.control)
                            FeatureChoice(feature, onToggle = { setFeatureEnabled(feature.id, it, nexus, options, actions) },
                                onResolve = { openFeature(feature.id) })
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                page.previous?.let { TextButton(onClick = { setPage(it) }) { Text("Voltar", color = c.muted) } }
                Spacer(Modifier.weight(1f))
                if (page == OnboardingPage.Pair && !connected) {
                    TextButton(onClick = { setPage(OnboardingPage.Features) }) { Text("Fazer depois", color = c.muted) }
                } else {
                    Pill(if (page.isLast) "Começar a usar" else if (page == OnboardingPage.Welcome) "Começar" else "Continuar",
                        { page.next?.let(setPage) ?: onFinish() }, prominent = true,
                        enabled = Onboarding.canContinue(page, connected))
                }
            }
        }
    }
}

@Composable
private fun FeatureChoice(feature: Feature, onToggle: (Boolean) -> Unit, onResolve: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ToggleRow(feature.title, feature.enabled, onToggle, subtitle = feature.summary)
        val pending = (feature.status as? FeatureStatus.Pending)?.requirement
        if (pending != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusChip("Falta: ${pending.label}", ChipTone.Warn)
                TextButton(onClick = onResolve) { Text("Resolver") }
            }
        }
    }
}
