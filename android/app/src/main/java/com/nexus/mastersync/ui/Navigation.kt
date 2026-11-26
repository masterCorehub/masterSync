package com.nexus.mastersync.ui

enum class Tab(val label: String) {
    Home("Início"), Conversation("Conversa"), Connection("Conexão");

    companion object {
        /** Restores a saved tab, mapping names from the previous navigation so an app update never fails to restore. */
        fun restore(name: String?): Tab = entries.firstOrNull { it.name == name } ?: when (name) {
            "Share" -> Conversation
            "Devices", "Settings" -> Connection
            else -> Home
        }
    }
}
