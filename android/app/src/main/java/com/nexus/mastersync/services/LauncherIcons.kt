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
    /** Encoded bytes allowed in one reply, well under the 256 KiB frame (JSON escaping included). */
    const val BUDGET = 180_000
    private val component = Regex("""\A[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+\z""")

    fun requested(message: JSONObject): List<String> {
        val array = message.optJSONArray("components") ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optString(it).takeIf(::valid) }.distinct().take(MAX)
    }

    private fun valid(value: String) = value.toByteArray().size <= 220 && component.matches(value)

    /** Keeps icons in order while they fit the budget; `true` when some were left for a later request. */
    fun withinBudget(icons: List<Pair<String, String>>): Pair<List<Pair<String, String>>, Boolean> {
        var used = 0
        val kept = icons.takeWhile { (component, data) ->
            used += component.length + data.length + 40
            used <= BUDGET
        }
        return kept to (kept.size < icons.size)
    }

    /** Renders only components that are real launcher activities on this phone, as many as fit one frame. */
    fun reply(context: Context, components: List<String>): JSONObject {
        val (kept, more) = withinBudget(render(context, components))
        val icons = JSONArray()
        kept.forEach { (component, data) -> icons.put(JSONObject().put("component", component).put("data", data)) }
        return Wire.message("launcherIcons").put("launcherIcons", icons).put("more", more)
    }

    private fun render(context: Context, components: List<String>): List<Pair<String, String>> {
        val manager = context.packageManager
        val launchers = manager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .associateBy { "${it.activityInfo.packageName}/${it.activityInfo.name}" }
        val icons = mutableListOf<Pair<String, String>>()
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
                    icons += name to Wire.encode(output.toByteArray())
                } finally { bitmap.recycle() }
            }
        }
        return icons
    }
}
