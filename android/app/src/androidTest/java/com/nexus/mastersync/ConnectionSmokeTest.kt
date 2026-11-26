package com.nexus.mastersync

import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.nexus.mastersync.protocol.Wire
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ConnectionSmokeTest {
    @Test
    fun authenticatesAndTransfersAcrossAnInterruptedSession() = runBlocking<Unit> {
        val encoded = InstrumentationRegistry.getArguments().getString("nexusInvitation")
        assumeNotNull(encoded)
        val invitation = Wire.decode(requireNotNull(encoded)).toString(Charsets.UTF_8)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val nexus = (instrumentation.targetContext.applicationContext as NexusApplication).nexus
        val file = File.createTempFile("nexus-transfer", ".bin", instrumentation.targetContext.cacheDir)
        try {
            instrumentation.runOnMainSync {
                nexus.setVisible(true)
                nexus.update(nexus.options.value.copy(clipboard = true, files = true, autoScan = true))
                nexus.client.pair(invitation)
            }
            val peer = withTimeout(35_000) { nexus.client.status.first { it.connected != null }.connected!! }
            withTimeout(12_000) { nexus.permissions.first { it.files && it.clipboard } }
            val received = withTimeout(12_000) { nexus.lastClip.first { it != null } }
            assertEquals("Olá do Mac", received?.text)
            nexus.client.sendTo(peer.id, Wire.message("clipboard").put("text", "Olá do Android"))
            file.writeBytes(ByteArray(2 * Wire.CHUNK + 91) { (it % 251).toByte() })
            nexus.transfers.offerFile(file, peer.id, "teste.bin", "application/octet-stream")
            val result = withTimeout(35_000) { nexus.transfers.feedback.first { it == "teste.bin enviado." } }
            assertEquals("teste.bin enviado.", result)

            val jpeg = File.createTempFile("nexus-page", ".jpg", instrumentation.targetContext.cacheDir)
            try {
                val bitmap = Bitmap.createBitmap(160, 220, Bitmap.Config.ARGB_8888)
                try {
                    bitmap.eraseColor(Color.WHITE)
                    jpeg.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                } finally { bitmap.recycle() }
                instrumentation.runOnMainSync {
                    nexus.requestBackgroundConnection(true)
                    check(nexus.beginBackgroundStart())
                    nexus.setVisible(false)
                    assertEquals(peer.id, nexus.client.status.value.connected?.id)
                    nexus.setBackground(true)
                    assertEquals(peer.id, nexus.client.status.value.connected?.id)
                    // Stopping the service allows the original disconnect-and-resume test to continue.
                    nexus.setBackground(false)
                }
                assertEquals(null, nexus.client.status.value.connected)
                val destination = nexus.scanDestination(null)
                assertEquals(peer.id, destination)
                val page = Uri.fromFile(jpeg)
                val saved = nexus.saveScan(null, listOf(page, page), destination)
                assertEquals(2, saved.pages.size)
                instrumentation.runOnMainSync { nexus.setVisible(true) }
                val sent = "${nexus.scans.name(saved)} enviado."
                withTimeout(25_000) { nexus.transfers.feedback.first { it == sent } }
            } finally {
                jpeg.delete()
            }
        } finally {
            file.delete()
            instrumentation.runOnMainSync {
                nexus.setBackground(false)
                nexus.setVisible(false)
            }
        }
    }
}
