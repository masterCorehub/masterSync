package com.nexus.mastersync.services

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.nexus.mastersync.NexusApplication

/** Hands a text that just arrived on the phone to the Mac, when SMS sharing is on. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        (context.applicationContext as? NexusApplication)?.nexus?.smsIncoming(intent)
    }
}
