package com.nexus.mastersync.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class TabTest {
    @Test fun restoresNewNames() =
        Tab.entries.forEach { assertEquals(it, Tab.restore(it.name)) }

    @Test fun restoresOldNames() {
        assertEquals(Tab.Conversation, Tab.restore("Share"))
        assertEquals(Tab.Connection, Tab.restore("Devices"))
        assertEquals(Tab.Connection, Tab.restore("Settings"))
        assertEquals(Tab.Home, Tab.restore("Scan"))
        assertEquals(Tab.Home, Tab.restore(null))
        assertEquals(Tab.Home, Tab.restore("???"))
    }
}
