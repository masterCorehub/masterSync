package com.nexus.mastersync

import android.app.KeyguardManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.PowerManager
import android.provider.MediaStore
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.nexus.mastersync.protocol.Wire
import com.nexus.mastersync.services.ConnectionService
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GalleryClipboardSmokeTest {
    @Test
    fun automaticImageCopyAndGalleryWhenScreenIsOff() = runBlocking<Unit> {
        val args = InstrumentationRegistry.getArguments()
        val standardKeyboard = args.getString("nexusStandardKeyboard") == "1"
        val encoded = args.getString("nexusInvitation")
        assumeNotNull(encoded)
        val invite = Wire.decode(requireNotNull(encoded)).toString(Charsets.UTF_8)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val nexus = (context.applicationContext as NexusApplication).nexus
        val resolver = context.contentResolver
        val name = "Nexus_100%_conexao.png"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Nexus Smoke/")
        }
        val photo = checkNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
        try {
            val image = Bitmap.createBitmap(320, 230, Bitmap.Config.ARGB_8888)
            image.eraseColor(Color.rgb(69, 78, 196))
            resolver.openOutputStream(photo)!!.use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            image.recycle()
            val activity = instrumentation.startActivitySync(
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ) as MainActivity
            try {
                instrumentation.runOnMainSync {
                    activity.startForegroundService(Intent(activity, ConnectionService::class.java))
                    nexus.update(nexus.options.value.copy(gallery = true, files = true, clipboard = true))
                    nexus.client.pair(invite)
                }
                val peer = withTimeout(35_000) { nexus.client.status.first { it.connected != null }.connected!! }
                withTimeout(12_000) { nexus.background.first { it } }
                withTimeout(12_000) { nexus.keyboardSelected.first { it == !standardKeyboard } }
                withTimeout(12_000) { nexus.permissions.first { it.gallery && it.files && (standardKeyboard || it.clipboardImages) } }

                suspend fun waitForFocus(expected: Boolean) {
                    withTimeout(10_000) {
                        var matched = false
                        while (!matched) {
                            instrumentation.runOnMainSync {
                                val state = if (expected) Lifecycle.State.RESUMED else Lifecycle.State.CREATED
                                matched = activity.hasWindowFocus() == expected && activity.lifecycle.currentState == state
                            }
                            if (!matched) delay(100)
                        }
                    }
                }

                suspend fun goHome() {
                    instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_HOME").close()
                    waitForFocus(false)
                }

                suspend fun reopenNexus() {
                    instrumentation.uiAutomation.executeShellCommand(
                        "am start -n ${context.packageName}/.MainActivity"
                    ).close()
                    waitForFocus(true)
                }

                // Return to Home so the Android app no longer owns the focused window.
                goHome()
                val clipboard = context.getSystemService(ClipboardManager::class.java)
                if (standardKeyboard) {
                    instrumentation.runOnMainSync {
                        clipboard.setPrimaryClip(ClipData.newPlainText("Teste", "Cópia com teclado padrão"))
                    }
                    reopenNexus()
                    // The test Mac enables clipboard only after the Nexus window is focused.
                    assertTrue(!nexus.permissions.value.clipboard)
                    assertTrue(nexus.client.sendTo(peer.id, Wire.message("qaClipboardFocused")))
                    withTimeout(15_000) { nexus.lastClip.first { it?.text == "Texto do Mac de teste" } }
                    goHome()
                }
                instrumentation.runOnMainSync {
                    clipboard.setPrimaryClip(ClipData.newUri(resolver, "Foto copiada", photo))
                }
                if (standardKeyboard) {
                    reopenNexus()
                    goHome()
                    assertTrue(nexus.client.sendTo(peer.id, Wire.message("qaClipboardBackground")))
                }
                withTimeout(15_000) { nexus.lastClip.first { it?.image == true } }
                if (standardKeyboard) return@runBlocking

                // Keep the foreground connection, but let the emulator turn off and lock its display.
                instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_SLEEP").close()
                withTimeout(10_000) {
                    while (context.getSystemService(PowerManager::class.java).isInteractive ||
                        !context.getSystemService(KeyguardManager::class.java).isKeyguardLocked) delay(100)
                }
                assertTrue(nexus.client.sendTo(peer.id, Wire.message("qaGalleryReady").put("name", name)))
                val sent = withTimeout(25_000) { nexus.transfers.feedback.first { it.contains("enviado.") } }
                assertTrue(sent.startsWith(name))
                instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_WAKEUP").close()
            } finally {
                instrumentation.runOnMainSync { activity.finish() }
            }
        } finally {
            context.stopService(Intent(context, ConnectionService::class.java))
            resolver.delete(photo, null, null)
            instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_WAKEUP").close()
        }
    }
}
