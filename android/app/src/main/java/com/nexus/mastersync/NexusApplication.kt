package com.nexus.mastersync

import android.app.Application
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import com.nexus.mastersync.protocol.LocalClient
import com.nexus.mastersync.protocol.Wire
import com.nexus.mastersync.services.NotificationRelay
import com.nexus.mastersync.services.RequestNotifications
import com.nexus.mastersync.services.DeviceActions
import com.nexus.mastersync.services.ClipboardSync
import com.nexus.mastersync.services.RemoteGallery
import com.nexus.mastersync.services.ScanLibrary
import com.nexus.mastersync.services.ScreenMirrorService
import com.nexus.mastersync.services.TransferQueue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class NexusApplication : Application() {
    lateinit var nexus: NexusController
        private set

    override fun onCreate() {
        super.onCreate()
        nexus = NexusController(this)
    }
}

class NexusController(val context: Context) {
    data class Options(
        val clipboard: Boolean = false,
        val files: Boolean = false,
        val notificationMirror: Boolean = false,
        val hideNotifications: Boolean = true,
        val remoteScan: Boolean = false,
        val autoScan: Boolean = false,
        val gallery: Boolean = false,
        val syncNewMedia: Boolean = false,
        val mirror: Boolean = false,
        val findPhone: Boolean = false,
        val mediaControl: Boolean = false,
        val theme: String = "system",
        val blockedApps: Set<String> = emptySet()
    )

    data class Permissions(val clipboard: Boolean = false, val files: Boolean = false, val notifications: Boolean = false,
        val gallery: Boolean = false, val clipboardImages: Boolean = false, val chat: Boolean = false)
    data class CameraRequest(val peer: String, val id: String)
    data class MirrorRequest(val peer: String, val id: String, val size: Int, val fps: Int, val quality: Int)
    private data class Battery(val level: Int?, val charging: Boolean)

    private val storage = context.getSharedPreferences("integration-v1", Context.MODE_PRIVATE)
    data class ChatEntry(val peer: String, val id: String, val text: String, val outgoing: Boolean, val confirmed: Boolean,
                         val time: Long = 0) {
        fun toJson(): JSONObject = JSONObject().put("peer", peer).put("id", id).put("text", text)
            .put("outgoing", outgoing).put("confirmed", confirmed).put("time", time)

        companion object {
            fun fromJson(item: JSONObject) = ChatEntry(item.getString("peer"), item.getString("id"), item.getString("text"),
                item.getBoolean("outgoing"), item.getBoolean("confirmed"), item.optLong("time", 0))
        }
    }
    private val chatHistory = MutableStateFlow(readChat())
    val messages = chatHistory.asStateFlow()

    private fun readChat(): List<ChatEntry> = runCatching {
        val array = JSONArray(storage.getString("chat-history", "[]"))
        List(array.length()) { index -> ChatEntry.fromJson(array.getJSONObject(index)) }
    }.getOrDefault(emptyList())

    private fun saveChat(entries: List<ChatEntry>) {
        val recent = entries.takeLast(400)
        val json = JSONArray()
        recent.forEach { item -> json.put(item.toJson()) }
        storage.edit().putString("chat-history", json.toString()).apply()
        chatHistory.value = recent
    }

    fun sendChat(draft: String): Boolean {
        val peer = client.status.value.connected?.id ?: return false
        val text = draft.trim()
        if (!permissions.value.chat || text.isEmpty() || text.toByteArray().size > 2048) return false
        val id = Wire.id()
        if (!client.sendTo(peer, Wire.message("chat").put("id", id).put("text", text))) return false
        saveChat(chatHistory.value + ChatEntry(peer, id, text, true, false, System.currentTimeMillis()))
        return true
    }

    private fun receiveChat(peer: String, message: JSONObject) {
        val id = message.optString("id")
        if (!permissions.value.chat || !Wire.validID(id)) return
        if (message.optString("type") == "chatAck") {
            saveChat(chatHistory.value.map { item ->
                if (item.peer == peer && item.id == id && item.outgoing) item.copy(confirmed = true) else item
            })
        } else {
            val text = message.optString("text")
            if (text.isEmpty() || text.toByteArray().size > 2048) return
            if (chatHistory.value.none { it.peer == peer && it.id == id }) {
                saveChat(chatHistory.value + ChatEntry(peer, id, text, false, true, System.currentTimeMillis()))
            }
            client.sendTo(peer, Wire.message("chatAck").put("id", id))
        }
    }

