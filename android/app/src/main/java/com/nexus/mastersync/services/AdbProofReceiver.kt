package com.nexus.mastersync.services

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.nexus.mastersync.NexusApplication

class AdbProofReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nonce = intent.getStringExtra("nonce") ?: return
        val nexus = (context.applicationContext as NexusApplication).nexus
        // The shell may verify the nonce once. The receiver never reveals it.
        if (isOrderedBroadcast && nexus.verifyAdbProof(nonce)) resultCode = 1
    }
}
