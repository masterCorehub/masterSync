package com.nexus.mastersync.services

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.nexus.mastersync.protocol.Wire
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

class TransferQueue(private val context: Context, private val sendTo: (String, JSONObject) -> Boolean) {
    data class Item(val id: String, val name: String, val mime: String, val size: Long, val hash: String) {
        fun offer() = reply("fileOffer", id).put("name", name).put("mime", mime).put("size", size).put("hash", hash)
    }

    data class Progress(val id: String, val name: String, val size: Long, val offset: Long, val sending: Boolean)
    data class Received(val item: Item, val file: File, val peer: String)
    data class Sent(val peer: String, val name: String)
    private data class Outgoing(val peer: String, val item: Item, val file: File, val scanPage: Boolean,
                                val onFailure: ((String) -> Unit)?, var expected: Long? = null)
    private data class Incoming(val peer: String, val item: Item, val partial: File, val destination: File)

    private val root = File(context.filesDir, "nexus-inbox")
    private val staging = File(context.cacheDir, "nexus-outbox")
    private val worker = CoroutineScope(Dispatchers.IO.limitedParallelism(1) + SupervisorJob())
    private val mutableProgress = MutableStateFlow<List<Progress>>(emptyList())
    private val mutableReceived = MutableStateFlow<List<Received>>(emptyList())
    private val history = context.getSharedPreferences("file-history", Context.MODE_PRIVATE)
    private val mutableSent = MutableStateFlow(readSent())
    val sent = mutableSent.asStateFlow()
    private val mutableFeedback = MutableStateFlow("")
    val progress = mutableProgress.asStateFlow()
    val received = mutableReceived.asStateFlow()
    val feedback = mutableFeedback.asStateFlow()
    private val outgoing = ArrayDeque<Outgoing>()
    private var incoming: Incoming? = null
    private var activePeer: String? = null

    init { worker.launch { refreshReceived() } }

    private fun readSent(): List<Sent> = runCatching {
        val entries = JSONArray(history.getString("sent", "[]"))
        List(entries.length()) { index ->
            val item = entries.getJSONObject(index)
            Sent(item.getString("peer"), item.getString("name"))
        }
    }.getOrDefault(emptyList())

    private fun recordSent(peer: String, item: Item) {
        val recent = (mutableSent.value + Sent(peer, item.name)).takeLast(150)
        val encoded = JSONArray()
        recent.forEach { encoded.put(JSONObject().put("peer", it.peer).put("name", it.name)) }
        history.edit().putString("sent", encoded.toString()).apply()
        mutableSent.value = recent
    }

    fun permission(peer: String?) = worker.launch {
        if (activePeer != peer) {
            activePeer = peer
            incoming = null
            mutableProgress.value = emptyList()
            if (peer != null) announce()
        }
    }

    fun forget(peer: String) = worker.launch {
        outgoing.filter { it.peer == peer }.forEach { it.file.delete() }
        outgoing.removeAll { it.peer == peer }
    }

    fun offer(uri: Uri, peer: String, displayName: String? = null, mime: String? = null,
              transferId: String = Wire.id(), onFailure: ((String) -> Unit)? = null) = worker.launch {
        val resolver = context.contentResolver
        runCatching {
            require(Wire.validID(transferId))
            if (outgoing.any { it.peer == peer && it.item.id == transferId }) return@launch
            require(uri.scheme == "content") { "Selecione o arquivo pelo seletor do Android." }
            val name = displayName ?: resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "Arquivo"
            val type = mime ?: resolver.getType(uri) ?: "application/octet-stream"
            resolver.openInputStream(uri)?.use { stage(it, peer, name, type, transferId) }
                ?: throw IOException("O Android não conseguiu ler o arquivo.")
        }.onFailure {
            mutableFeedback.value = it.message ?: "Falha ao ler arquivo."
            onFailure?.invoke("O Android não conseguiu preparar o arquivo selecionado.")
        }
    }

    fun offerFile(file: File, peer: String, name: String, mime: String, scanPage: Boolean = false,
                  transferId: String = Wire.id(), onFailure: ((String) -> Unit)? = null) = worker.launch {
        runCatching { file.inputStream().use { stage(it, peer, name, mime, id = transferId, scanPage = scanPage, onFailure = onFailure) } }
            .onFailure {
                val reason = it.message ?: "Falha ao preparar arquivo."
                mutableFeedback.value = reason
                onFailure?.invoke(reason)
            }
    }