    private val settings = MutableStateFlow(readOptions())
    val options = settings.asStateFlow()
    private val remote = MutableStateFlow(Permissions())
    val permissions = remote.asStateFlow()
    private val noticeApps = MutableStateFlow<Map<String, String>>(emptyMap())
    val apps = noticeApps.asStateFlow()
    var backgroundRequested = storage.getBoolean("connection-in-background", true)
        private set
    private var backgroundStarting = false
    private val keepConnected = MutableStateFlow(false)
    val background = keepConnected.asStateFlow()
    data class ScanRequest(val peer: String, val id: String?)
    private val scanRequest = MutableStateFlow<ScanRequest?>(null)
    val pendingScan = scanRequest.asStateFlow()
    private val photoRequest = MutableStateFlow<CameraRequest?>(null)
    val pendingPhoto = photoRequest.asStateFlow()
    private var capturingPhoto: CameraRequest? = null

    fun decidePhoto(allow: Boolean): CameraRequest? {
        val request = photoRequest.value ?: return null
        photoRequest.value = null
        if (!allow || !options.value.remoteScan || !options.value.files || !permissions.value.files ||
            client.status.value.connected?.id != request.peer) {
            photoStatus(request, "Pedido de foto recusado.")
            return null
        }
        capturingPhoto = request
        updateLifecycle()
        photoStatus(request, "Aguardando a foto no Android…", finished = false)
        return request
    }

    fun finishPhoto(request: CameraRequest) {
        if (capturingPhoto == request) capturingPhoto = null
        updateLifecycle()
    }

    fun photoStatus(request: CameraRequest, text: String, finished: Boolean = true) {
        client.sendTo(request.peer, Wire.message("cameraStatus").put("id", request.id)
            .put("message", text.take(130)).put("more", !finished))
    }

    private val mirrorRequest = MutableStateFlow<MirrorRequest?>(null)
    val pendingMirror = mirrorRequest.asStateFlow()
    private var approvedMirror: String? = null
    private val activeMirror = MutableStateFlow(false)
    val mirroring = activeMirror.asStateFlow()
    var screenService: ScreenMirrorService? = null

    private val notes = MutableStateFlow("")
    val feedback = notes.asStateFlow()

    private val main = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private var foreground = false
    private var lastPeer: String? = null
    private var adbProof: Pair<String, Long>? = null

    fun verifyAdbProof(candidate: String): Boolean {
        val proof = adbProof ?: return false
        if (proof.first != candidate || android.os.SystemClock.elapsedRealtime() > proof.second) return false
        adbProof = null
        return true
    }
    private val actions = DeviceActions(context)
    private var battery = Battery(null, false)
    var supportsNoticeSync = false
        private set
    var listener: NotificationRelay? = null

    val client = LocalClient(context) { peer, message -> main.launch { receive(peer, message) } }
    val transfers = TransferQueue(context, client::sendTo)
    val scans = ScanLibrary(context)
    val gallery = RemoteGallery(context, { peer ->
        options.value.gallery && permissions.value.gallery && client.status.value.connected?.id == peer
    }, client::sendTo, transfers)
    private val clipboard = ClipboardSync(context, ::clipboardPeer, client::sendTo, ::note)
    val keyboardSelected = clipboard.keyboardSelected
    val lastClip = clipboard.lastReceived

