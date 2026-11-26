package com.nexus.mastersync.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AccountBox
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nexus.mastersync.protocol.LocalClient
import com.nexus.mastersync.ui.components.ChipTone
import com.nexus.mastersync.ui.components.Muted
import com.nexus.mastersync.ui.components.NexusPanel
import com.nexus.mastersync.ui.components.Pill
import com.nexus.mastersync.ui.components.StatusChip
import com.nexus.mastersync.ui.features.Feature
import com.nexus.mastersync.ui.features.FeatureId
import com.nexus.mastersync.ui.features.FeatureStatus
import com.nexus.mastersync.ui.theme.LocalNexusColors

fun FeatureId.icon(): ImageVector = when (this) {
    FeatureId.Clipboard -> Icons.Default.Edit
    FeatureId.Files -> Icons.AutoMirrored.Filled.Send
    FeatureId.Gallery -> Icons.Default.AccountBox
    FeatureId.Notifications -> Icons.Default.Notifications
    FeatureId.Mirror -> Icons.Default.Phone
    FeatureId.Scan -> Icons.Default.Search
    FeatureId.FindPhone -> Icons.Default.LocationOn
}

@Composable
fun HomeScreen(status: LocalClient.Status, background: Boolean, features: List<Feature>,
               onOpenFeature: (FeatureId) -> Unit, onOpenConnection: () -> Unit, onReadQr: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        MacCard(status, background, onOpenConnection, onReadQr)
        NexusPanel {
            Text("Recursos para o Mac", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() })
            features.forEachIndexed { index, feature ->
                if (index > 0) HorizontalDivider(color = LocalNexusColors.current.control)
                FeatureRow(feature) { onOpenFeature(feature.id) }
            }
        }
    }
}

@Composable
fun MacCard(status: LocalClient.Status, background: Boolean, onOpenConnection: (() -> Unit)?, onReadQr: () -> Unit) {
    val c = LocalNexusColors.current
    val mac = status.connected
    if (mac == null && status.peers.isEmpty()) {
        NexusPanel(highlighted = true) {
            Text("Conectar um Mac", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Muted("No Mac, abra Dispositivos → Gerar QR e leia o código com o celular.")
            Pill("Ler QR", onReadQr, prominent = true)
        }
        return
    }
    NexusPanel(highlighted = true, onClick = onOpenConnection) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(8.dp).background(if (mac != null) c.connected else c.muted, CircleShape))
                    Text(if (mac != null) "Conectado" else status.title, color = c.muted,
                        style = MaterialTheme.typography.labelLarge)
                }
                Text(mac?.name ?: status.peers.first().name, style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold)
                Muted(when {
                    mac != null && background -> "Rede local • em segundo plano"
                    mac != null -> "Rede local"
                    else -> status.info
                })
            }
            if (onOpenConnection != null) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Abrir conexão", tint = c.muted)
            }
        }
    }
}

@Composable
private fun FeatureRow(feature: Feature, onClick: () -> Unit) {
    val c = LocalNexusColors.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(34.dp).background(c.accentSurface, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            Icon(feature.id.icon(), contentDescription = null, tint = c.accent, modifier = Modifier.size(18.dp))
        }
        Text(feature.title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        when (val s = feature.status) {
            FeatureStatus.Active -> StatusChip("Ativo", ChipTone.Ok)
            FeatureStatus.Off -> StatusChip("Desligado", ChipTone.Off)
            is FeatureStatus.Pending -> StatusChip(s.requirement.chip, ChipTone.Warn)
        }
    }
}
