package com.nexus.mastersync.ui.conversation

/** A least-recently-used cache bounded by the bytes its values hold, so decoded images cannot pile up. */
class ByteLruCache<V : Any>(private val maxBytes: Long, private val sizeOf: (V) -> Long) {
    private val entries = LinkedHashMap<String, V>(16, 0.75f, true)
    private var bytes = 0L

    @Synchronized fun get(key: String): V? = entries[key]

    @Synchronized fun put(key: String, value: V) {
        entries.remove(key)?.let { bytes -= sizeOf(it) }
        val size = sizeOf(value)
        if (size > maxBytes) return
        entries[key] = value
        bytes += size
        val iterator = entries.entries.iterator()
        while (bytes > maxBytes && iterator.hasNext()) {
            val eldest = iterator.next()
            bytes -= sizeOf(eldest.value)
            iterator.remove()
        }
    }
}
