package com.nexus.mastersync.services

import com.nexus.mastersync.protocol.Wire

/**
 * A scan the Mac asked for and then opened MasterSync for over ADB. The matching request is accepted
 * without the confirmation dialog, whichever of the two arrives first, within a short window.
 */
class ScanAutoAccept(private val windowMs: Long = 20_000) {
    private var expected: Pair<String, Long>? = null

    @Synchronized fun expect(id: String, now: Long) {
        if (Wire.validID(id)) expected = id to now + windowMs
    }

    @Synchronized fun consume(id: String?, now: Long): Boolean {
        val (wanted, deadline) = expected ?: return false
        if (now > deadline) {
            expected = null
            return false
        }
        if (id == null || id != wanted) return false
        expected = null
        return true
    }
}
