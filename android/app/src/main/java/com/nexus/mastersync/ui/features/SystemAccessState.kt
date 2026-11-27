package com.nexus.mastersync.ui.features

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.compose.LifecycleResumeEffect

/** Android permissions the features depend on, re-read every time the app comes back to the foreground. */
@Composable
fun rememberSystemAccess(): SystemAccess {
    val context = LocalContext.current
    var revision by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(context) {
        revision++
        onPauseOrDispose {}
    }
    return remember(context, revision) { readSystemAccess(context) }
}

private fun readSystemAccess(context: Context): SystemAccess {
    fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    val mediaFull = if (Build.VERSION.SDK_INT >= 33) {
        granted(Manifest.permission.READ_MEDIA_IMAGES) && granted(Manifest.permission.READ_MEDIA_VIDEO)
    } else granted(Manifest.permission.READ_EXTERNAL_STORAGE)
    val mediaPartial = Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    return SystemAccess(
        camera = granted(Manifest.permission.CAMERA),
        mediaFull = mediaFull,
        mediaPartial = mediaPartial,
        appNotifications = NotificationManagerCompat.from(context).areNotificationsEnabled(),
        notificationListener = context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context),
        sms = granted(Manifest.permission.READ_SMS) && granted(Manifest.permission.SEND_SMS)
    )
}
