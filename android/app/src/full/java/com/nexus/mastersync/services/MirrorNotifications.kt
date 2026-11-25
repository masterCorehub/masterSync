package com.nexus.mastersync.services

import android.app.KeyguardManager
import android.app.Notification
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.session.MediaSessionManager
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.nexus.mastersync.NexusApplication
import com.nexus.mastersync.protocol.Wire
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

class MirrorNotifications : NotificationListenerService(), NotificationRelay {
    private val nexus get() = (application as NexusApplication).nexus
    private val forwarded = mutableMapOf<String, StatusBarNotification>()

    override fun onListenerConnected() {
        nexus.listener = this
        nexus.notificationSettingsChanged()
    }

    override fun onListenerDisconnected() {
        forwarded.clear()
        if (nexus.listener === this) {
            nexus.listener = null
            nexus.notificationSettingsChanged()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) { post(sbn) }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val id = id(sbn.key)
        if (forwarded.remove(id) != null) remove(id)
    }

    override fun refresh() {
        val old = forwarded.keys.toSet()
        forwarded.clear()
        val active = runCatching { activeNotifications?.toList() }.getOrNull().orEmpty()
        active.take(50).forEach(::post)
        old.minus(forwarded.keys).forEach(::remove)
    }

    override fun receive(data: JSONObject) {
        val id = data.optString("id")
        val previous = forwarded[id] ?: return
        val current = runCatching { getActiveNotifications(arrayOf(previous.key))?.firstOrNull() }.getOrNull() ?: return
        if (current.packageName in nexus.options.value.blockedApps) return
        when (data.optString("type")) {
            "noticeDismiss" -> cancelNotification(current.key)
            "noticeReply" -> {
                if (privateContent(current)) return
                val action = replyAction(current) ?: return
                val value = data.optString("text")
                if (value.isBlank() || value.toByteArray().size > 1024) return
                val inputs = action.remoteInputs.filter { it.allowFreeFormInput }.toTypedArray()
                val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, value) } }
                val intent = Intent()
                RemoteInput.addResultsToIntent(inputs, intent, results)
                runCatching { action.actionIntent.send(this, 0, intent) }
                    .onFailure { nexus.note("O aplicativo não aceitou a resposta.") }
            }
        }
    }

    private fun post(sbn: StatusBarNotification) {
        val source = sbn.packageName
        val notification = sbn.notification
        if (source == packageName || sbn.isOngoing || notification.visibility == Notification.VISIBILITY_SECRET ||
            notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val label = runCatching { packageManager.getApplicationInfo(source, 0).loadLabel(packageManager).toString() }
            .getOrDefault(source).take(80)
        nexus.noticeApp(source, label)
        if (!nexus.canMirrorNotices() || source in nexus.options.value.blockedApps) return
        val redacted = privateContent(sbn)
        val extras = notification.extras ?: Bundle.EMPTY
        val id = id(sbn.key)
        val message = Wire.message("notice").put("id", id).put("app", label).put("group", source.take(180))
            .put("name", if (redacted) "Notificação recebida" else extras.getCharSequence(Notification.EXTRA_TITLE)?.take(120)?.toString() ?: label)
            .put("text", if (redacted) "" else extras.getCharSequence(Notification.EXTRA_TEXT)?.take(600)?.toString().orEmpty())
            .put("canReply", !redacted && replyAction(sbn) != null).put("at", sbn.postTime)
        icon(sbn)?.let { message.put("data", it) }
        if (nexus.client.send(message)) forwarded[id] = sbn
    }

    private fun privateContent(sbn: StatusBarNotification): Boolean =
        nexus.options.value.hideNotifications || sbn.notification.visibility == Notification.VISIBILITY_SECRET ||
            getSystemService(KeyguardManager::class.java).isDeviceLocked

    private fun replyAction(sbn: StatusBarNotification): Notification.Action? =
        sbn.notification.actions?.firstOrNull {
            it.actionIntent != null && it.remoteInputs?.any { input -> input.allowFreeFormInput } == true
        }

    private fun remove(id: String) { nexus.client.send(Wire.message("noticeRemoved").put("id", id)) }

    private fun id(value: String) = Wire.encode(MessageDigest.getInstance("SHA-256").digest(value.toByteArray()))

    private fun icon(sbn: StatusBarNotification): String? = runCatching {
        val drawable = sbn.notification.smallIcon?.loadDrawable(this) ?: return null
        val bitmap = Bitmap.createBitmap(36, 36, Bitmap.Config.ARGB_8888)
        try {
            drawable.setBounds(0, 0, 36, 36)
            drawable.draw(Canvas(bitmap))
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            Wire.encode(output.toByteArray())
        } finally { bitmap.recycle() }
    }.getOrNull()

    override fun media(command: String): String = runCatching {
        val manager = getSystemService(MediaSessionManager::class.java)
        val source = ComponentName(this, MirrorNotifications::class.java)
        val session = manager.getActiveSessions(source).firstOrNull()
            ?: return "Nenhum aplicativo de mídia está ativo no Android."
        when (command) {
            "play" -> session.transportControls.play()
            "pause" -> session.transportControls.pause()
            "next" -> session.transportControls.skipToNext()
            "previous" -> session.transportControls.skipToPrevious()
            else -> return "Comando indisponível."
        }
        "Comando de mídia enviado."
    }.getOrDefault("Autorize o acesso às notificações para controlar a mídia.")
}
