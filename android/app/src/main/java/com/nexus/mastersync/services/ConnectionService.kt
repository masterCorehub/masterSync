package com.nexus.mastersync.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import com.nexus.mastersync.MainActivity
import com.nexus.mastersync.NexusApplication
import com.nexus.mastersync.R

class ConnectionService : Service() {
    private val nexus get() = (application as NexusApplication).nexus

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("connection", "Conexão local", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 0, Intent(this, ConnectionService::class.java).setAction("stop"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, "connection")
            .setSmallIcon(R.drawable.ic_nexus)
            .setContentTitle("Nexus masterSync ativo")
            .setContentText("O Nexus está disponível para o Mac na rede local.")
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Parar", stop).build())
            .build()
        val started = runCatching {
            startForeground(1001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        }.onSuccess { nexus.setBackground(true) }.onFailure {
            nexus.note("O Android não permitiu manter a conexão em segundo plano.")
            stopSelf()
        }
        // Resume an already active connection if Android reclaims the process.
        return if (started.isSuccess) START_STICKY else START_NOT_STICKY
    }

    override fun onDestroy() {
        nexus.setBackground(false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
