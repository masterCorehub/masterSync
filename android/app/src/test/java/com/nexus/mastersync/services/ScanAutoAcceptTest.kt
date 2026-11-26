package com.nexus.mastersync.services

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanAutoAcceptTest {
    private val id = "3f1d2c4b-5a6e-4f70-8a91-b2c3d4e5f607"

    @Test fun acceptsExpectedIdOnceWithinWindow() {
        val auto = ScanAutoAccept()
        auto.expect(id, 0)
        assertTrue(auto.consume(id, 1000))
        assertFalse(auto.consume(id, 1001))
    }

    @Test fun expiresAfterWindow() {
        val auto = ScanAutoAccept()
        auto.expect(id, 0)
        assertFalse(auto.consume(id, 20_001))
    }

    @Test fun ignoresOtherAndNullIds() {
        val auto = ScanAutoAccept()
        auto.expect(id, 0)
        assertFalse(auto.consume("9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d", 1))
        assertFalse(auto.consume(null, 1))
        assertTrue(auto.consume(id, 2))
    }

    @Test fun rejectsInvalidId() {
        val auto = ScanAutoAccept()
        auto.expect("../x", 0)
        assertFalse(auto.consume("../x", 1))
    }
}
