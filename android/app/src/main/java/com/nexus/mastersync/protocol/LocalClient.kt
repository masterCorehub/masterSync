package com.nexus.mastersync.protocol

import android.content.Context
import android.os.Build
import com.nexus.mastersync.security.PeerVault
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel as MessageQueue
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Inet6Address
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SSLHandshakeException

class LocalClient(context: Context, private val onMessage: (String, JSONObject) -> Unit) {
    data class Status(
        val title: String = "Nenhum Mac conectado",
        val info: String = "Gere um QR em Dispositivos no Mac.",
        val connected: MacPeer? = null,
        val peers: List<MacPeer> = emptyList()
    )

    private data class Request(val peer: MacPeer, val invitation: Invitation?)
    private data class Channel(val peer: String, val raw: Socket, val messages: MessageQueue<JSONObject> = MessageQueue(32))

    private val vault = PeerVault(context)
    private val prefs = context.getSharedPreferences("connection", Context.MODE_PRIVATE)
    private val deviceId = prefs.getString("device-id", null) ?: Wire.id().also {
        check(prefs.edit().putString("device-id", it).commit())
    }
    private val discovery = Discovery(context)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val generation = AtomicLong()
    private var peers: List<MacPeer> = emptyList()
    private var vaultFailure = false
    private val mutableStatus = MutableStateFlow(Status())
    val status = mutableStatus.asStateFlow()
    private var job: Job? = null
    private var raw: Socket? = null
    private var channel: Channel? = null
    private var enabled = false
    @Volatile
    private var pairingDoor: Invitation? = null

    init {
        runCatching { vault.read() }.onSuccess { peers = it }
            .onFailure { vaultFailure = true }
        publish(loggedOut())
    }

    @Synchronized
    fun start() {
        if (enabled) return
        enabled = true
        discovery.start()
        val peer = selected()
        if (peer != null) {
            val invitation = pairingDoor?.takeIf { it.serverId == peer.id }
            begin(Request(peer, invitation))
        }
    }

    @Synchronized
    fun suspendConnection() {
        enabled = false
        cancelConnection()
        discovery.stop()
        publish(loggedOut())
    }

    @Synchronized
    fun pair(scanned: String) {
        if (vaultFailure) return
        val invitation = runCatching { Invitation.parse(scanned) }.getOrElse {
            publish(status.value.copy(info = "O QR é inválido ou expirou. Gere um novo no Mac."))
            return
        }
        val credential = Wire.encode(ByteArray(32).also { SecureRandom().nextBytes(it) })
        val peer = MacPeer(invitation.serverId, "Mac", invitation.host, invitation.port, invitation.pin, credential, true)
        // The pending credential enables reconnect if the network drops after consent on the Mac.
        if (!persist(peers.filterNot { it.id == peer.id && it.pending } + peer)) return
        prefs.edit().putString("selected", peer.id).apply()
        pairingDoor = invitation
        enabled = true
        discovery.start()
        begin(Request(peer, invitation))
    }

    @Synchronized
    fun select(id: String) {
        if (vaultFailure) return
        val peer = peers.lastOrNull { it.id == id } ?: return
        prefs.edit().putString("selected", id).apply()
        begin(Request(peer, pairingDoor?.takeIf { it.serverId == id }))
    }

    @Synchronized
    fun forget(id: String) {
        val current = selected()?.id
        if (!persist(peers.filterNot { it.id == id })) return
        if (pairingDoor?.serverId == id) pairingDoor = null
        if (current == id) {
            prefs.edit().remove("selected").apply()
            cancelConnection()
            publish(loggedOut())
        } else publish(status.value)
    }

    fun send(message: JSONObject): Boolean {
        val current = synchronized(this) { channel } ?: return false
        return current.messages.trySend(message).isSuccess
    }

    fun sendTo(peer: String, message: JSONObject): Boolean {
        val current = synchronized(this) { channel?.takeIf { it.peer == peer } } ?: return false
        return current.messages.trySend(message).isSuccess
    }

