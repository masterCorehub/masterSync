package com.nexus.mastersync.services

import org.json.JSONObject

// Only the full edition supplies a listener. A session without one cannot advertise notification access.
interface NotificationRelay {
    fun refresh()
    fun receive(data: JSONObject)
    fun media(command: String): String
}
