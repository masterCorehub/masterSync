package com.nexus.mastersync.ui.connection

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nexus.mastersync.NexusController
import com.nexus.mastersync.protocol.MacPeer
import com.nexus.mastersync.ui.NexusActions
import com.nexus.mastersync.ui.components.Muted
import com.nexus.mastersync.ui.components.NexusPanel
import com.nexus.mastersync.ui.components.Pill
import com.nexus.mastersync.ui.components.SectionLabel
import com.nexus.mastersync.ui.components.ToggleRow
import com.nexus.mastersync.ui.home.MacCard
import com.nexus.mastersync.ui.theme.LocalNexusColors

@Composable
fun ConnectionScreen(nexus: NexusController, background: Boolean, actions: NexusActions) {
    val c = LocalNexusColors.current
    val status by nexus.client.status.collectAsStateWithLifecycle()
    val options by nexus.options.collectAsStateWithLifecycle()
    var forget by remember { mutableStateOf<MacPeer?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MacCard(status, background, onOpenConnection = null, onReadQr = actions.readQr)
        NexusPanel {
            ToggleRow("Manter conexão em segundo plano", background, { actions.toggleBackground() },
                subtitle = "Recebe do Mac com outro app aberto. O Android mostra uma notificação.")
        }
        if (status.peers.isNotEmpty()) SectionLabel("Macs autorizados")
        if (status.peers.isNotEmpty()) NexusPanel {
            status.peers.forEachIndexed { index, peer ->
                if (index > 0) HorizontalDivider(color = c.control)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(peer.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                        Muted(if (status.connected?.id == peer.id) "Conectado" else "Desconectado")
                    }
                    if (status.connected?.id != peer.id) TextButton(onClick = { nexus.client.select(peer.id) }) {
                        Text("Conectar", color = c.accent)
                    }
                    TextButton(onClick = { forget = peer }) { Text("Esquecer", color = c.muted) }
                }
            }
            Pill("Parear outro Mac", actions.readQr)
        }
        SectionLabel("Aparência")
        NexusPanel {
            Text("Tema", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.semantics { heading() })
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf("system" to "Automático", "light" to "Claro", "dark" to "Escuro").forEach { (key, label) ->
                    Pill(label, { nexus.update(options.copy(theme = key)) }, selected = options.theme == key)
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
