package com.nexus.mastersync.services

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.Bundle
import android.os.UserManager
import android.provider.MediaStore
import android.util.Size
import com.nexus.mastersync.protocol.Wire
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

class RemoteGallery(
    private val context: Context,
    private val approved: (String) -> Boolean,
    private val send: (String, JSONObject) -> Boolean,
    private val transfers: TransferQueue
) {
    private val worker = CoroutineScope(Dispatchers.IO.limitedParallelism(1) + SupervisorJob())
    private val syncState = context.getSharedPreferences("gallery-sync-cursor", Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private var watching = false
    @Volatile private var automatic: Pair<String, Long>? = null
    private val scan = Runnable { automatic?.let { (peer, since) -> worker.launch { syncNew(peer, since) } } }
    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { scheduleSync() }
    }
    private val collection = MediaStore.Files.getContentUri("external")

    fun watch(peer: String?, since: Long) {
        val enabled = peer?.let { it to since }
        if (automatic == enabled) return
        automatic = enabled
        if (enabled == null) {
            handler.removeCallbacks(scan)
            if (watching) {
                context.contentResolver.unregisterContentObserver(observer)
                watching = false
            }
        } else {
            if (!watching) {
                context.contentResolver.registerContentObserver(collection, true, observer)
                watching = true
            }
            scheduleSync()
        }
    }

    private fun scheduleSync() {
        handler.removeCallbacks(scan)
        handler.postDelayed(scan, 500)
    }

    private fun syncNew(peer: String, since: Long) {
        if (!approved(peer) || !available() || automatic != (peer to since)) return
        val date = maxOf(since, syncState.getLong("$peer-date", since))
        val id = if (date == since) Long.MAX_VALUE else syncState.getLong("$peer-id", 0)
        runCatching {
            query("${GalleryQuery.MEDIA_ONLY} AND (date_added > ? OR (date_added = ? AND _id > ?))",
                arrayOf(date.toString(), date.toString(), id.toString()), 0, 20, ascending = true) { cursor ->
                while (cursor.moveToNext() && approved(peer) && automatic == (peer to since)) {
                    val item = entry(cursor)
                    val media = item.getLong("id")
                    transfers.offer(ContentUris.withAppendedId(collection, media), peer, item.getString("name"), item.getString("mime"))
                    syncState.edit().putLong("$peer-date", item.getLong("at")).putLong("$peer-id", media).apply()
                }
            }
        }
    }

    fun available(): Boolean = context.getSystemService(UserManager::class.java).isUserUnlocked && canReadMedia()

    private fun canReadMedia(): Boolean = if (Build.VERSION.SDK_INT >= 33) {
        granted(Manifest.permission.READ_MEDIA_IMAGES) || granted(Manifest.permission.READ_MEDIA_VIDEO) ||
            Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    } else granted(Manifest.permission.READ_EXTERNAL_STORAGE)

    fun receive(peer: String, message: JSONObject, filesEnabled: Boolean) = worker.launch {
        if (!approved(peer)) return@launch
        val id = message.optString("id")
        val transferId = message.optString("transferId").takeIf(Wire::validID)
        if (!available()) {
            send(peer, status(id, "Autorize o acesso à galeria no Android.", transferId))
            return@launch
        }
        val result = runCatching {
            when (message.optString("type")) {
                "galleryList" -> list(message)
                "galleryAlbums" -> albums()
                "galleryThumb" -> thumb(id)
                "galleryPreview" -> {
                    require(Wire.validID(id))
                    preview(message.optString("mediaId"))
                }
                "galleryFetch" -> {
                    if (!filesEnabled) {
                        send(peer, status(id, "Ative Arquivos nos dois dispositivos para abrir o original.", transferId))
                        return@launch
                    }
                    val row = row(id)
                    transfers.offer(ContentUris.withAppendedId(collection, row.getLong("id")), peer,
                        row.getString("name"), row.getString("mime"), transferId ?: Wire.id()) { problem ->
                        if (approved(peer)) send(peer, status(id, problem, transferId))
                    }
                    Wire.message("galleryQueued")
                        .put("message", "Preparando o arquivo original no Android…")
                }
                else -> return@launch
            }
        }.getOrElse {
            status(id, "O Android não conseguiu acessar o item selecionado.", transferId)
        }
        transferId?.let { result.put("transferId", it) }
        if (approved(peer) && available()) send(peer, result.put("id", id))
    }

    private fun status(id: String, text: String, transferId: String?) =
        Wire.message("galleryStatus").put("id", id).put("message", text).put("transferId", transferId)

    private fun list(message: JSONObject): JSONObject {
        val filter = GalleryQuery.from(message)
        val media = JSONArray()
        val reply = Wire.message("galleryPage").put("offset", filter.offset)
        query(filter.selection, filter.values, filter.offset, 25, filter.ascending, filter.sortColumns) { cursor ->
            while (media.length() < 24 && cursor.moveToNext()) media.put(entry(cursor))
            reply.put("more", cursor.moveToNext())
        }
        return reply.put("media", media)
    }

    private fun albums(): JSONObject {
        val albums = linkedMapOf<String, String>()
        val fields = arrayOf("bucket_id", "bucket_display_name")
        val args = Bundle().apply { putString(ContentResolver.QUERY_ARG_SQL_SELECTION, GalleryQuery.MEDIA_ONLY) }
        context.contentResolver.query(collection, fields, args, null)?.use { cursor ->
            while (cursor.moveToNext() && albums.size < 128) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: "Álbum"
                albums.putIfAbsent(id, name.take(100))
            }
        }
        return Wire.message("galleryAlbumList").put("albums", JSONArray().also { output ->
            albums.entries.sortedBy { it.value }.forEach { output.put(JSONObject().put("id", it.key).put("name", it.value)) }
        })
    }

    private fun thumb(id: String): JSONObject {
        val entry = row(id)
        val uri = ContentUris.withAppendedId(collection, entry.getLong("id"))
        val image = context.contentResolver.loadThumbnail(uri, Size(224, 160), null)
        try {
            val output = ByteArrayOutputStream()
            image.compress(Bitmap.CompressFormat.JPEG, 78, output)
            return Wire.message("galleryImage").put("data", Wire.encode(output.toByteArray()))
        } finally { image.recycle() }
    }

    private fun preview(id: String): JSONObject {
        val entry = row(id)
        require(entry.getString("mime").startsWith("image/"))
        val uri = ContentUris.withAppendedId(collection, entry.getLong("id"))
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        val image = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val scale = (1440.0 / maxOf(info.size.width, info.size.height)).coerceAtMost(1.0)
            decoder.setTargetSize((info.size.width * scale).roundToInt().coerceAtLeast(1),
                (info.size.height * scale).roundToInt().coerceAtLeast(1))
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        try {
            val output = ByteArrayOutputStream()
            for (quality in listOf(84, 72, 55, 38, 25)) {
                output.reset()
                image.compress(Bitmap.CompressFormat.JPEG, quality, output)
                // JSON and Base64 must fit inside one encrypted protocol message.
                if (output.size() in 1..140 * 1024) {
                    return Wire.message("galleryPreviewImage").put("mediaId", id).put("data", Wire.encode(output.toByteArray()))
                }
            }
            error("Prévia maior que o limite.")
        } finally { image.recycle() }
    }

    private fun row(id: String): JSONObject {
        val number = id.toLongOrNull()?.takeIf { it > 0 } ?: error("Mídia inválida.")
        var found: JSONObject? = null
        query("${GalleryQuery.MEDIA_ONLY} AND _id = ?", arrayOf(number.toString()), 0, 1) { cursor ->
            if (cursor.moveToFirst()) found = entry(cursor)
        }
        return found ?: error("Mídia indisponível.")
    }

    private fun query(selection: String, values: Array<String>, offset: Int, limit: Int,
                      ascending: Boolean = false, sortColumns: Array<String> = arrayOf("date_added", "_id"),
                      read: (android.database.Cursor) -> Unit) {
        val args = Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, values)
            putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, sortColumns)
            putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, if (ascending) ContentResolver.QUERY_SORT_DIRECTION_ASCENDING
                else ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
        }
        context.contentResolver.query(collection, columns, args, null)?.use(read)
    }

    private fun entry(cursor: android.database.Cursor): JSONObject =
        JSONObject().put("id", cursor.getLong(0).toString())
            .put("name", cursor.getString(1)?.take(120) ?: "Mídia")
            .put("mime", cursor.getString(2)?.take(100) ?: "application/octet-stream")
            .put("album", cursor.getString(3)?.take(100) ?: "Álbum")
            .put("at", cursor.getLong(4)).put("size", cursor.getLong(5))

    private fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private companion object {
        val columns = arrayOf("_id", "_display_name", "mime_type", "bucket_display_name", "date_added", "_size")
    }
}