    private fun stage(input: InputStream, peer: String, name: String, mime: String, id: String = Wire.id(),
                      scanPage: Boolean = false, onFailure: ((String) -> Unit)? = null) {
        require(outgoing.size < 25) { "A fila de envio está cheia." }
        staging.mkdirs()
        // The request ID identifies the transfer, while a private temporary file holds its bytes.
        val file = File.createTempFile("upload-", ".part", staging)
        val digest = MessageDigest.getInstance("SHA-256")
        mutableFeedback.value = "Preparando ${safeName(name)}…"
        try {
            var size = 0L
            file.outputStream().use { output ->
                val buffer = ByteArray(Wire.CHUNK)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    size += count
                    if (size > Wire.MAX_FILE) throw IOException("O arquivo excede 4 GB.")
                    digest.update(buffer, 0, count)
                    output.write(buffer, 0, count)
                }
            }
            val first = outgoing.none { it.peer == peer }
            val item = Item(id, safeName(name), mime.take(120), size, Wire.encode(digest.digest()))
            outgoing.addLast(Outgoing(peer, item, file, scanPage, onFailure))
            if (first && activePeer == peer) announce()
            mutableFeedback.value = if (activePeer == peer) "" else "Envio aguardando conexão."
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    fun handle(peer: String, message: JSONObject) = worker.launch {
        val id = message.optString("id")
        if (!Wire.validID(id)) return@launch
        val type = message.optString("type")
        try {
            if (activePeer != peer) {
                if (type == "fileOffer") sendTo(peer, reply("fileError", id).put("message", "Recebimento desativado no Android."))
                return@launch
            }
            when (type) {
                "fileOffer" -> accept(peer, parse(message))
                "fileOffset", "fileAck" -> {
                    val out = outgoing.firstOrNull { it.peer == peer && it.item.id == id } ?: return@launch
                    val offset = message.optLong("offset", -1)
                    require(offset in 0..out.item.size)
                    if (type == "fileAck" && out.expected != offset) return@launch
                    sendChunk(out, offset)
                }
                "fileData" -> incoming?.takeIf { it.peer == peer && it.item.id == id }?.let { append(it, message) }
                "fileDone" -> incoming?.takeIf { it.peer == peer && it.item.id == id }?.let { finish(it) }
                "fileComplete" -> {
                    val out = outgoing.firstOrNull { it.peer == peer && it.item.id == id } ?: return@launch
                    outgoing.remove(out)
                    out.file.delete()
                    recordSent(peer, out.item)
                    clearProgress(id)
                    mutableFeedback.value = "${out.item.name} enviado."
                    announce()
                }
                "fileError" -> abort(id, message.optString("message").take(150))
            }
        } catch (error: Exception) {
            val description = error.message?.take(150)?.takeIf { it.isNotBlank() } ?: "Falha na transferência."
            send(reply("fileError", id).put("message", description))
            abort(id, description)
        }
    }

    private fun accept(peer: String, item: Item) {
        require(incoming == null || incoming?.item == item) { "O Android já recebe outro arquivo." }
        val folder = File(File(root, peer), item.id).apply { mkdirs() }
        val metadata = File(folder, "offer.json")
        val partial = File(folder, "content.part")
        val payload = File(folder, "arquivo").apply { mkdirs() }
        val destination = File(payload, item.name)
        if (metadata.exists()) require(parse(JSONObject(metadata.readText())) == item)
        else metadata.writeText(item.offer().toString())
        if (destination.exists()) {
            send(reply("fileComplete", item.id))
            return
        }
        if (!partial.exists()) partial.createNewFile()
        val offset = partial.length()
        require(offset <= item.size)
        require(item.size - offset <= (root.usableSpace - 128L * 1024 * 1024).coerceAtLeast(0)) {
            "Espaço insuficiente no Android."
        }
        incoming = Incoming(peer, item, partial, destination)
        update(item, offset, sending = false)
        send(reply("fileOffset", item.id, offset))
    }

    private fun sendChunk(out: Outgoing, offset: Long) {
        val item = out.item
        update(item, offset, sending = true)
        if (offset == item.size) {
            send(reply("fileDone", item.id))
            return
        }
        val count = minOf(Wire.CHUNK.toLong(), item.size - offset).toInt()
        val bytes = ByteArray(count)
        RandomAccessFile(out.file, "r").use {
            it.seek(offset)
            it.readFully(bytes)
        }
        out.expected = offset + count
        send(reply("fileData", item.id, offset).put("data", Wire.encode(bytes)))
    }

    private fun append(record: Incoming, message: JSONObject) {
        val offset = message.optLong("offset", -1)
        val chunk = Wire.decode(message.getString("data"))
        require(offset == record.partial.length() && chunk.size in 1..Wire.CHUNK && offset + chunk.size <= record.item.size)
        FileOutputStream(record.partial, true).use { it.write(chunk) }
        val next = offset + chunk.size
        update(record.item, next, sending = false)
        send(reply("fileAck", record.item.id, next))
    }

    private fun finish(record: Incoming) {
        val item = record.item
        require(record.partial.length() == item.size) { "Arquivo incompleto." }
        val digest = MessageDigest.getInstance("SHA-256")
        record.partial.inputStream().use { input ->
            val buffer = ByteArray(Wire.CHUNK)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        if (!MessageDigest.isEqual(digest.digest(), Wire.secret(item.hash))) {
            record.partial.delete()
            throw IOException("O arquivo falhou na verificação de integridade.")
        }
        if (!record.partial.renameTo(record.destination)) throw IOException("Não foi possível salvar o arquivo.")
        incoming = null
        clearProgress(item.id)
        refreshReceived()
        mutableFeedback.value = "${item.name} recebido."
        send(reply("fileComplete", item.id))
    }

    private fun announce() {
        val out = outgoing.firstOrNull { it.peer == activePeer } ?: return
        out.expected = null
        update(out.item, 0, sending = true)
        val offer = out.item.offer()
        if (out.scanPage) offer.put("scanPage", true)
        send(offer)
    }

    private fun send(message: JSONObject): Boolean =
        activePeer?.let { sendTo(it, message) } ?: false

    private fun abort(id: String, description: String) {
        if (incoming?.item?.id == id) incoming = null
        val failed = outgoing.firstOrNull { it.item.id == id }
        if (failed != null) {
            failed.file.delete()
            outgoing.remove(failed)
            failed.onFailure?.invoke(description.ifBlank { "O Mac não conseguiu receber a digitalização." })
            announce()
        }
        clearProgress(id)
        mutableFeedback.value = description
    }

    private fun update(item: Item, offset: Long, sending: Boolean) {
        val updated = Progress(item.id, item.name, item.size, offset, sending)
        mutableProgress.value = mutableProgress.value.filterNot { it.id == item.id } + updated
    }

    private fun clearProgress(id: String) {
        mutableProgress.value = mutableProgress.value.filterNot { it.id == id }
    }

    private fun refreshReceived() {
        mutableReceived.value = root.listFiles().orEmpty().filter { Wire.validID(it.name) }.flatMap { peer ->
            peer.listFiles().orEmpty().mapNotNull { folder ->
                runCatching {
                    val item = parse(JSONObject(File(folder, "offer.json").readText()))
                    val file = File(File(folder, "arquivo"), item.name)
                    if (file.isFile) Received(item, file, peer.name) else null
                }.getOrNull()
            }
        }.sortedByDescending { it.file.lastModified() }
    }

    companion object {
        private fun parse(json: JSONObject): Item {
            val id = json.getString("id")
            val size = json.getLong("size")
            val hash = json.getString("hash")
            require(Wire.validID(id) && size in 0..Wire.MAX_FILE)
            Wire.secret(hash)
            return Item(id, safeName(json.getString("name")), json.optString("mime", "application/octet-stream").take(120), size, hash)
        }

        fun safeName(name: String): String {
            val cleaned = name.take(120).filterNot { it.isISOControl() }
                .replace('/', '_').replace('\\', '_').replace(':', '_').trim().trimStart('.')
            val result = StringBuilder()
            var length = 0
            for (codePoint in cleaned.codePoints().toArray()) {
                val character = String(Character.toChars(codePoint))
                length += character.toByteArray().size
                if (length > 200) break
                result.append(character)
            }
            return result.toString().ifBlank { "Arquivo recebido" }
        }

        private fun reply(type: String, id: String, offset: Long? = null): JSONObject =
            Wire.message(type).put("id", id).also { if (offset != null) it.put("offset", offset) }
    }
}
