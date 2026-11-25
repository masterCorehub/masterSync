package com.nexus.mastersync.services

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import android.view.WindowManager
import com.nexus.mastersync.MainActivity
import com.nexus.mastersync.NexusApplication
import com.nexus.mastersync.R
import com.nexus.mastersync.protocol.Wire
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.roundToInt

class ScreenMirrorService : Service() {
    private val nexus get() = (application as NexusApplication).nexus
    private val capture = HandlerThread("Nexus screen capture").apply { start() }
    private val worker by lazy { Handler(capture.looper) }
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var scratch: Bitmap? = null
    private var paddedBuffer: ByteBuffer? = null
    private var pendingID: String? = null
    private var lastFrame = 0L
    private var peer: String? = null
    private var longestEdge = 768
    private var fps = 10
    private var quality = 68
    @Volatile private var ending = false

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() { stopSelf() }
        override fun onCapturedContentResize(width: Int, height: Int) {
            if (width > 0 && height > 0 && !ending) runCatching { configure(width, height) }.onFailure { stopSelf() }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            stopSelf()
            return START_NOT_STICKY
        }
        if (projection != null) return START_NOT_STICKY
        val device = intent?.getStringExtra("peer")
        val consent = intent?.let(::consent)
        if (device == null || consent == null || nexus.client.status.value.connected?.id != device) {
            stopSelf()
            return START_NOT_STICKY
        }
        peer = device
        longestEdge = intent.getIntExtra("size", 768).coerceIn(480, 960)
        fps = intent.getIntExtra("fps", 10).coerceIn(4, 15)
        quality = intent.getIntExtra("quality", 68).coerceIn(35, 82)
        runCatching {
            showNotification()
            val manager = getSystemService(MediaProjectionManager::class.java)
            projection = manager.getMediaProjection(Activity.RESULT_OK, consent)
                ?: error("Permissão de espelhamento inválida.")
            projection?.registerCallback(projectionCallback, worker)
            nexus.screenService = this
            nexus.setMirroring(true)
            worker.post {
                runCatching {
                    val (width, height) = displaySize()
                    configure(width, height)
                    nexus.client.sendTo(device, Wire.message("screenActive"))
                }.onFailure { stopSelf() }
            }
        }.onFailure {
            nexus.note("O Android não permitiu iniciar o espelhamento.")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    fun acknowledge(id: String) {
        worker.post { if (pendingID == id) pendingID = null }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= 34) return
        worker.post {
            if (display != null && !ending) {
                val (width, height) = displaySize()
                runCatching { configure(width, height) }.onFailure { stopSelf() }
            }
        }
    }

    override fun onDestroy() {
        ending = true
        peer?.let { nexus.client.sendTo(it, Wire.message("screenEnded").put("message", "Espelhamento encerrado no Android.")) }
        if (nexus.screenService === this) nexus.screenService = null
        nexus.setMirroring(false)
        worker.post {
            display?.release()
            reader?.close()
            scratch?.recycle()
            projection?.unregisterCallback(projectionCallback)
            projection?.stop()
            capture.quitSafely()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun configure(width: Int, height: Int) {
        val scale = (longestEdge.toDouble() / maxOf(width, height)).coerceAtMost(1.0)
        val w = (width * scale).roundToInt().coerceAtLeast(2)
        val h = (height * scale).roundToInt().coerceAtLeast(2)
        if (reader?.width == w && reader?.height == h) return
        val next = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        val density = resources.displayMetrics.densityDpi
        try {
            val existing = display
            if (existing == null) {
                display = projection?.createVirtualDisplay("Nexus masterSync", w, h, density,
                    VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, next.surface, null, worker)
                    ?: error("Não foi possível compartilhar a tela.")
            } else {
                existing.resize(w, h, density)
                existing.surface = next.surface
            }
            reader?.close()
            reader = next
            next.setOnImageAvailableListener({ source ->
                if (!ending && source === reader) runCatching {
                    source.acquireLatestImage()?.use { frame(it) }
                }.onFailure { stopSelf() }
            }, worker)
        } catch (failure: Exception) {
            next.close()
            throw failure
        }
    }

    private fun frame(image: Image) {
        val device = peer ?: return
        val now = SystemClock.elapsedRealtime()
        if (nexus.client.status.value.connected?.id != device) { stopSelf(); return }
        if (now - lastFrame < 1000 / fps || pendingID != null && now - lastFrame < 2500) return
        lastFrame = now
        val plane = image.planes[0]
        val paddedWidth = plane.rowStride / plane.pixelStride
        val padded = scratch?.takeIf { it.width == paddedWidth && it.height == image.height }
            ?: Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888).also {
                scratch?.recycle()
                scratch = it
            }
        plane.buffer.rewind()
        if (plane.buffer.remaining() >= padded.byteCount) {
            padded.copyPixelsFromBuffer(plane.buffer)
        } else {
            // Some image planes omit the padding after the last row.
            val buffer = paddedBuffer?.takeIf { it.capacity() == padded.byteCount }
                ?: ByteBuffer.allocateDirect(padded.byteCount).also { paddedBuffer = it }
            buffer.clear()
            buffer.put(plane.buffer)
            buffer.rewind()
            padded.copyPixelsFromBuffer(buffer)
        }
        val visible = Bitmap.createBitmap(padded, 0, 0, image.width, image.height)
        try {
            val output = ByteArrayOutputStream()
            visible.compress(Bitmap.CompressFormat.JPEG, quality, output)
            if (output.size() > 84_000) {
                output.reset()
                visible.compress(Bitmap.CompressFormat.JPEG, 33, output)
            }
            if (output.size() > 84_000) return
            val id = Wire.id()
            if (nexus.client.sendTo(device, Wire.message("screenFrame").put("id", id)
                .put("data", Wire.encode(output.toByteArray())))) pendingID = id
        } finally {
            if (visible !== padded) visible.recycle()
        }
    }

    private fun showNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("screen", "Espelhamento de tela", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 11, Intent(this, MainActivity::class.java).putExtra("open-share", true),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 12, Intent(this, ScreenMirrorService::class.java).setAction("stop"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, "screen").setSmallIcon(R.drawable.ic_nexus)
            .setContentTitle("Nexus está compartilhando sua tela").setContentText("O Mac conectado pode ver a tela autorizada.")
            .setOngoing(true).setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Parar", stop).build()).build()
        startForeground(1003, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
    }

    @Suppress("DEPRECATION")
    private fun consent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra("consent", Intent::class.java)
        else intent.getParcelableExtra("consent")

    @Suppress("DEPRECATION")
    private fun displaySize(): Pair<Int, Int> {
        val windows = getSystemService(WindowManager::class.java)
        return if (Build.VERSION.SDK_INT >= 30) {
            val bounds = windows.maximumWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val metrics = android.util.DisplayMetrics()
            windows.defaultDisplay.getRealMetrics(metrics)
            metrics.widthPixels to metrics.heightPixels
        }
    }
}