    private fun begin(request: Request) {
        cancelConnection()
        val attempt = generation.get()
        job = scope.launch {
            var pause = 600L
            var next = request
            while (isActive && attempt == generation.get()) {
                discovery.start()
                publishIfCurrent(attempt, Status(
                    if (next.invitation != null) "Pareando com o Mac" else "Procurando o Mac",
                    if (next.invitation != null) "Conectando pela rede local." else "Reconexão automática ativada."
                ))
                var authenticated = false
                try {
                    exchange(attempt, next, onSubmitted = {
                        pairingDoor = null
                        next = next.copy(invitation = null)
                    }, onConnected = { peer ->
                        authenticated = true
                        pairingDoor = null
                        next = Request(peer, null)
                    })
                } catch (error: Rejected) {
                    synchronized(this@LocalClient) {
                        if (generation.get() != attempt) return@launch
                        if (next.peer.pending) {
                            persist(peers.filterNot { it.id == next.peer.id && it.pending })
                            pairingDoor = null
                        }
                        publish(Status("Acesso recusado", error.message.orEmpty()))
                    }
                    break
                } catch (_: SSLHandshakeException) {
                    publishIfCurrent(attempt, Status("Identidade do Mac não confirmada",
                        "Confira a data dos aparelhos ou gere um novo QR diretamente no Mac."))
                    break
                } catch (_: Exception) {
                    val invitation = next.invitation
                    if (invitation != null && invitation.expiresAt <= System.currentTimeMillis() / 1000) {
                        pairingDoor = null
                        next = next.copy(invitation = null)
                    }
                    publishIfCurrent(attempt, Status("Mac desconectado",
                        if (authenticated) "Tentando reconectar." else "Confira se o Mac está ativo na mesma rede."))
                }
                if (authenticated) pause = 600
                delay(pause)
                pause = (pause * 2).coerceAtMost(10_000)
            }
        }
    }

