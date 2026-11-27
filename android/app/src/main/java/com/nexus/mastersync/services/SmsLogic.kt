package com.nexus.mastersync.services

import org.json.JSONArray
import org.json.JSONObject

/** One row of the phone's SMS box. */
data class SmsRow(val id: Long, val threadId: Long, val address: String, val body: String, val date: Long, val type: Int, val read: Boolean) {
    companion object {
        const val INBOX = 1
        const val SENT = 2
        const val OUTBOX = 4
    }
}

data class SmsThreadInfo(val id: String, val address: String, val snippet: String, val date: Long, val unread: Int, val count: Int) {
    fun toJson(name: String?): JSONObject = JSONObject().put("id", id).put("address", address).put("snippet", snippet)
        .put("date", date).put("unread", unread).put("count", count).also { if (!name.isNullOrBlank()) it.put("name", name) }
}

data class SmsEntryJson(val id: String, val threadId: String, val address: String, val body: String, val date: Long, val outgoing: Boolean) {
    fun toJson(): JSONObject = JSONObject().put("id", id).put("threadId", threadId).put("address", address)
        .put("body", body).put("date", date).put("outgoing", outgoing)
}

object SmsGrouping {
    /** Conversations from a flat list of messages: newest first, each with its newest text and its unread count. */
    fun threads(rows: List<SmsRow>): List<SmsThreadInfo> = rows.groupBy { it.threadId }.map { (id, group) ->
        val newest = group.maxByOrNull { it.date }!!
        SmsThreadInfo(
            id = id.toString(), address = newest.address, snippet = SmsText.snippet(newest.body), date = newest.date,
            unread = group.count { it.type == SmsRow.INBOX && !it.read }, count = group.size)
    }.sortedByDescending { it.date }

    fun entry(row: SmsRow) = SmsEntryJson(row.id.toString(), row.threadId.toString(), row.address, SmsText.body(row.body), row.date,
        outgoing = row.type == SmsRow.SENT || row.type == SmsRow.OUTBOX)
}

object SmsAddress {
    private val allowed = Regex("^[+0-9 ()\\-]{3,32}$")

    /** Digits and a leading plus only, as the phone wants them. */
    fun clean(address: String) = address.filter { it.isDigit() || it == '+' }

    /** A real phone number or short code. Names like "NUBANK" can be read but never answered. */
    fun canSendTo(address: String): Boolean {
        if (!allowed.matches(address)) return false
        return clean(address).count { it.isDigit() } in 3..15
    }
}

object SmsText {
    const val MAX_OUTGOING = 1000
    const val MAX_BODY = 1000

    fun outgoing(text: String): String? {
        val trimmed = text.trim()
        return if (trimmed.isEmpty() || trimmed.length > MAX_OUTGOING) null else trimmed
    }

    fun body(text: String) = text.take(MAX_BODY)

    fun snippet(text: String) = text.replace(Regex("\\s+"), " ").trim().take(120)
}

object SmsPayload {
    /** As many messages as fit in [budget] bytes of JSON, in order, so a page never exceeds the protocol's frame limit. */
    fun fit(entries: List<SmsEntryJson>, budget: Int): JSONArray {
        val array = JSONArray()
        var used = 2
        for (entry in entries) {
            val json = entry.toJson()
            val size = json.toString().toByteArray(Charsets.UTF_8).size + 1
            if (used + size > budget) break
            array.put(json)
            used += size
        }
        return array
    }
}
