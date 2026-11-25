package com.nexus.mastersync.protocol

import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager

object PinnedSocket {
    fun connect(raw: Socket, address: InetSocketAddress, certificatePin: String): SSLSocket {
        val expected = Wire.secret(certificatePin)
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>, auth: String) {
                throw CertificateException("Certificado de cliente inesperado.")
            }

            override fun checkServerTrusted(chain: Array<X509Certificate>, auth: String) {
                val cert = chain.firstOrNull() ?: throw CertificateException("O Mac não apresentou certificado.")
                cert.checkValidity()
                val actual = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
                // Use o certificado completo do QR como identidade, inclusive se o endereço IP mudar.
                if (!MessageDigest.isEqual(expected, actual)) {
                    throw CertificateException("O certificado do Mac difere do QR.")
                }
            }
        }
        val factory = SSLContext.getInstance("TLSv1.3").apply { init(null, arrayOf(trust), null) }.socketFactory
        raw.tcpNoDelay = true
        raw.soTimeout = 6_000
        raw.connect(address, 4_000)
        return (factory.createSocket(raw, address.hostString, address.port, true) as SSLSocket).apply {
            enabledProtocols = arrayOf("TLSv1.3")
            startHandshake()
        }
    }
}
