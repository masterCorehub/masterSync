package com.nexus.mastersync.protocol

import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.util.Base64
import java.util.UUID

object Wire {
    const val VERSION = 1
    const val MAX_FRAME = 256 * 1024
    const val CHUNK = 64 * 1024
    const val MAX_FILE = 4L * 1024 * 1024 * 1024
    const val SERVICE = "_nexus-sync._tcp."

    fun id() = UUID.randomUUID().toString()
    fun validID(value: String) = runCatching { UUID.fromString(value).toString() == value }.getOrDefault(false)
    fun encode(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
    fun decode(value: String): ByteArray = Base64.getDecoder().decode(value)
    fun secret(value: String) = decode(value).also { require(it.size == 32) }
    fun message(type: String) = JSONObject().put("type", type)

    fun read(input: DataInputStream): JSONObject {
        val length = input.readInt()
        if (length !in 1..MAX_FRAME) throw IOException("Tamanho de mensagem inválido.")
        val body = ByteArray(length)
        input.readFully(body)
        return JSONObject(body.toString(Charsets.UTF_8))
    }

    fun write(output: DataOutputStream, message: JSONObject) {
        val body = message.toString().toByteArray(Charsets.UTF_8)
        if (body.size !in 1..MAX_FRAME) throw IOException("Tamanho de mensagem inválido.")
        output.writeInt(body.size)
        output.write(body)
        output.flush()
    }
}

data class Invitation(
    val serverId: String,
    val host: String,
    val port: Int,
    val pin: String,
    val token: String,
    val expiresAt: Long
) {
    companion object {
        fun parse(text: String): Invitation {
            require(text.length <= 2048)
            val json = JSONObject(text)
            require(json.getInt("version") == Wire.VERSION)
            val id = json.getString("serverId")
            val host = json.getString("host")
            val port = json.getInt("port")
            val expires = json.getLong("expiresAt")
            require(Wire.validID(id) && port in 1..65535 && expires > System.currentTimeMillis() / 1000)
            require(host.isEmpty() || isIPv4(host))
            val pin = json.getString("pin")
            val token = json.getString("token")
            Wire.secret(pin)
            Wire.secret(token)
            return Invitation(id, host, port, pin, token, expires)
        }

        private fun isIPv4(host: String): Boolean {
            val parts = host.split('.')
            return parts.size == 4 && parts.all { part ->
                part.length in 1..3 && part.all { it in '0'..'9' } && part.toInt() in 0..255
            }
        }
    }
}

data class MacPeer(
    val id: String,
    val name: String,
    val host: String,
    val port: Int,
    val pin: String,
    val credential: String,
    val pending: Boolean = false
) {
    fun json(): JSONObject = JSONObject()
        .put("id", id).put("name", name).put("host", host).put("port", port)
        .put("pin", pin).put("credential", credential).put("pending", pending)

    companion object {
        fun parse(json: JSONObject) = MacPeer(
            json.getString("id"), json.getString("name"), json.getString("host"),
            json.getInt("port"), json.getString("pin"), json.getString("credential"), json.optBoolean("pending")
        )
    }
}
