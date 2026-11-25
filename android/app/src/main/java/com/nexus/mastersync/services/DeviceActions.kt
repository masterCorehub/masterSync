package com.nexus.mastersync.services

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

class DeviceActions(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var lastRing: Long? = null

    fun ring(): String {
        val now = SystemClock.elapsedRealtime()
        if (lastRing?.let { now - it < 12_000 } == true) return "Já há um toque recente no Android."
        return runCatching {
            stop()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val tone = RingtoneManager.getRingtone(context, uri) ?: error("Toque indisponível")
            tone.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build()
            tone.isLooping = true
            ringtone = tone
            lastRing = now
            tone.play()
            handler.postDelayed(::stop, 12_000)
            "Toque iniciado no Android."
        }.getOrDefault("O Android não conseguiu tocar o telefone.")
    }

    fun stop() {
        ringtone?.stop()
        ringtone = null
        handler.removeCallbacksAndMessages(null)
    }
}
