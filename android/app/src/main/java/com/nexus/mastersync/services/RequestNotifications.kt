package com.nexus.mastersync.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.nexus.mastersync.MainActivity
import com.nexus.mastersync.R

// These notifications belong to Nexus and never read alerts from other apps.
object RequestNotifications {
    fun notifyScreen(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("screen-requests", "Solicitações de espelhamento", NotificationManager.IMPORTANCE_DEFAULT))
        val pending = PendingIntent.getActivity(context, 16, Intent(context, MainActivity::class.java)
            .putExtra("open-share", true), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        manager.notify(1004, Notification.Builder(context, "screen-requests")
            .setSmallIcon(R.drawable.ic_nexus).setContentTitle("O Mac solicitou compartilhar sua tela")
            .setContentText("Toque para aceitar ou recusar no Nexus.").setContentIntent(pending)
            .setAutoCancel(true).build())
    }

    fun notifyPhoto(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("camera-request", "Pedidos de foto", NotificationManager.IMPORTANCE_DEFAULT))
        val pending = PendingIntent.getActivity(context, 17, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        manager.notify(1005, Notification.Builder(context, "camera-request")
            .setSmallIcon(R.drawable.ic_nexus).setContentTitle("O Mac solicitou uma foto")
            .setContentText("Toque para abrir o pedido no MasterSync.").setContentIntent(pending)
            .setAutoCancel(true).build())
    }

    fun notifyScan(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("scan", "Solicitações de scanner", NotificationManager.IMPORTANCE_DEFAULT))
        val pending = PendingIntent.getActivity(context, 3, Intent(context, MainActivity::class.java)
            .putExtra("open-scan", true), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        manager.notify(1002, Notification.Builder(context, "scan")
            .setSmallIcon(R.drawable.ic_nexus).setContentTitle("O Mac solicitou uma digitalização")
            .setContentText("Toque para aceitar ou recusar no Nexus.").setContentIntent(pending)
            .setAutoCancel(true).build())
    }
}
