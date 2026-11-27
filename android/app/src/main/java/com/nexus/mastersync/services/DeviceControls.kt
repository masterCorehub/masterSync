package com.nexus.mastersync.services

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.app.NotificationManager
import android.os.Handler
import android.os.Looper
import com.nexus.mastersync.protocol.Wire
import org.json.JSONObject

/** The phone's ringer modes by name, and what may be set without extra permission. Pure, so it can be unit tested. */
object RingerPolicy {
    const val SILENT = "silent"
    const val VIBRATE = "vibrate"
    const val NORMAL = "normal"

    // AudioManager.RINGER_MODE_SILENT / VIBRATE / NORMAL
    fun name(mode: Int) = when (mode) { 0 -> SILENT; 1 -> VIBRATE; else -> NORMAL }
    fun modeOf(name: String): Int? = when (name) { SILENT -> 0; VIBRATE -> 1; NORMAL -> 2; else -> null }

    /** Silent mode needs the Do Not Disturb access the app already asks for; normal and vibrate do not. */
    fun canSet(target: String, policyAccess: Boolean) = target != SILENT || policyAccess

    fun target(wantSilent: Boolean) = if (wantSilent) SILENT else NORMAL
}

/** The flashlight and the ringer, driven from the Mac. */
class DeviceControls(private val context: Context) {
    data class Command(val control: String, val enabled: Boolean)

    private val handler = Handler(Looper.getMainLooper())
    private val camera = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    private var torchOn = false
    private var watching = false

    private val torchId: String? by lazy {
        runCatching {
            camera?.cameraIdList?.firstOrNull { id ->
                val info = camera.getCameraCharacteristics(id)
                info.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                    info.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            }
        }.getOrNull()
    }

    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchId) torchOn = enabled
        }
    }

    private fun watchTorch() {
        if (watching) return
        watching = true
        runCatching { camera?.registerTorchCallback(torchCallback, handler) }
    }

    fun stop() {
        if (!watching) return
        watching = false
        runCatching { camera?.unregisterTorchCallback(torchCallback) }
    }

    fun state(): JSONObject {
        watchTorch()
        val access = notifications?.isNotificationPolicyAccessGranted == true
        return Wire.message("deviceControlsState")
            .put("torch", torchOn)
            .put("torchAvailable", torchId != null)
            .put("ringer", RingerPolicy.name(audio?.ringerMode ?: 2))
            .put("ringerAllowed", access)
    }

    /** Applies a command and returns what to tell the Mac. */
    fun apply(command: Command): String = when (command.control) {
        "torch" -> runCatching {
            val id = torchId ?: error("sem lanterna")
            camera?.setTorchMode(id, command.enabled)
            torchOn = command.enabled
            if (command.enabled) "Lanterna acesa." else "Lanterna apagada."
        }.getOrDefault("O Android não conseguiu mudar a lanterna.")
        "ringer" -> {
            val target = RingerPolicy.target(command.enabled)
            if (!RingerPolicy.canSet(target, notifications?.isNotificationPolicyAccessGranted == true)) {
                "Autorize o Não Perturbe no MasterSync do Android para silenciar o celular."
            } else runCatching {
                audio?.ringerMode = RingerPolicy.modeOf(target) ?: 2
                if (command.enabled) "Celular silenciado." else "Som do celular ligado."
            }.getOrDefault("O Android não conseguiu mudar o modo de toque.")
        }
        else -> "Controle desconhecido."
    }

    companion object {
        /** A valid command from the Mac, or null: only torch and ringer, and the flag must be present. */
        fun parse(message: JSONObject): Command? {
            val control = message.optString("control")
            if (control != "torch" && control != "ringer") return null
            if (!message.has("enabled")) return null
            return Command(control, message.optBoolean("enabled"))
        }
    }
}
