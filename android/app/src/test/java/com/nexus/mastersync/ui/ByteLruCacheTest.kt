package com.nexus.mastersync.ui

import com.nexus.mastersync.ui.conversation.ByteLruCache
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ByteLruCacheTest {
    private fun cache() = ByteLruCache<String>(maxBytes = 10) { it.length.toLong() }

    @Test fun evictsLeastRecentlyUsedWhenOverBudget() {
        val cache = cache()
        cache.put("a", "1111")
        cache.put("b", "2222")
        cache.get("a")              // a is now the most recent
        cache.put("c", "3333")      // 12 bytes > 10: b goes
        assertEquals("1111", cache.get("a"))
        assertNull(cache.get("b"))
        assertEquals("3333", cache.get("c"))
    }

    @Test fun valueLargerThanTheBudgetIsNotKept() {
        val cache = cache()
        cache.put("big", "x".repeat(20))
        assertNull(cache.get("big"))
    }

    @Test fun replacingAKeyDoesNotLeakItsOldSize() {
        val cache = cache()
        cache.put("a", "1111111")
        cache.put("a", "22")
        cache.put("b", "33333333")  // 2 + 8 = 10 fits only if the old 7 bytes were released
        assertEquals("22", cache.get("a"))
        assertEquals("33333333", cache.get("b"))
    }
}
