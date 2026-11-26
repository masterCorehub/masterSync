package com.nexus.mastersync.services

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.session.MediaSessionManager
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.nexus.mastersync.NexusApplication
import com.nexus.mastersync.protocol.Wire
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

class MirrorNotifications : NotificationListenerService(), NotificationRelay {
    private val nexus get() = (application as NexusApplication).nexus
    private val forwarded = mutableMapOf<String, StatusBarNotification>()

    private val handler = Handler(Looper.getMainLooper())
    private val retryRefresh = Runnable { if (nexus.listener === this) refresh() }

    override fun onListenerConnected() {
        nexus.listener = this
        nexus.notificationSettingsChanged()
    }

    override fun onListenerDisconnected() {
        handler.removeCallbacksAndMessages(null)
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
        handler.removeCallbacks(retryRefresh)
        val peer = nexus.client.status.value.connected?.id ?: return
        val modernPeer = nexus.supportsNoticeSync
        if (modernPeer) publishDnd(peer)
        if (!nexus.canMirrorNotices()) return
        val active = runCatching { activeNotifications }.getOrNull() ?: return
        if (!modernPeer) {
            val old = forwarded.keys.toSet()
            forwarded.clear()
            active.take(50).forEach(::post)
            old.minus(forwarded.keys).forEach(::remove)
            return
        }

        val entries = active.mapNotNull { notice -> entry(notice)?.let { notice to it } }
        val batches = entries.chunked(12).ifEmpty { listOf(emptyList()) }
        val snapshotID = Wire.id()
        // Commit on the last batch so the Mac never renders a partial snapshot.
        batches.forEachIndexed { index, batch ->
            val payload = Wire.message("noticeSnapshot").put("id", snapshotID)
                .put("offset", index).put("more", index < batches.lastIndex)
                .put("notices", JSONArray(batch.map { it.second }))
            if (!nexus.client.sendTo(peer, payload)) {
                handler.postDelayed(retryRefresh, 500)
                return
            }
        }
        forwarded.clear()
        entries.forEach { (notice, message) -> forwarded[message.getString("id")] = notice }
    }

    override fun onInterruptionFilterChanged(interruptionFilter: Int) {
        val peer = nexus.client.status.value.connected?.id ?: return
        if (nexus.supportsNoticeSync) publishDnd(peer)
    }

    private fun publishDnd(peer: String, requested: Boolean? = null, error: String? = null) {
        val manager = getSystemService(NotificationManager::class.java)
        val filter = manager.currentInterruptionFilter
        val enabled = filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        val message = Wire.message("dndState").put("dndAllowed", manager.isNotificationPolicyAccessGranted)
            .put("dndEnabled", enabled)
        val feedback = error ?: if (requested == false && enabled)
            "O Android continua em Não Perturbe. Verifique os modos ativos no celular."
            else if (requested == true && !enabled) "O Android não ativou o Não Perturbe." else null
        feedback?.let { message.put("message", it) }
        nexus.client.sendTo(peer, message)
    }

    private fun setDnd(enabled: Boolean) {
        val peer = nexus.client.status.value.connected?.id ?: return
        val manager = getSystemService(NotificationManager::class.java)
        if (!manager.isNotificationPolicyAccessGranted) {
            publishDnd(peer, error = "Autorize o Não Perturbe no MasterSync do Android.")
            return
        }
        runCatching {
            manager.setInterruptionFilter(if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY
                else NotificationManager.INTERRUPTION_FILTER_ALL)
        }.onSuccess {
            handler.postDelayed({ publishDnd(peer, requested = enabled) }, 500)
        }.onFailure {
            publishDnd(peer, error = "O Android não permitiu alterar o Não Perturbe.")
        }
    }

