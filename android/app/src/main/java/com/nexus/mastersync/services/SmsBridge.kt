package com.nexus.mastersync.services

import android.content.Context
import android.content.Intent
import com.nexus.mastersync.protocol.Wire
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Answers the Mac's SMS requests and pushes new messages to it. Every request is checked before it touches the SMS box. */
class SmsBridge(context: Context, private val send: (String, JSONObject) -> Unit, private val connectedPeer: () -> String?) {
    private val store = SmsStore(context)
    private val worker = CoroutineScope(Dispatchers.IO.limitedParallelism(1) + SupervisorJob())

    fun available() = store.canRead()

    fun receive(peer: String, message: JSONObject) {
        val id = message.optString("id")
        if (!Wire.validID(id)) return
        worker.launch {
            when (message.optString("type")) {
                "smsThreadsRequest" -> threads(peer, id, message.optInt("offset", 0).coerceIn(0, 5000))
                "smsMessagesRequest" -> messages(peer, id, message.optString("threadId"), message.optInt("offset", 0).coerceIn(0, 200_000))
                "smsSend" -> sendText(peer, id, message.optString("address"), message.optString("text"))
            }
        }
    }

    private fun status(peer: String, id: String, text: String) =
        send(peer, Wire.message("smsStatus").put("id", id).put("message", text))

    private fun threads(peer: String, id: String, offset: Int) {
        if (!store.canRead()) return status(peer, id, "Autorize a leitura de SMS no MasterSync do Android.")
        val (list, more) = store.threads(offset, 30)
        val array = JSONArray()
        list.forEach { array.put(it.toJson(store.name(it.address))) }
        send(peer, Wire.message("smsThreads").put("id", id).put("smsThreads", array).put("more", more))
    }

    private fun messages(peer: String, id: String, threadId: String, offset: Int) {
        if (!store.canRead()) return status(peer, id, "Autorize a leitura de SMS no MasterSync do Android.")
        val thread = threadId.takeIf { it.length in 1..18 && it.all(Char::isDigit) }?.toLongOrNull() ?: return
        val (list, more) = store.messages(thread, offset, 40)
        val fitted = SmsPayload.fit(list, budget = 200_000)
        send(peer, Wire.message("smsMessages").put("id", id).put("threadId", threadId).put("smsEntries", fitted)
            .put("more", more || fitted.length() < list.size))
    }

    private fun sendText(peer: String, id: String, address: String, text: String) {
        val body = SmsText.outgoing(text)
        if (body == null || !SmsAddress.canSendTo(address)) {
            return send(peer, Wire.message("smsSendStatus").put("id", id).put("enabled", false)
                .put("message", "Esse contato não recebe SMS."))
        }
        val (ok, message) = store.send(address, body)
        send(peer, Wire.message("smsSendStatus").put("id", id).put("enabled", ok).put("message", message))
    }

    /** A text just arrived on the phone. */
    fun incoming(intent: Intent) {
        val peer = connectedPeer() ?: return
        worker.launch {
            val entries = store.fromIntent(intent)
            if (entries.isEmpty()) return@launch
            val array = JSONArray()
            entries.forEach { array.put(it.toJson()) }
            send(peer, Wire.message("smsReceived").put("smsEntries", array))
        }
    }
}
