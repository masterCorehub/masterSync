package com.nexus.mastersync.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nexus.mastersync.ui.theme.LocalNexusColors

val PanelShape = RoundedCornerShape(19.dp)

@Composable
fun Pill(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, prominent: Boolean = false,
         enabled: Boolean = true, selected: Boolean = false) {
    val c = LocalNexusColors.current
    val filled = prominent || selected
    Button(onClick = onClick, enabled = enabled, shape = CircleShape, modifier = modifier.defaultMinSize(minHeight = 40.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (filled) c.accent else c.control, contentColor = if (filled) c.accentInk else c.ink,
            disabledContainerColor = (if (filled) c.accent else c.control).copy(alpha = 0.45f),
            disabledContentColor = (if (filled) c.accentInk else c.ink).copy(alpha = 0.6f)
        ), elevation = null) {
        Text(text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1)
    }
}

@Composable
fun NexusPanel(modifier: Modifier = Modifier, highlighted: Boolean = false, onClick: (() -> Unit)? = null,
               content: @Composable ColumnScope.() -> Unit) {
    val c = LocalNexusColors.current
    val color = if (highlighted) c.accentSurface else c.surface
    val border = BorderStroke(1.dp, if (highlighted) c.accent.copy(alpha = 0.5f) else c.border.copy(alpha = 0.65f))
    val body: @Composable () -> Unit = {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
    if (onClick != null) {
        Surface(onClick = onClick, modifier = modifier.fillMaxWidth(), shape = PanelShape, color = color,
            contentColor = c.ink, border = border, content = body)
    } else {
        Surface(modifier = modifier.fillMaxWidth(), shape = PanelShape, color = color, contentColor = c.ink,
            border = border, content = body)
    }
}

enum class ChipTone { Ok, Warn, Off }

@Composable
fun StatusChip(text: String, tone: ChipTone) {
    val c = LocalNexusColors.current
    val (fg, bg) = when (tone) {
        ChipTone.Ok -> c.connected to c.connected.copy(alpha = 0.16f)
        ChipTone.Warn -> c.accent to c.accentSurface
        ChipTone.Off -> c.muted to c.control
    }
    Surface(shape = CircleShape, color = bg, contentColor = fg) {
        Text(text, Modifier.padding(horizontal = 10.dp, vertical = 4.dp), fontSize = 12.sp,
            fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, subtitle: String? = null,
              enabled: Boolean = true) {
    val c = LocalNexusColors.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Muted(subtitle)
        }
        Switch(checked, onChange, enabled = enabled, colors = SwitchDefaults.colors(
            checkedTrackColor = c.accent, checkedThumbColor = c.accentInk,
            uncheckedTrackColor = c.control, uncheckedThumbColor = c.muted, uncheckedBorderColor = c.border))
    }
}

@Composable
fun Banner(text: String, action: String?, onAction: () -> Unit) {
    val c = LocalNexusColors.current
    Surface(shape = RoundedCornerShape(14.dp), color = c.accentSurface, contentColor = c.ink,
        border = BorderStroke(1.dp, c.accent.copy(alpha = 0.35f))) {
        Row(Modifier.fillMaxWidth().padding(start = 14.dp, top = 4.dp, bottom = 4.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f).padding(vertical = 8.dp), style = MaterialTheme.typography.bodyMedium)
            if (action != null) TextButton(onClick = onAction) {
                Text(action, color = c.accent, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(text.uppercase(), color = LocalNexusColors.current.muted, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        letterSpacing = 0.8.sp, modifier = Modifier.padding(start = 4.dp, top = 8.dp).semantics { heading() })
}

@Composable
fun Muted(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, color = LocalNexusColors.current.muted, style = MaterialTheme.typography.bodyMedium)
}
