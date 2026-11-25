package com.nexus.mastersync.services

import org.json.JSONObject

internal data class GalleryQuery(
    val selection: String,
    val values: Array<String>,
    val sortColumns: Array<String>,
    val ascending: Boolean,
    val offset: Int
) {
    companion object {
        const val MEDIA_ONLY = "(media_type = 1 OR media_type = 3)"
        private const val MAX_EPOCH_SECOND = 253_402_300_799L

        fun from(message: JSONObject): GalleryQuery {
            val conditions = mutableListOf(MEDIA_ONLY)
            val values = mutableListOf<String>()
            val album = message.optString("album").take(40)
            val name = message.optString("query").trim().take(120)
            val from = message.optLong("addedFrom").takeIf { it in 1..MAX_EPOCH_SECOND }
            val before = message.optLong("addedBefore").takeIf { it in 1..MAX_EPOCH_SECOND }
            val order = message.optString("order")
            when (message.optString("mime")) {
                "image" -> conditions.add("media_type = 1")
                "video" -> conditions.add("media_type = 3")
            }
            if (album.isNotEmpty()) {
                conditions.add("bucket_id = ?")
                values.add(album)
            }
            if (name.isNotEmpty()) {
                // Bind the pattern separately, and escape SQLite's LIKE wildcards in filenames.
                conditions.add("_display_name LIKE ? ESCAPE '\\'")
                values.add("%" + name.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%")
            }
            if (from != null) {
                conditions.add("date_added >= ?")
                values.add(from.toString())
            }
            if (before != null) {
                conditions.add("date_added < ?")
                values.add(before.toString())
            }
            return GalleryQuery(
                conditions.joinToString(" AND "),
                values.toTypedArray(),
                if (order == "name") arrayOf("_display_name", "_id") else arrayOf("date_added", "_id"),
                order == "name" || order == "oldest",
                message.optInt("offset", 0).coerceIn(0, 200_000)
            )
        }
    }
}
