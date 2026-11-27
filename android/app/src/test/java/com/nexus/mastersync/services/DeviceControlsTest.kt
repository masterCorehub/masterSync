package com.nexus.mastersync.services

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceControlsTest {
    @Test fun ringerModeNames() {
        assertEquals("silent", RingerPolicy.name(0))
        assertEquals("vibrate", RingerPolicy.name(1))
        assertEquals("normal", RingerPolicy.name(2))
        assertEquals("normal", RingerPolicy.name(99))
    }

    @Test fun silentNeedsPolicyAccess() {
        assertFalse(RingerPolicy.canSet("silent", policyAccess = false))
        assertTrue(RingerPolicy.canSet("silent", policyAccess = true))
        assertTrue(RingerPolicy.canSet("normal", policyAccess = false))
    }

    @Test fun turningSilentOffGoesBackToNormal() {
        assertEquals("silent", RingerPolicy.target(wantSilent = true))
        assertEquals("normal", RingerPolicy.target(wantSilent = false))
    }

    @Test fun modeConstantsMatchAudioManager() {
        assertEquals(0, RingerPolicy.modeOf("silent"))
        assertEquals(1, RingerPolicy.modeOf("vibrate"))
        assertEquals(2, RingerPolicy.modeOf("normal"))
        assertNull(RingerPolicy.modeOf("loud"))
    }

    @Test fun commandReadsControlAndFlag() {
        val torch = DeviceControls.parse(JSONObject().put("control", "torch").put("enabled", true))
        assertEquals(DeviceControls.Command("torch", true), torch)
        val ringer = DeviceControls.parse(JSONObject().put("control", "ringer").put("enabled", false))
        assertEquals(DeviceControls.Command("ringer", false), ringer)
    }

    @Test fun commandRejectsUnknownOrIncomplete() {
        assertNull(DeviceControls.parse(JSONObject().put("control", "hotspot").put("enabled", true)))
        assertNull(DeviceControls.parse(JSONObject().put("control", "torch")))
        assertNull(DeviceControls.parse(JSONObject()))
    }
}
