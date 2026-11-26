package com.nexus.mastersync.services

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import com.nexus.mastersync.protocol.Wire
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** Icons of launcher apps the Mac pinned, sent on request because the full list would not fit in one frame. */
object LauncherIcons {
    const val MAX = 24
    const val SIZE = 48
    private val component = Regex("""\A[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+\z""")

    fun requested(message: JSONObject): List<String> {
        val array = message.optJSONArray("components") ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optString(it).takeIf(::valid) }.distinct().take(MAX)
    }

    private fun valid(value: String) = value.toByteArray().size <= 220 && component.matches(value)

    /** Renders only components that are real launcher activities on this phone. */
    fun render(context: Context, components: List<String>): JSONArray {
        val manager = context.packageManager
        val launchers = manager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .associateBy { "${it.activityInfo.packageName}/${it.activityInfo.name}" }
        val icons = JSONArray()
        components.forEach { name ->
            val entry = launchers[name] ?: return@forEach
            runCatching {
                val drawable = entry.loadIcon(manager)
                val bitmap = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
                try {
                    drawable.setBounds(0, 0, SIZE, SIZE)
                    drawable.draw(Canvas(bitmap))
                    val output = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                    icons.put(JSONObject().put("component", name).put("data", Wire.encode(output.toByteArray())))
                } finally { bitmap.recycle() }
            }
        }
        return icons
    }
}
