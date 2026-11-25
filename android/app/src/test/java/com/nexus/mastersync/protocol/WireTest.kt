package com.nexus.mastersync.protocol

import com.nexus.mastersync.services.TransferQueue
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

class WireTest {
    @Test fun framePreservesUtf8AcrossTwoConsecutiveMessages() {
        val sink = ByteArrayOutputStream()
        val output = DataOutputStream(sink)
        Wire.write(output, Wire.message("clipboard").put("text", "Olá do Nexus"))
        Wire.write(output, Wire.message("ping"))
        val input = DataInputStream(ByteArrayInputStream(sink.toByteArray()))
        assertEquals("Olá do Nexus", Wire.read(input).getString("text"))
        assertEquals("ping", Wire.read(input).getString("type"))
    }

    @Test fun rejectsNegativeAndOversizedFramesBeforeReadingBody() {
        for (length in listOf(-1, 0, Wire.MAX_FRAME + 1)) {
            val sink = ByteArrayOutputStream()
            DataOutputStream(sink).writeInt(length)
            val header = DataInputStream(ByteArrayInputStream(sink.toByteArray()))
            assertThrows(IOException::class.java) { Wire.read(header) }
        }
    }

    @Test fun qrRequiresValidPinAndIPv4() {
        val key = Wire.encode(ByteArray(32))
        val id = Wire.id()
        val qr = JSONObject().put("version", 1).put("serverId", id).put("host", "10.0.0.4")
            .put("port", 47525).put("pin", key).put("token", key)
            .put("expiresAt", System.currentTimeMillis() / 1000 + 120)
        assertEquals(id, Invitation.parse(qr.toString()).serverId)
        assertThrows(IllegalArgumentException::class.java) { Invitation.parse(qr.put("host", "http://example.com").toString()) }
        qr.put("host", "10.0.0.4")
        assertThrows(IllegalArgumentException::class.java) { Invitation.parse(qr.put("pin", "").toString()) }
    }

    @Test fun fileNamesAreRestrictedToAPathComponent() {
        assertEquals("___senha", TransferQueue.safeName("../\\:senha"))
        assertEquals("Arquivo recebido", TransferQueue.safeName("."))
    }
}