    private fun exchange(attempt: Long, request: Request, onSubmitted: () -> Unit, onConnected: (MacPeer) -> Unit) {
        val peer = request.peer
        val discovered = discovery.endpoints(peer.id)
        val direct = peer.host.takeIf { it.isNotEmpty() }?.let { InetSocketAddress(it, peer.port) }
        // A leitura da presença DNS-SD pode chegar depois da primeira tentativa.
        val candidates = if (peer.host == "127.0.0.1") listOfNotNull(direct) else discovered + listOfNotNull(direct)
        val endpoints = candidates.distinct().filter { localEndpoint(it, peer.host == "127.0.0.1") }
        var lastError: Exception = IOException("Mac ainda não descoberto.")
        for (endpoint in endpoints) {
            var authSent = false
            Socket().use { socket ->
                synchronized(this) {
                    if (attempt != generation.get()) return
                    raw = socket
                }
                try {
                    PinnedSocket.connect(socket, endpoint, peer.pin).use { tls ->
                        val input = DataInputStream(BufferedInputStream(tls.inputStream))
                        val output = DataOutputStream(BufferedOutputStream(tls.outputStream))
                        val ticket = request.invitation
                        tls.soTimeout = if (ticket == null) 8_000 else (
                            ticket.expiresAt * 1000 - System.currentTimeMillis() + 5000
                        ).coerceIn(5_000, 185_000).toInt()
                        val auth = Wire.message(if (ticket != null) "pair" else "resume")
                            .put("version", Wire.VERSION).put("serverId", peer.id)
                            .put("id", deviceId).put("credential", peer.credential)
                        if (ticket != null) {
                            auth.put("token", ticket.token)
                                .put("name", Build.MODEL.take(80))
                                .put("model", "${Build.MANUFACTURER} ${Build.MODEL}".take(80))
                            publishIfCurrent(attempt, Status("Confirme no Mac", "Aguardando autorização do novo dispositivo."))
                        }
                        Wire.write(output, auth)
                        authSent = true
                        if (ticket != null) onSubmitted()
                        val reply = Wire.read(input)
                        if (reply.optString("type") == "reject") throw Rejected(reply.optString("message"))
                        if (reply.optString("type") != "accepted" || reply.optInt("version") != Wire.VERSION ||
                            reply.optString("serverId") != peer.id) throw IOException("Resposta de autenticação inválida.")
                        val accepted = peer.copy(name = reply.optString("name").take(80), pending = false)
                        val current = Channel(peer.id, socket)
                        synchronized(this) {
                            if (attempt != generation.get()) return
                            if (accepted != peer && !persist(peers.filterNot { it.id == peer.id } + accepted)) {
                                throw Rejected("O Android não conseguiu guardar a autorização.")
                            }
                            channel = current
                            onConnected(accepted)
                            publish(Status("Mac conectado", "Sincronização local ativa.", connected = accepted))
                        }
                        tls.soTimeout = 26_000
                        val writer = scope.launch {
                            runCatching {
                                for (message in current.messages) Wire.write(output, message)
                            }.onFailure { runCatching { current.raw.close() } }
                        }
                        val ping = scope.launch {
                            while (isActive) {
                                delay(8_000)
                                if (!current.messages.trySend(Wire.message("ping")).isSuccess) {
                                    current.raw.close()
                                    break
                                }
                            }
                        }
                        try {
                            while (attempt == generation.get()) {
                                val incoming = Wire.read(input)
                                when (incoming.optString("type")) {
                                    "reject" -> throw Rejected(incoming.optString("message"))
                                    "pong" -> Unit
                                    else -> onMessage(accepted.id, incoming)
                                }
                            }
                        } finally {
                            ping.cancel()
                            current.messages.close()
                            writer.cancel()
                            synchronized(this) { if (channel === current) channel = null }
                        }
                    }
                    return
                } catch (error: Rejected) {
                    throw error
                } catch (error: Exception) {
                    if (lastError !is SSLHandshakeException || error is SSLHandshakeException) lastError = error
                    if (authSent || error is SocketTimeoutException && request.invitation != null) throw error
                } finally {
                    synchronized(this) { if (raw === socket) raw = null }
                }
            }
        }
        throw lastError
    }

    @Synchronized
    fun selectedAuthorizedMac(): String? = selected()?.takeUnless { it.pending }?.id

    private fun selected(): MacPeer? {
        val id = prefs.getString("selected", null)
        return peers.lastOrNull { it.id == id }
    }

    private fun localEndpoint(endpoint: InetSocketAddress, usb: Boolean): Boolean {
        val ip = endpoint.address ?: return false
        if (ip.isLoopbackAddress) return usb
        return ip.isSiteLocalAddress || ip.isLinkLocalAddress ||
            ip is Inet6Address && (ip.address[0].toInt() and 0xfe) == 0xfc
    }

    private fun cancelConnection() {
        generation.incrementAndGet()
        job?.cancel()
        job = null
        runCatching { raw?.close() }
        raw = null
        channel = null
    }

    private fun persist(newPeers: List<MacPeer>): Boolean {
        if (vaultFailure) return false
        return runCatching { vault.write(newPeers) }.onSuccess { peers = newPeers }
            .onFailure { publish(Status("Armazenamento protegido indisponível", "O Android não conseguiu guardar a autorização.")) }
            .isSuccess
    }

    @Synchronized
    private fun publishIfCurrent(attempt: Long, state: Status) {
        if (attempt == generation.get()) publish(state)
    }

    private fun publish(state: Status) {
        mutableStatus.value = state.copy(peers = peers.distinctBy { it.id }.filterNot { it.pending })
    }

    private fun loggedOut(): Status =
        if (vaultFailure) Status("Armazenamento protegido indisponível", "A autorização guardada não pôde ser aberta pelo Android.")
        else Status()

    private class Rejected(message: String) : IOException(message)
}
