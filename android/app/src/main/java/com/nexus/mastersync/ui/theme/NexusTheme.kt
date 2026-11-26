package com.nexus.mastersync.ui.theme

import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

/** Same tones as NexusPalette in the macOS app (NexusAppearance.swift). */
@Immutable
data class NexusColors(
    val canvas: Color, val surface: Color, val control: Color, val border: Color,
    val ink: Color, val muted: Color, val accent: Color, val accentInk: Color,
    val accentSurface: Color, val connected: Color, val dark: Boolean
)

val LightNexusColors = NexusColors(
    canvas = Color(0xFFF5EEE6), surface = Color(0xFFFFF9F2), control = Color(0xFFECE0D3), border = Color(0xFFDED0C2),
    ink = Color(0xFF281C16), muted = Color(0xFF635046), accent = Color(0xFF8A4925), accentInk = Color(0xFFFFF8F0),
    accentSurface = Color(0xFFF2E0CB), connected = Color(0xFF386342), dark = false
)

val DarkNexusColors = NexusColors(
    canvas = Color(0xFF191412), surface = Color(0xFF2F2521), control = Color(0xFF392E28), border = Color(0xFF59453B),
    ink = Color(0xFFF5ECE3), muted = Color(0xFFC4B1A3), accent = Color(0xFFF3BB7D), accentInk = Color(0xFF27180F),
    accentSurface = Color(0xFF473225), connected = Color(0xFFA6CD9E), dark = true
)

val LocalNexusColors = staticCompositionLocalOf { LightNexusColors }

@Composable
fun NexusTheme(dark: Boolean, content: @Composable () -> Unit) {
    val colors = if (dark) DarkNexusColors else LightNexusColors
    val scheme = with(colors) {
        val base = if (dark) darkColorScheme() else lightColorScheme()
        base.copy(
            primary = accent, onPrimary = accentInk, primaryContainer = accentSurface, onPrimaryContainer = ink,
            secondary = accent, onSecondary = accentInk, secondaryContainer = accentSurface, onSecondaryContainer = ink,
            background = canvas, onBackground = ink, surface = surface, onSurface = ink,
            surfaceVariant = control, onSurfaceVariant = muted, outline = border, outlineVariant = border,
            surfaceContainerLow = surface, surfaceContainer = surface, surfaceContainerHigh = canvas,
            surfaceContainerHighest = control
        )
    }
    CompositionLocalProvider(LocalNexusColors provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** Warm glow at the window edge, like NexusBackdrop on the Mac. Omitted when animations are turned off. */
@Composable
fun NexusBackdrop(modifier: Modifier = Modifier) {
    val colors = LocalNexusColors.current
    val context = LocalContext.current
    val reduced = remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.TRANSITION_ANIMATION_SCALE, 1f) == 0f
    }
    val radius = with(LocalDensity.current) { 540.dp.toPx() }
    BoxWithConstraints(modifier.fillMaxSize().background(colors.canvas)) {
        if (!reduced) {
            val w = constraints.maxWidth.toFloat()
            val h = constraints.maxHeight.toFloat()
            Box(Modifier.fillMaxSize().background(Brush.radialGradient(
                listOf(colors.accent.copy(alpha = if (colors.dark) 0.145f else 0.09f), Color.Transparent),
                center = Offset(w * 0.82f, h * 0.11f), radius = radius)))
        }
    }
}
