package com.nexus.mastersync.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nexus.mastersync.ui.features.Requirement
import com.nexus.mastersync.ui.features.StepAction
import com.nexus.mastersync.ui.features.StepState
import com.nexus.mastersync.ui.theme.LocalNexusColors

@Composable
fun StepRow(index: Int, requirement: Requirement, onAction: (StepAction) -> Unit) {
    val c = LocalNexusColors.current
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val (mark, fg, bg, border) = when (requirement.state) {
            StepState.Done -> Quad("✓", c.accentInk, c.connected, null)
            StepState.Pending -> Quad("$index", c.accent, c.surface, BorderStroke(2.dp, c.accent))
            StepState.AwaitingMac -> Quad("$index", c.muted, c.control, null)
        }
        Surface(shape = CircleShape, color = bg, contentColor = fg, border = border, modifier = Modifier.size(24.dp)
            .semantics { contentDescription = when (requirement.state) {
                StepState.Done -> "Feito"; StepState.Pending -> "Pendente"; StepState.AwaitingMac -> "Aguardando o Mac" } }) {
            Box(contentAlignment = Alignment.Center) { Text(mark, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
        }
        Column(Modifier.weight(1f)) {
            Text(requirement.label, style = MaterialTheme.typography.bodyLarge,
                color = if (requirement.state == StepState.AwaitingMac) c.muted else c.ink)
            val detail = when {
                requirement.state == StepState.AwaitingMac -> "Confirme quando o Mac conectar"
                requirement.state == StepState.Pending || requirement.optional -> requirement.hint
                else -> null
            }
            if (detail != null) Muted(detail)
        }
        val action = requirement.action
        if (requirement.state == StepState.Pending && action != null) {
            Pill(requirement.chip, { onAction(action) }, prominent = !requirement.optional)
        }
    }
}

private data class Quad<A, B, C, D>(val a: A, val b: B, val c: C, val d: D)
