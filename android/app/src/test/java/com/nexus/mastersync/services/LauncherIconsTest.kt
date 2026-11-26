package com.nexus.mastersync.services

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LauncherIconsTest {
    private fun request(vararg components: String) =
        JSONObject().put("components", JSONArray(components.toList()))

    @Test fun keepsValidDistinctInOrder() =
        assertEquals(listOf("a.b/.C", "x.y/z.W"), LauncherIcons.requested(request("a.b/.C", "a.b/.C", "x.y/z.W")))

    @Test fun dropsInvalid() =
        assertTrue(LauncherIcons.requested(request("sem barra", "a/b c", "a/b/c", "a/" + "b".repeat(230))).isEmpty())

    @Test fun capsAtMax() =
        assertEquals(LauncherIcons.MAX, LauncherIcons.requested(request(*Array(30) { "app.n$it/.Main" })).size)

    @Test fun missingArrayIsEmpty() = assertTrue(LauncherIcons.requested(JSONObject()).isEmpty())
}
