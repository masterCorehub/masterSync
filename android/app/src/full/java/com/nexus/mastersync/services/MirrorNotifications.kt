package com.nexus.mastersync.services

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaMetadata
import android.media.Rating
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
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
    private companion object { const val MAX_ART_BYTES = 48 * 1024 }

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
            getSystemService(KeyguardManager::class.java).isDeviceLocked,
            lockscreenSetting("lock_screen_allow_private_notifications"), lockscreenSetting("lock_screen_show_notifications"))

    // Hidden system keys behind the lock screen notification settings; unreadable means hide.
    private fun lockscreenSetting(key: String): Boolean = runCatching {
        android.provider.Settings.Secure.getInt(contentResolver, key, 1) != 0
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

    private fun activeSession(): MediaController? = runCatching {
        getSystemService(MediaSessionManager::class.java)
            .getActiveSessions(ComponentName(this, MirrorNotifications::class.java)).firstOrNull()
    }.getOrNull()

    private fun title(metadata: MediaMetadata?) =
        metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: metadata?.description?.title?.toString()

    private fun artist(metadata: MediaMetadata?) =
        metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: metadata?.description?.subtitle?.toString()

    override fun mediaStatus(): JSONObject? = runCatching {
        val session = activeSession() ?: return Wire.message("mediaStatus")
        val metadata = session.metadata
        val state = session.playbackState
        val snapshot = MediaSnapshot(
            title = title(metadata), artist = artist(metadata), album = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            year = (metadata?.getLong(MediaMetadata.METADATA_KEY_YEAR) ?: 0L).toInt(),
            track = (metadata?.getLong(MediaMetadata.METADATA_KEY_TRACK_NUMBER) ?: 0L).toInt(),
            tracks = (metadata?.getLong(MediaMetadata.METADATA_KEY_NUM_TRACKS) ?: 0L).toInt(),
            durationMs = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L,
            positionMs = state?.position ?: 0L,
            updatedAt = state?.lastPositionUpdateTime ?: 0L,
            speed = state?.playbackSpeed ?: 1f,
            playing = state?.let { it.state == PlaybackState.STATE_PLAYING },
            canSeek = ((state?.actions ?: 0L) and PlaybackState.ACTION_SEEK_TO) != 0L,
            canLike = session.ratingType == Rating.RATING_HEART,
            liked = metadata?.getRating(MediaMetadata.METADATA_KEY_USER_RATING)?.hasHeart() == true,
            hasQueue = session.queue?.isNotEmpty() == true
        )
        val payload = MediaPayload.status(snapshot, SystemClock.elapsedRealtime())
        Wire.message("mediaStatus").apply { payload.keys().forEach { if (it != "type") put(it, payload.get(it)) } }
    }.getOrNull()

    override fun media(command: String, argument: Long): String = runCatching {
        val session = activeSession() ?: return "Nenhum aplicativo de mídia está ativo no Android."
        val controls = session.transportControls
        when (command) {
            "play" -> controls.play()
            "pause" -> controls.pause()
            "next" -> controls.skipToNext()
            "previous" -> controls.skipToPrevious()
            "seek" -> if (argument >= 0) controls.seekTo(argument) else return "Posição inválida."
            "like", "unlike" -> {
                if (session.ratingType != Rating.RATING_HEART) return "Este aplicativo não permite favoritar."
                controls.setRating(Rating.newHeartRating(command == "like"))
            }
            "queueItem" -> {
                if (session.queue?.any { it.queueId == argument } != true) return "Esse item não está mais na fila."
                controls.skipToQueueItem(argument)
            }
            else -> return "Comando indisponível."
        }
        "Comando de mídia enviado."
    }.getOrDefault("Autorize o acesso às notificações para controlar a mídia.")

    /** The cover of the track playing now, as a small JPEG; null when [key] is no longer the current track. */
    override fun mediaArt(key: String): JSONObject? {
        val encoded = runCatching {
            val metadata = activeSession()?.metadata ?: return@runCatching null
            val current = MediaPayload.artKey(title(metadata), artist(metadata), metadata.getString(MediaMetadata.METADATA_KEY_ALBUM))
            if (key.isEmpty() || key != current) return@runCatching null
            val source = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART) ?: return@runCatching null
            listOf(256 to 80, 256 to 60, 192 to 60).firstNotNullOfOrNull { (edge, quality) ->
                jpeg(source, edge, quality)?.takeIf { it.size <= MAX_ART_BYTES }
            }?.let(Wire::encode)
        }.getOrNull()
        // Players often publish a track's metadata before its bitmap; answering without an image lets the Mac ask again.
        val reply = MediaPayload.artReply(key, encoded)
        return Wire.message("mediaArt").apply { reply.keys().forEach { if (it != "type") put(it, reply.get(it)) } }
    }

    private fun jpeg(source: Bitmap, edge: Int, quality: Int): ByteArray? = runCatching {
        val scale = minOf(1f, edge.toFloat() / maxOf(source.width, source.height))
        val scaled = if (scale < 1f) Bitmap.createScaledBitmap(source, (source.width * scale).toInt().coerceAtLeast(1),
            (source.height * scale).toInt().coerceAtLeast(1), true) else source
        try {
            ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
        } finally {
            // The metadata owns the original bitmap.
            if (scaled !== source) scaled.recycle()
        }
    }.getOrNull()

    override fun mediaQueue(): JSONObject? = runCatching {
        val session = activeSession() ?: return null
        val items = JSONArray()
        session.queue.orEmpty().take(MediaPayload.MAX_QUEUE).forEach { item ->
            items.put(JSONObject().put("id", item.queueId)
                .put("title", item.description.title?.toString().orEmpty().take(150)))
        }
        Wire.message("mediaQueue").put("queue", items)
            .apply { session.playbackState?.activeQueueItemId?.takeIf { it >= 0 }?.let { put("queueId", it) } }
    }.getOrNull()
}
