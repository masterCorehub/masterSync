package com.nexus.mastersync

import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Bitmap
import android.graphics.Color
import android.os.PersistableBundle
import android.os.SystemClock
import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ADBClipboardSourceTest {
    @Test
    fun copiesTextAndPrivateImageWithoutLaunchingAnActivity() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nexusUsbClipboard") == "1")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        val file = File(context.cacheDir, "nexus-clipboard/usb-fixture.png")
        file.parentFile?.mkdirs()
        try {
            val image = Bitmap.createBitmap(160, 120, Bitmap.Config.ARGB_8888)
            image.eraseColor(Color.rgb(53, 126, 184))
            file.outputStream().use { check(image.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            image.recycle()
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.clipboard", file)
            instrumentation.runOnMainSync {
                clipboard.setPrimaryClip(ClipData.newPlainText("Nexus", "Cópia USB de teste"))
            }
            SystemClock.sleep(500)
            instrumentation.runOnMainSync {
                val sensitive = ClipData.newPlainText("Nexus", "Marcado como sensível")
                sensitive.description.extras = PersistableBundle().apply {
                    putBoolean("android.content.extra.IS_SENSITIVE", true)
                }
                clipboard.setPrimaryClip(sensitive)
            }
            SystemClock.sleep(500)
            instrumentation.runOnMainSync {
                clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, "Imagem USB de teste", uri))
            }
            SystemClock.sleep(3000)
        } finally { file.delete() }
    }
}