    override fun receive(data: JSONObject) {
        val id = data.optString("id")
        if (data.optString("type") == "dndSet") {
            setDnd(data.optBoolean("dndEnabled"))
            return
        }
        val dismiss = data.optString("type") == "noticeDismiss"
        val previous = forwarded[id] ?: run {
            if (dismiss && nexus.supportsNoticeSync) refresh()
            return
        }
        val active = runCatching { getActiveNotifications(arrayOf(previous.key)) }.getOrNull()
        if (active == null) {
            if (dismiss) dismissFailed(id)
            return
        }
        val current = active.firstOrNull()
        if (current == null) {
            forwarded.remove(id)
            remove(id)
            return
        }
        if (current.packageName in nexus.options.value.blockedApps) return
        when (data.optString("type")) {
            "noticeDismiss" -> {
                if (!current.isClearable || runCatching { cancelNotification(current.key) }.isFailure) {
                    dismissFailed(id)
                    return
                }
                val peer = nexus.client.status.value.connected?.id
                handler.postDelayed({
                    if (peer == nexus.client.status.value.connected?.id && forwarded[id] != null) {
                        val remaining = runCatching { getActiveNotifications(arrayOf(current.key)) }.getOrNull()
                        if (remaining?.isEmpty() == true) {
                            forwarded.remove(id)
                            remove(id)
                        } else dismissFailed(id)
                    }
                }, 1000)
            }
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
        val message = entry(sbn)
        val id = id(sbn.key)
        if (message == null) {
            if (forwarded.remove(id) != null) remove(id)
            return
        }
        if (nexus.client.send(message)) forwarded[id] = sbn
        else if (nexus.supportsNoticeSync) handler.postDelayed(retryRefresh, 500)
    }

    private fun entry(sbn: StatusBarNotification): JSONObject? {
        val source = sbn.packageName
        val notification = sbn.notification
        if (source == packageName || notification.visibility == Notification.VISIBILITY_SECRET ||
            notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null
        val label = runCatching { packageManager.getApplicationInfo(source, 0).loadLabel(packageManager).toString() }
            .getOrDefault(source).take(80)
        nexus.noticeApp(source, label)
        if (!nexus.canMirrorNotices() || source in nexus.options.value.blockedApps) return null
        val redacted = privateContent(sbn)
        val extras = notification.extras ?: Bundle.EMPTY
        val id = id(sbn.key)
        val message = Wire.message("notice").put("id", id).put("app", label).put("group", source.take(180))
            .put("name", if (redacted) "Notificação recebida" else extras.getCharSequence(Notification.EXTRA_TITLE)?.take(120)?.toString() ?: label)
            .put("text", if (redacted) "" else extras.getCharSequence(Notification.EXTRA_TEXT)?.take(600)?.toString().orEmpty())
            .put("canDismiss", sbn.isClearable).put("canReply", !redacted && replyAction(sbn) != null).put("at", sbn.postTime)
        icon(sbn)?.let { message.put("data", it) }
        return message
    }

    private fun dismissFailed(id: String) {
        nexus.client.send(Wire.message("noticeDismissFailed").put("id", id)
            .put("message", "O Android manteve essa notificação ativa."))
    }

    private fun privateContent(sbn: StatusBarNotification): Boolean =
        NoticePrivacy.redact(nexus.options.value.hideNotifications, sbn.notification.visibility,
            getSystemService(KeyguardManager::class.java).isDeviceLocked, lockscreenAllowsPrivate())

    // Hidden system key behind "Mostrar conteúdo sensível" on the lock screen; unreadable means hide.
    private fun lockscreenAllowsPrivate(): Boolean = runCatching {
        android.provider.Settings.Secure.getInt(contentResolver, "lock_screen_allow_private_notifications", 1) != 0
    }.getOrDefault(false)

    private fun replyAction(sbn: StatusBarNotification): Notification.Action? =
        sbn.notification.actions?.firstOrNull {
            it.actionIntent != null && it.remoteInputs?.any { input -> input.allowFreeFormInput } == true
        }

    private fun remove(id: String) {
        if (!nexus.client.send(Wire.message("noticeRemoved").put("id", id)) && nexus.supportsNoticeSync) {
            handler.postDelayed(retryRefresh, 500)
        }
    }

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

    override fun mediaStatus(): JSONObject? = runCatching {
        val source = ComponentName(this, MirrorNotifications::class.java)
        val session = getSystemService(MediaSessionManager::class.java).getActiveSessions(source).firstOrNull()
        Wire.message("mediaStatus").apply {
            session?.metadata?.description?.title?.toString()?.take(150)?.let { put("name", it) }
            session?.metadata?.description?.subtitle?.toString()?.take(150)?.let { put("text", it) }
            session?.playbackState?.let { put("playing", it.state == android.media.session.PlaybackState.STATE_PLAYING) }
        }
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
