package com.nexus.mastersync.ui.features

import com.nexus.mastersync.NexusController

enum class FeatureId { Clipboard, Files, Gallery, Notifications, Mirror, Scan, FindPhone, Sms }

enum class StepState { Done, Pending, AwaitingMac }

enum class StepAction { OpenAppSettings, OpenNotificationAccess, RequestGallery, RequestSms, ToggleBackground, EnableFiles }

/** One thing a feature needs. [chip] is the short label shown on Home when this is the first missing step. */
data class Requirement(val label: String, val chip: String, val hint: String?, val state: StepState,
                       val action: StepAction?, val optional: Boolean = false)

sealed interface FeatureStatus {
    data object Off : FeatureStatus
    data object Active : FeatureStatus
    data class Pending(val requirement: Requirement) : FeatureStatus
}

data class Feature(val id: FeatureId, val title: String, val summary: String, val enabled: Boolean,
                   val requirements: List<Requirement>, val status: FeatureStatus)

data class SystemAccess(val camera: Boolean, val mediaFull: Boolean, val mediaPartial: Boolean,
                        val appNotifications: Boolean, val notificationListener: Boolean, val sms: Boolean = false)

fun buildFeatures(options: NexusController.Options, permissions: NexusController.Permissions,
                  connected: Boolean, background: Boolean, access: SystemAccess,
                  notificationRelay: Boolean): List<Feature> {
    fun state(done: Boolean) = if (done) StepState.Done else StepState.Pending
    fun mac(granted: Boolean, path: String) = Requirement("Ligado no Mac", "Ligar no Mac", "No Mac: $path",
        when { !connected -> StepState.AwaitingMac; granted -> StepState.Done; else -> StepState.Pending }, null)
    fun keepConnected(optional: Boolean) = Requirement("Conexão em segundo plano", "Manter conectado",
        if (optional) "Recomendado para funcionar com outro app aberto" else null,
        state(background), StepAction.ToggleBackground, optional)
    val appNotifications = Requirement("Notificações do app", "Permitir avisos", "Configuração do Android",
        state(access.appNotifications), StepAction.OpenAppSettings)

    fun feature(id: FeatureId, title: String, summary: String, enabled: Boolean, requirements: List<Requirement>) =
        Feature(id, title, summary, enabled, requirements, when {
            !enabled -> FeatureStatus.Off
            else -> requirements.firstOrNull { it.state == StepState.Pending && !it.optional }
                ?.let { FeatureStatus.Pending(it) } ?: FeatureStatus.Active
        })

    return listOfNotNull(
        feature(FeatureId.Clipboard, "Área de transferência", "Copie aqui, cole no Mac", options.clipboard, listOf(
            mac(permissions.clipboard, "Celular → Área de transferência"),
            keepConnected(optional = true))),
        feature(FeatureId.Files, "Arquivos", "Envie e receba arquivos", options.files, listOf(
            mac(permissions.files, "Galeria → Arquivos"))),
        feature(FeatureId.Gallery, "Galeria", "Fotos e vídeos no Mac", options.gallery, listOf(
            Requirement("Fotos e vídeos", "Permitir fotos", "Configuração do Android",
                state(access.mediaFull || access.mediaPartial), StepAction.RequestGallery),
            mac(permissions.gallery, "Galeria → Galeria"),
            keepConnected(optional = true))),
        if (notificationRelay) feature(FeatureId.Notifications, "Notificações",
            "Veja e responda avisos do celular no Mac", options.notificationMirror, listOf(
                Requirement("Acesso às notificações", "Dar acesso", "Configuração do Android",
                    state(access.notificationListener), StepAction.OpenNotificationAccess),
                mac(permissions.notifications, "Celular → Notificações"),
                appNotifications,
                keepConnected(optional = false))) else null,
        if (notificationRelay) feature(FeatureId.Sms, "SMS no Mac", "Leia e responda SMS pelo Mac", options.sms, listOf(
            Requirement("Ler e enviar SMS", "Permitir SMS", "Configuração do Android", state(access.sms), StepAction.RequestSms),
            mac(permissions.sms, "SMS"),
            keepConnected(optional = false))) else null,
        feature(FeatureId.Mirror, "Espelhar tela", "Mostre a tela do celular no Mac", options.mirror, listOf(
            appNotifications, keepConnected(optional = false))),
        feature(FeatureId.Scan, "Digitalizar e câmera", "O Mac pede, o celular fotografa", options.remoteScan, listOf(
            Requirement("Câmera", "Permitir câmera", "Configuração do Android", state(access.camera),
                StepAction.OpenAppSettings),
            Requirement("Arquivos no Android", "Ligar Arquivos", null, state(options.files), StepAction.EnableFiles),
            mac(permissions.files, "Galeria → Arquivos"))),
        feature(FeatureId.FindPhone, "Localizar celular", "O Mac faz o celular tocar", options.findPhone, listOf(
            appNotifications))
    )
}
