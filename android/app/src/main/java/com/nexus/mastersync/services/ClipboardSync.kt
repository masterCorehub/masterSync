package com.nexus.mastersync.services

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.database.ContentObserver
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.Settings
import androidx.core.content.FileProvider
import com.nexus.mastersync.protocol.ClipboardImages
import com.nexus.mastersync.protocol.Wire
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

class ClipboardFileProvider : FileProvider()

class ClipboardSync(
    private val context: Context,
    private val allowedPeer: () -> Peer?,
    private val send: (String, JSONObject) -> Boolean,
    private val status: (String) -> Unit
) {
    data class Peer(val id: String, val images: Boolean)
    data class Received(val text: String? = null, val image: Boolean = false)

    private val manager = context.getSystemService(ClipboardManager::class.java)
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private val mutableReceived = MutableStateFlow<Received?>(null)
    private val mutableKeyboard = MutableStateFlow(false)
    val lastReceived = mutableReceived.asStateFlow()
    val keyboardSelected = mutableKeyboard.asStateFlow()
    private var focused = false
    private var target: Peer? = null
    private var scanGeneration = 0L
    private var imageWriteGeneration = 0L
    private var lastTimestamp = -1L
    private val directory = File(context.cacheDir, "nexus-clipboard")

    private val images = ClipboardImages(
        send = { message -> target?.takeIf { it == allowedPeer() && it.images }?.let { send(it.id, message) } == true },
        received = ::applyImage
    )

    init {
        manager.addPrimaryClipChangedListener { observe() }
        context.contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD), false,
            object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) { refreshKeyboard() }
            }
        )
        refreshKeyboard()
    }

    fun setFocus(value: Boolean) {
        focused = value
        if (value) observe()
    }

    fun refreshKeyboard() {
        val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        mutableKeyboard.value = id?.let(ComponentName::unflattenFromString) == ComponentName(context, NexusKeyboard::class.java)
    }

    fun targetChanged() {
        // The Nexus window can gain focus before the Mac announces its permissions.
        if (refreshTarget() && focused) observe()
    }

    private fun refreshTarget(): Boolean {
        val peer = allowedPeer()
        if (target == peer) return false
        target = peer
        scanGeneration++
        imageWriteGeneration++
        images.reset()
        mutableReceived.value = null
        return true
    }

    fun receive(peer: String, message: JSONObject) {
        val active = allowedPeer()?.takeIf { it.id == peer } ?: return
        refreshTarget()
        if (message.optBoolean("sensitive")) return
        if (message.optString("type") == "clipboard") {
            val text = message.optString("text")
            if (!validText(text)) return
            scanGeneration++
            imageWriteGeneration++
            images.cancelIncoming()
            apply(ClipData.newPlainText("Nexus masterSync", text), Received(text = text))
        } else if (active.images) images.receive(message)
    }

    private fun observe() {
        val peer = allowedPeer() ?: return
        if (!focused && !keyboardSelected.value) return
        refreshTarget()
        val clip = runCatching { manager.primaryClip }.getOrNull() ?: return
        val description = clip.description
        val extras = description.extras
        if (extras?.getBoolean(REMOTE_MARKER) == true) return
        if (clip.itemCount == 0 || extras?.getBoolean("android.content.extra.IS_SENSITIVE") == true) {
            scanGeneration++
            images.cancelOutgoing()
            return
        }
        val timestamp = description.timestamp
        if (timestamp > 0 && timestamp == lastTimestamp) return
        val generation = ++scanGeneration
        imageWriteGeneration++
        val item = clip.getItemAt(0)
        val uri = item.uri
        if (peer.images && uri?.scheme == "content" && description.hasMimeType("image/*")) {
            lastTimestamp = timestamp
            scope.launch {
                val image = withContext(Dispatchers.IO) { readImage(uri) }
                if (generation != scanGeneration || allowedPeer() != peer) return@launch
                if (image == null) status("O Android não conseguiu copiar esta imagem. O limite é de 8 MB.")
                else images.offer(image.first, image.second)
            }
        } else {
            val text = item.text?.toString()?.takeIf(::validText) ?: return
            images.cancelOutgoing()
            if (send(peer.id, Wire.message("clipboard").put("text", text))) lastTimestamp = timestamp
        }
    }

    private fun readImage(uri: Uri): Pair<ByteArray, String>? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() + count > ClipboardImages.LIMIT) return null
                output.write(buffer, 0, count)
            }
            val bytes = output.toByteArray()
            validatedMime(bytes)?.let { bytes to it }
        }
    }.getOrNull()

    private fun applyImage(bytes: ByteArray, mime: String) {
        val peer = allowedPeer()?.takeIf { it.images } ?: return
        val generation = ++imageWriteGeneration
        val observed = ++scanGeneration
        scope.launch {
            val file = withContext(Dispatchers.IO) {
                if (validatedMime(bytes) != mime) return@withContext null
                runCatching {
                    directory.mkdirs()
                    File(directory, "${Wire.id()}.${ClipboardImages.EXTENSIONS.getValue(mime)}").apply { writeBytes(bytes) }
                }.getOrNull()
            } ?: return@launch
            if (generation != imageWriteGeneration || observed != scanGeneration || allowedPeer() != peer) {
                withContext(Dispatchers.IO) { file.delete() }
                return@launch
            }
            val changed = runCatching {
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.clipboard", file)
                apply(ClipData.newUri(context.contentResolver, "Imagem do Nexus", uri), Received(image = true))
            }.getOrDefault(false)
            withContext(Dispatchers.IO) {
                if (!changed) file.delete()
                else directory.listFiles().orEmpty().filter { it != file }.sortedByDescending { it.lastModified() }.drop(2)
                    .forEach { it.delete() }
            }
        }
    }

    private fun apply(clip: ClipData, received: Received): Boolean = runCatching {
        // Metadata follows the system clipboard event and blocks an echo to the remote peer.
        clip.description.extras = PersistableBundle().apply { putBoolean(REMOTE_MARKER, true) }
        manager.setPrimaryClip(clip)
        mutableReceived.value = received
        true
    }.onFailure { status("O Android não conseguiu escrever na área de transferência.") }.getOrDefault(false)

    private fun validText(text: String) = text.isNotEmpty() && text.toByteArray().size <= 32 * 1024

    private fun validatedMime(bytes: ByteArray): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val mime = bounds.outMimeType
        return mime?.takeIf { it in ClipboardImages.EXTENSIONS && bounds.outHeight in 1..16_384 &&
            bounds.outWidth > 0 && bounds.outWidth <= 24_000_000 / bounds.outHeight }
    }

    private companion object {
        const val REMOTE_MARKER = "com.nexus.mastersync.clipboard.REMOTE"
    }
}
