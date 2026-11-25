package com.nexus.mastersync.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.nexus.mastersync.protocol.MacPeer
import com.nexus.mastersync.protocol.Wire
import org.json.JSONArray
import java.io.IOException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class PeerVault(context: Context) {
    private val storage = context.getSharedPreferences("trusted-macs-v1", Context.MODE_PRIVATE)
    private val alias = "nexus-peer-vault-v1"
    private val marker = "nexus-peers-v1".toByteArray()

    fun read(): List<MacPeer> {
        val stored = storage.getString("peers", null) ?: return emptyList()
        val bytes = Wire.decode(stored)
        require(bytes.size >= 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(marker)
        val entries = JSONArray(cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8))
        return List(entries.length()) { MacPeer.parse(entries.getJSONObject(it)) }
    }

    fun write(peers: List<MacPeer>) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(marker)
        val entries = JSONArray()
        peers.forEach { entries.put(it.json()) }
        val payload = cipher.iv + cipher.doFinal(entries.toString().toByteArray(Charsets.UTF_8))
        if (!storage.edit().putString("peers", Wire.encode(payload)).commit()) {
            throw IOException("O Android não conseguiu salvar os Macs autorizados.")
        }
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build()
            )
            generateKey()
        }
    }
}