    init {
        context.registerReceiver(object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val capacity = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val value = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val state = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val level = if (capacity > 0 && value >= 0) (100 * value / capacity).coerceIn(0, 100) else null
                battery = Battery(level, state == BatteryManager.BATTERY_STATUS_CHARGING || state == BatteryManager.BATTERY_STATUS_FULL)
                sendBattery()
            }
        }, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        main.launch {
            client.status.collect { status ->
                val id = status.connected?.id
                if (lastPeer != id) {
                    lastPeer = id
                    adbProof = null
                    remote.value = Permissions()
                    supportsNoticeSync = false
                    actions.stop()
                    clipboard.targetChanged()
                    scanRequest.value = null
                    photoRequest.value = null
                    capturingPhoto = null
                    mirrorRequest.value = null
                    approvedMirror = null
                    if (screenService != null) stopMirror()
                    updateTransfers()
                }
                if (id != null) {
                    sendBattery()
                    advertise()
                }
            }
        }
    }

    fun setVisible(visible: Boolean) {
        foreground = visible
        updateLifecycle()
    }

    fun requestBackgroundConnection(enabled: Boolean) {
        if (backgroundRequested == enabled) return
        backgroundRequested = enabled
        storage.edit().putBoolean("connection-in-background", enabled).apply()
        if (!enabled) {
            backgroundStarting = false
            setBackground(false)
        }
    }

    fun beginBackgroundStart(): Boolean {
        if (!backgroundRequested || keepConnected.value || backgroundStarting) return false
        // Avoid suspending the socket while Android starts the foreground service.
        backgroundStarting = true
        return true
    }

    fun setBackground(active: Boolean) {
        backgroundStarting = false
        keepConnected.value = active
        updateLifecycle()
        advertise()
    }

    fun refreshPermissions() {
        clipboard.refreshKeyboard()
        advertise()
        listener?.refresh()
        updateTransfers()
    }

    private fun updateLifecycle() {
        if (foreground || backgroundStarting || keepConnected.value || activeMirror.value || approvedMirror != null || capturingPhoto != null) client.start()
        else client.suspendConnection()
    }

    fun update(next: Options) {
        require(next.theme in setOf("system", "light", "dark"))
        if (next.syncNewMedia && !settings.value.syncNewMedia) {
            storage.edit().putLong("media-sync-since", System.currentTimeMillis() / 1000).apply()
        }
        storage.edit().putBoolean("sync-new-media", next.syncNewMedia).putBoolean("clipboard", next.clipboard).putBoolean("files", next.files)
            .putBoolean("notification-mirror", next.notificationMirror).putBoolean("hide-notifications", next.hideNotifications)
            .putBoolean("remote-scan", next.remoteScan).putBoolean("auto-scan", next.autoScan)
            .putBoolean("gallery", next.gallery).putBoolean("mirror", next.mirror)
            .putBoolean("find", next.findPhone).putBoolean("media-control", next.mediaControl).putString("theme", next.theme).putStringSet("blocked-apps", next.blockedApps).apply()
        settings.value = next
        if (!next.findPhone) actions.stop()
        if (!next.remoteScan && scanRequest.value != null) decideScan(false)
        if (!next.mirror) {
            decideMirror(false)
            approvedMirror = null
            if (activeMirror.value) stopMirror()
            else updateLifecycle()
        }
        advertise()
        clipboard.targetChanged()
        updateTransfers()
        listener?.refresh()
    }

    fun setFocus(hasFocus: Boolean) = clipboard.setFocus(hasFocus)

    fun offerFile(uri: android.net.Uri) {
        val peer = client.status.value.connected
        if (peer == null || !options.value.files || !permissions.value.files) {
            note("Conecte-se ao Mac e ative arquivos nos dois dispositivos.")
        } else transfers.offer(uri, peer.id)
    }

    fun scanDestination(authorizedPeer: String?): String? = authorizedPeer ?: client.selectedAuthorizedMac()
        .takeIf { options.value.autoScan && options.value.files }

    suspend fun saveScan(pdf: Uri?, pages: List<Uri>, destination: String?, capture: File? = null, requestID: String? = null): ScanLibrary.Document {
        // Saving and queuing can finish if the activity is recreated during a scan.
        return main.async {
            val document = try { scans.save(pdf, pages) } finally { capture?.delete() }
            if (destination != null && options.value.files && client.status.value.peers.any { it.id == destination }) {
                val ready = client.status.value.connected?.id == destination && permissions.value.files
                note(if (ready) "Digitalização salva no Android. Preparando o envio ao Mac."
                    else "Digitalização salva no Android. O envio aguarda conexão com o Mac e Arquivos ativos nos dois aparelhos.")
                val failure: (String) -> Unit = { note("Digitalização salva no Android. $it") }
                document.pages.forEachIndexed { index, file ->
                    transfers.offerFile(file, destination, scans.name(document, page = index + 1), "image/jpeg",
                        scanPage = true, transferId = if (index == 0 && requestID != null) requestID else Wire.id(),
                        onFailure = failure)
                }
                transfers.offerFile(document.pdf, destination, scans.name(document), "application/pdf", onFailure = failure)
            } else note(if (options.value.autoScan || destination != null)
                "Digitalização salva no Android. Para enviar, pareie o Mac e ative Arquivos nos dois aparelhos."
                else "Digitalização salva no Android.")
            document
        }.await()
    }

    fun forget(id: String) {
        client.forget(id)
        transfers.forget(id)
    }

    fun notificationSettingsChanged() {
        advertise()
        listener?.refresh()
    }

    fun noticeApp(packageName: String, label: String) {
        if (noticeApps.value[packageName] == label) return
        noticeApps.value = noticeApps.value + (packageName to label)
    }

    fun canMirrorNotices() = options.value.notificationMirror && permissions.value.notifications &&
        client.status.value.connected != null

    fun canPostNotifications(): Boolean = context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    fun decideScan(allow: Boolean): ScanRequest? {
        val request = scanRequest.value ?: return null
        scanRequest.value = null
        val connected = client.status.value.connected?.id == request.peer
        if (connected) {
            val status = Wire.message("scanStatus").put("message",
                if (allow) "Scanner autorizado no Android." else "Solicitação recusada no Android.")
            request.id?.let { status.put("id", it).put("more", allow) }
            client.sendTo(request.peer, status)
        }
        return request.takeIf { connected && allow }
    }

    fun decideMirror(allow: Boolean): MirrorRequest? {
        val request = mirrorRequest.value ?: return null
        mirrorRequest.value = null
        if (!allow) client.sendTo(request.peer, Wire.message("screenEnded").put("message", "Espelhamento recusado no Android."))
        return request.takeIf { allow && client.status.value.connected?.id == request.peer }?.also {
            approvedMirror = it.id
        }
    }

    fun confirmMirror(request: MirrorRequest, consent: Boolean): Boolean {
        val valid = consent && approvedMirror == request.id &&
            options.value.mirror && client.status.value.connected?.id == request.peer
        approvedMirror = null
        if (valid) activeMirror.value = true
        updateLifecycle()
        return valid
    }

    fun setMirroring(enabled: Boolean) {
        activeMirror.value = enabled
        updateLifecycle()
    }

    fun stopMirror() {
        context.stopService(Intent(context, ScreenMirrorService::class.java))
    }

    fun note(text: String) { notes.value = text }

    private fun receive(peer: String, message: JSONObject) {
        if (client.status.value.connected?.id != peer) return
        when (val type = message.optString("type")) {
            "capabilities" -> {
                val noticeSyncChanged = supportsNoticeSync != message.optBoolean("noticeSync")
                supportsNoticeSync = message.optBoolean("noticeSync")
                val state = Permissions(message.optBoolean("clipboard"), message.optBoolean("files"),
                    message.optBoolean("notifications"), message.optBoolean("gallery"), message.optBoolean("clipboardImages"), message.optBoolean("chat"))
                val notificationsChanged = state.notifications != remote.value.notifications
                if (state != remote.value) {
                    remote.value = state
                    clipboard.targetChanged()
                    updateTransfers()
                }
                if (noticeSyncChanged || notificationsChanged) listener?.refresh()
            }
            "launcherAppsRequest" -> {
                val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                val manager = context.packageManager
                val apps = JSONArray()
                // Only launcher activities are eligible, including third-party apps visible to the user.
                manager.queryIntentActivities(intent, 0).distinctBy { it.activityInfo.packageName }
                    .take(200).forEach { entry ->
                        val activity = entry.activityInfo
                        apps.put(JSONObject()
                            .put("component", "${activity.packageName}/${activity.name}")
                            .put("label", entry.loadLabel(manager).toString().take(70)))
                    }
                client.sendTo(peer, Wire.message("launcherApps").put("launcherApps", apps))
            }
            "launcherIconsRequest" -> {
                val components = com.nexus.mastersync.services.LauncherIcons.requested(message)
                if (components.isEmpty()) return
                client.sendTo(peer, Wire.message("launcherIcons")
                    .put("launcherIcons", com.nexus.mastersync.services.LauncherIcons.render(context, components)))
            }
            "adbProof" -> {
                val nonce = message.optString("id")
                if (!Wire.validID(nonce)) return
                adbProof = nonce to (android.os.SystemClock.elapsedRealtime() + 12_000)
                client.sendTo(peer, Wire.message("adbProofReady").put("id", nonce))
            }
            "chat", "chatAck" -> receiveChat(peer, message)
            "clipboard", "clipboardImageOffer", "clipboardImageAck", "clipboardImagePart", "clipboardImageDone" ->
                clipboard.receive(peer, message)
            "noticeRefresh" -> listener?.refresh()
            "dndSet" -> if (supportsNoticeSync && message.has("dndEnabled")) listener?.receive(message)
            "noticeReply", "noticeDismiss" -> if (canMirrorNotices()) listener?.receive(message)
            "ringPhone" -> if (options.value.findPhone) {
                client.sendTo(peer, Wire.message("actionStatus").put("message", actions.ring()))
            }
            "mediaStatusRequest" -> if (options.value.mediaControl) {
                listener?.mediaStatus()?.let { client.sendTo(peer, it) }
            }
            "mediaCommand" -> if (options.value.mediaControl) {
                listener?.media(message.optString("message"))?.let { result ->
                    client.sendTo(peer, Wire.message("actionStatus").put("message", result))
                    listener?.mediaStatus()?.let { client.sendTo(peer, it) }
                }
            }
            "screenRequest" -> {
                val id = message.optString("id")
                if (!options.value.mirror || activeMirror.value || mirrorRequest.value != null ||
                    approvedMirror != null || !Wire.validID(id)) return
                mirrorRequest.value = MirrorRequest(peer, id, message.optInt("size", 768),
                    message.optInt("rate", 10), message.optInt("quality", 68))
                if (!foreground && canPostNotifications()) RequestNotifications.notifyScreen(context)
            }
            "screenAck" -> screenService?.acknowledge(message.optString("id"))
            "screenStop" -> {
                decideMirror(false)
                approvedMirror = null
                if (activeMirror.value) stopMirror()
                else updateLifecycle()
            }
            "cameraRequest" -> {
                val id = message.optString("id")
                if (!options.value.remoteScan || !options.value.files || !permissions.value.files || !Wire.validID(id)) return
                val request = CameraRequest(peer, id)
                if (photoRequest.value != null || capturingPhoto != null) {
                    photoStatus(request, "Já existe uma solicitação de câmera no celular.")
                    return
                }
                photoRequest.value = request
                if (!foreground && canPostNotifications()) RequestNotifications.notifyPhoto(context)
            }
            "scanRequest" -> {
                if (!options.value.remoteScan || !options.value.files || !permissions.value.files) return
                if (scanRequest.value != null) return
                scanRequest.value = ScanRequest(peer, message.optString("id").takeIf(Wire::validID))
                if (!foreground && canPostNotifications()) RequestNotifications.notifyScan(context)
            }
            else -> when {
                type.startsWith("file") -> transfers.handle(peer, message)
                type.startsWith("gallery") -> gallery.receive(peer, message, options.value.files && permissions.value.files)
            }
        }
    }

    private fun advertise() {
        val local = options.value
        client.send(Wire.message("capabilities").put("clipboard", local.clipboard).put("files", local.files)
            .put("notifications", local.notificationMirror && listener != null).put("noticeSync", listener != null)
            .put("instantCamera", local.remoteScan && local.files).put("scanPaste", local.remoteScan && local.files).put("scanner", local.remoteScan && local.files).put("gallery", local.gallery && gallery.available()).put("mirror", local.mirror)
            .put("galleryRevision", 2).put("backgroundConnection", keepConnected.value).put("clipboardImages", local.clipboard)
            .put("launcher", true).put("adbProof", true).put("chat", true).put("findPhone", local.findPhone).put("mediaControl", local.mediaControl && listener != null))
    }

    private fun updateTransfers() {
        val peer = client.status.value.connected?.id
        val filesPeer = peer.takeIf { options.value.files && permissions.value.files }
        transfers.permission(filesPeer)
        gallery.watch(filesPeer.takeIf {
            options.value.gallery && options.value.syncNewMedia && permissions.value.gallery && gallery.available()
        }, storage.getLong("media-sync-since", System.currentTimeMillis() / 1000))
    }

    private fun sendBattery() {
        val status = Wire.message("status").put("charging", battery.charging)
        battery.level?.let { status.put("battery", it) }
        client.send(status)
    }

    private fun clipboardPeer(): ClipboardSync.Peer? {
        val id = client.status.value.connected?.id ?: return null
        if (!options.value.clipboard || !permissions.value.clipboard) return null
        return ClipboardSync.Peer(id, permissions.value.clipboardImages)
    }

    private fun readOptions() = Options(
        clipboard = storage.getBoolean("clipboard", false),
        files = storage.getBoolean("files", false),
        notificationMirror = storage.getBoolean("notification-mirror", false),
        hideNotifications = storage.getBoolean("hide-notifications", true),
        remoteScan = storage.getBoolean("remote-scan", false),
        autoScan = storage.getBoolean("auto-scan", false),
        gallery = storage.getBoolean("gallery", false),
        syncNewMedia = storage.getBoolean("sync-new-media", false),
        mirror = storage.getBoolean("mirror", false),
        findPhone = storage.getBoolean("find", false),
        mediaControl = storage.getBoolean("media-control", false),
        theme = storage.getString("theme", "system") ?: "system",
        blockedApps = storage.getStringSet("blocked-apps", emptySet()).orEmpty()
    )
}
