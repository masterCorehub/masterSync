package com.nexus.mastersync.protocol

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap

class Discovery(context: Context) {
    private val manager = context.getSystemService(NsdManager::class.java)
    private val known = ConcurrentHashMap<String, List<InetSocketAddress>>()
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var running = false
    private var resolving = false

    private val listener = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(type: String) = Unit
        @Synchronized
        override fun onStartDiscoveryFailed(type: String, code: Int) = failed()
        override fun onStopDiscoveryFailed(type: String, code: Int) = Unit
        override fun onDiscoveryStopped(type: String) = Unit

        override fun onServiceFound(info: NsdServiceInfo) {
            synchronized(this@Discovery) {
                if (!running || !Wire.validID(info.serviceName)) return
                if (queue.none { it.serviceName == info.serviceName }) queue.addLast(info)
                resolveNext()
            }
        }

        override fun onServiceLost(info: NsdServiceInfo) {
            synchronized(this@Discovery) {
                known.remove(info.serviceName)
                queue.removeAll { it.serviceName == info.serviceName }
            }
        }
    }

    @Synchronized
    fun start() {
        if (running) return
        running = true
        runCatching { manager.discoverServices(Wire.SERVICE, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure { failed() }
    }

    @Synchronized
    fun stop() {
        if (running) runCatching { manager.stopServiceDiscovery(listener) }
        failed()
    }

    fun endpoints(id: String): List<InetSocketAddress> = known[id].orEmpty()

    @Synchronized
    private fun failed() {
        running = false
        queue.clear()
        known.clear()
    }

    // A API legada aceita uma resolução de serviço por vez. A fila serializa os callbacks.
    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (!running || resolving || queue.isEmpty()) return
        val info = queue.removeFirst()
        resolving = true
        runCatching {
            manager.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(service: NsdServiceInfo, error: Int) = resolved(info.serviceName, emptyList())
                override fun onServiceResolved(service: NsdServiceInfo) {
                    val addresses = if (Build.VERSION.SDK_INT >= 34) service.hostAddresses
                        else listOfNotNull(service.host)
                    resolved(info.serviceName, addresses.map { InetSocketAddress(it, service.port) })
                }
            })
        }.onFailure { resolved(info.serviceName, emptyList()) }
    }

    @Synchronized
    private fun resolved(id: String, addresses: List<InetSocketAddress>) {
        if (running && addresses.isNotEmpty()) known[id] = addresses
        resolving = false
        resolveNext()
    }
}
